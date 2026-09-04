//
//  NFCRequestEmulation.swift
//  macadamia
//
//  Receiving ecash over NFC via HCE card emulation.
//
//  Emulates an NFC Forum Type 4 NDEF tag via CoreNFC's CardSession that
//  carries a Cashu payment request as a single NDEF Text record. A payer
//  device (e.g. macadamia's Contactless view or a Numo-spec payer) reads
//  the request and writes an NDEF message containing a Cashu token back
//  via UPDATE BINARY. Card emulation requires the HCE entitlement on
//  iOS 17.4 or later and is currently limited to the European Economic Area.
//
//  The wire protocol mirrors Numo's implementation exactly, see
//  https://github.com/cashubtc/Numo/blob/main/docs/NDEF_Payer_Side_Spec.md
//

import CoreNFC
import Foundation
import OSLog

fileprivate let nfcHCELogger = Logger(subsystem: "macadamia", category: "NFCRequestEmulation")

// MARK: - Type 4 Tag APDU Engine

/// A pure ISO 7816-4 state machine emulating a Type 4 NDEF tag with one
/// readable NDEF file (the payment request) and a write buffer for the
/// payer's response. Mirrors Numo's `NdefProcessor`/`NdefApduHandler`.
final class Type4TagEmulator {

    enum Effect {
        /// The reader has read the entire NDEF file containing the request.
        case requestRead
        /// The reader wrote a complete NDEF message; contains the decoded Text/URI string.
        case messageReceived(String)
    }

    private enum SelectedFile {
        case none, cc, ndef
    }

    private static let ok = Data([0x90, 0x00])
    private static let error = Data([0x6A, 0x82])

    /// Standard NFC Forum Type 4 NDEF tag application AID (D2760000850101),
    /// selected by macadamia's Contactless payer and Numo-spec payers alike.
    /// iOS only routes this SELECT to the card session because the AID is
    /// registered in com.apple.developer.nfc.hce.iso7816.select-identifier-prefixes.
    private static let ndefTagAID: [UInt8] = [0xD2, 0x76, 0x00, 0x00, 0x85, 0x01, 0x01]

    /// Capability container advertising the NDEF file E104, byte-identical to Numo's.
    private static let ccFile = Data([0x00, 0x0F, 0x20, 0x00, 0x3B, 0x00, 0x34,
                                      0x04, 0x06, 0xE1, 0x04, 0x70, 0xFF, 0x00, 0x00])

    private static let receiveBufferSize = 65536

    private let ndefFile: [UInt8]
    private var selectedFile: SelectedFile = .none
    private var receiveBuffer = [UInt8](repeating: 0, count: receiveBufferSize)
    private var expectedNdefLength: Int?

    init(payload: String) {
        self.ndefFile = Self.type4NDEFFile(text: payload)
    }

    /// Processes one command APDU and returns the response APDU plus an
    /// optional side effect for the caller to act on.
    func handle(_ apdu: Data) -> (response: Data, effect: Effect?) {
        let bytes = [UInt8](apdu)
        guard bytes.count >= 4 else { return (Self.error, nil) }

        switch (bytes[0], bytes[1]) {
        case (0x00, 0xA4) where bytes[2] == 0x04 && bytes[3] == 0x00:
            return (handleSelectAID(bytes), nil)
        case (0x00, 0xA4) where bytes[2] == 0x00 && bytes[3] == 0x0C:
            return (handleSelectFile(bytes), nil)
        case (0x00, 0xB0):
            return handleReadBinary(bytes)
        case (0x00, 0xD6):
            return handleUpdateBinary(bytes)
        default:
            nfcHCELogger.warning("unsupported APDU: \(bytes.prefix(4).map { String(format: "%02X", $0) }.joined())")
            return (Self.error, nil)
        }
    }

    private func handleSelectAID(_ bytes: [UInt8]) -> Data {
        guard bytes.count >= 5 else { return Self.error }
        let lc = Int(bytes[4])
        guard bytes.count >= 5 + lc else { return Self.error }
        let aid = Array(bytes[5 ..< 5 + lc])

        if aid.starts(with: Self.ndefTagAID) {
            return Self.ok
        }
        nfcHCELogger.warning("SELECT for unknown AID: \(aid.map { String(format: "%02X", $0) }.joined())")
        return Self.error
    }

    private func handleSelectFile(_ bytes: [UInt8]) -> Data {
        guard bytes.count >= 7, bytes[4] == 0x02 else { return Self.error }
        switch (bytes[5], bytes[6]) {
        case (0xE1, 0x03):
            selectedFile = .cc
            return Self.ok
        case (0xE1, 0x04):
            selectedFile = .ndef
            return Self.ok
        default:
            return Self.error
        }
    }

    private func handleReadBinary(_ bytes: [UInt8]) -> (Data, Effect?) {
        guard bytes.count >= 5 else { return (Self.error, nil) }

        let file: [UInt8]
        switch selectedFile {
        case .cc: file = [UInt8](Self.ccFile)
        case .ndef: file = ndefFile
        case .none: return (Self.error, nil)
        }

        let offset = (Int(bytes[2]) << 8) | Int(bytes[3])
        let length = bytes[4] == 0 ? 256 : Int(bytes[4])

        guard offset + length <= file.count else { return (Self.error, nil) }

        // Report when the reader has consumed the request to the end of the file.
        let effect: Effect? = (selectedFile == .ndef && offset + length == file.count) ? .requestRead : nil
        return (Data(file[offset ..< offset + length]) + Self.ok, effect)
    }

    private func handleUpdateBinary(_ bytes: [UInt8]) -> (Data, Effect?) {
        // Writing requires the NDEF file to be selected; the CC file is read-only.
        guard selectedFile == .ndef, bytes.count >= 5 else { return (Self.error, nil) }

        let offset = (Int(bytes[2]) << 8) | Int(bytes[3])
        let lc = Int(bytes[4])
        guard bytes.count >= 5 + lc, offset + lc <= Self.receiveBufferSize else { return (Self.error, nil) }

        receiveBuffer.replaceSubrange(offset ..< offset + lc, with: bytes[5 ..< 5 + lc])

        // Complete-message detection, mirroring Numo's NdefUpdateBinaryHandler:
        // the payer either writes NLEN first and then the body (pattern A), or
        // zeroes NLEN, writes the body, and finishes with the real NLEN (pattern B).
        if offset == 0 && lc >= 2 {
            let nlen = (Int(receiveBuffer[0]) << 8) | Int(receiveBuffer[1])
            if nlen == 0 {
                expectedNdefLength = 0
            } else if lc >= nlen + 2 || bodyHasData(length: nlen) {
                return (Self.ok, finalizeReceivedMessage())
            } else {
                expectedNdefLength = nlen
            }
        } else if let expected = expectedNdefLength, expected > 0, offset + lc >= expected + 2 {
            return (Self.ok, finalizeReceivedMessage())
        }

        return (Self.ok, nil)
    }

    private func bodyHasData(length: Int) -> Bool {
        let end = min(length + 2, receiveBuffer.count)
        return receiveBuffer[2 ..< end].contains { $0 != 0 }
    }

    private func finalizeReceivedMessage() -> Effect? {
        defer {
            receiveBuffer = [UInt8](repeating: 0, count: Self.receiveBufferSize)
            expectedNdefLength = nil
        }
        guard let text = Self.parseNDEFFile(receiveBuffer) else { return nil }
        return .messageReceived(text)
    }

    // MARK: NDEF encoding & decoding

    /// Builds a Type 4 NDEF file (NLEN prefix) containing a single
    /// well-known Text record with language code "en", like Numo's
    /// `NdefMessageBuilder.createNdefMessage`.
    static func type4NDEFFile(text: String) -> [UInt8] {
        let textBytes = [UInt8](text.utf8)
        let language = [UInt8]("en".utf8)
        let payload = [UInt8(language.count)] + language + textBytes

        var record: [UInt8]
        if payload.count <= 255 {
            record = [0xD1, 0x01, UInt8(payload.count), 0x54]
        } else {
            let len = UInt32(payload.count)
            record = [0xC1, 0x01,
                      UInt8((len >> 24) & 0xFF), UInt8((len >> 16) & 0xFF),
                      UInt8((len >> 8) & 0xFF), UInt8(len & 0xFF),
                      0x54]
        }
        record += payload

        return [UInt8((record.count >> 8) & 0xFF), UInt8(record.count & 0xFF)] + record
    }

    /// Parses a Type 4 NDEF file and decodes the first record if it is a
    /// well-known Text ("T") or URI ("U") record.
    static func parseNDEFFile(_ data: [UInt8]) -> String? {
        guard data.count > 2 else { return nil }
        let totalLength = (Int(data[0]) << 8) | Int(data[1])
        guard totalLength > 0, totalLength + 2 <= data.count else { return nil }

        let offset = 2
        let header = data[offset]
        let typeLength = Int(data[offset + 1])
        guard typeLength == 1 else { return nil }

        let payloadLength: Int
        let typeFieldStart: Int
        if header & 0x10 != 0 { // short record
            payloadLength = Int(data[offset + 2])
            typeFieldStart = offset + 3
        } else {
            guard offset + 6 < data.count else { return nil }
            payloadLength = (Int(data[offset + 2]) << 24) | (Int(data[offset + 3]) << 16)
                          | (Int(data[offset + 4]) << 8) | Int(data[offset + 5])
            typeFieldStart = offset + 6
        }

        let payloadStart = typeFieldStart + typeLength
        guard payloadLength > 0, payloadStart + payloadLength <= data.count else { return nil }

        switch data[typeFieldStart] {
        case 0x54: // Text record: status byte, language code, then UTF-8 text
            let languageCodeLength = Int(data[payloadStart] & 0x3F)
            let textStart = payloadStart + 1 + languageCodeLength
            let textEnd = payloadStart + payloadLength
            guard textStart <= textEnd, textEnd <= data.count else { return nil }
            return String(bytes: data[textStart ..< textEnd], encoding: .utf8)
        case 0x55: // URI record: identifier code byte, then URI
            let prefixes: [UInt8: String] = [0x00: "", 0x01: "http://www.", 0x02: "https://www.",
                                             0x03: "http://", 0x04: "https://"]
            let uriStart = payloadStart + 1
            let uriEnd = payloadStart + payloadLength
            guard uriStart <= uriEnd, uriEnd <= data.count,
                  let uri = String(bytes: data[uriStart ..< uriEnd], encoding: .utf8) else { return nil }
            return (prefixes[data[payloadStart]] ?? "") + uri
        default:
            return nil
        }
    }

    /// Extracts a serialized Cashu token from freeform text or a URL,
    /// following the same rules as Numo's `CashuPaymentHelper.extractCashuToken`.
    static func extractCashuToken(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("cashuA") || trimmed.hasPrefix("cashuB") {
            return trimmed
        }

        if let range = trimmed.range(of: "#token=cashu") {
            return String(trimmed[trimmed.index(range.lowerBound, offsetBy: 7)...])
        }

        if let range = trimmed.range(of: "token=cashu") {
            let start = trimmed.index(range.lowerBound, offsetBy: 6)
            let end = trimmed[start...].firstIndex(where: { $0 == "&" || $0 == "#" }) ?? trimmed.endIndex
            return String(trimmed[start ..< end])
        }

        for prefix in ["cashuA", "cashuB"] {
            if let range = trimmed.range(of: prefix) {
                let terminators: Set<Character> = ["\"", "'", "<", ">", "&", "#"]
                let end = trimmed[range.lowerBound...].firstIndex(where: {
                    $0.isWhitespace || terminators.contains($0)
                }) ?? trimmed.endIndex
                return String(trimmed[range.lowerBound ..< end])
            }
        }

        return nil
    }
}

// MARK: - Card Session Manager

/// Owns the CardSession lifecycle for one NFC payment request presentation
/// and publishes status updates for the UI.
///
/// While emulation runs, iOS shows its own presentment sheet on top of the
/// app, so the UI only needs to know whether a session is active, whether a
/// token arrived, or whether the session failed in a way worth telling the
/// user about. Cancellation and timeouts simply return to `.idle`.
@MainActor
final class NFCRequestCardSession: ObservableObject {

    enum Status: Equatable {
        case idle
        /// Emulation is running and the system presentment sheet is shown.
        case presenting
        /// The payer wrote a Cashu token back and the session is over.
        case tokenReceived(String)
        /// The session ended with an error the user should know about.
        case failed(String)
    }

    @Published private(set) var status: Status = .idle

    var isPresenting: Bool { status == .presenting }

    /// Whether this device can emulate a tag right now: the HCE entitlement on
    /// iOS 17.4 or later (`isSupported`) plus the regional eligibility check
    /// (`isEligible`, currently limited to the European Economic Area).
    static var isAvailable: Bool {
        get async {
            guard CardSession.isSupported else { return false }
            return await CardSession.isEligible
        }
    }

    private var cardSession: CardSession?
    private var presentmentIntent: NFCPresentmentIntentAssertion?
    private var emulationTask: Task<Void, Never>?

    func start(payload: String) {
        stop()
        status = .idle
        emulationTask = Task { await run(payload: payload) }
    }

    func stop() {
        emulationTask?.cancel()
        emulationTask = nil
        cardSession?.invalidate()
        cardSession = nil
        presentmentIntent = nil
    }

    private static var unavailableMessage: String {
        String(localized: "Receiving via NFC is not available on this device or in your region.")
    }

    private static var notReadyMessage: String {
        String(localized: "NFC is not available right now. Make sure it is turned on and try again.")
    }

    private static var connectionLostMessage: String {
        String(localized: "The connection to the payer's device was lost. Try again.")
    }

    private func run(payload: String) async {
        guard await Self.isAvailable else {
            nfcHCELogger.warning("card session unavailable: supported \(CardSession.isSupported)")
            status = .failed(Self.unavailableMessage)
            return
        }

        let emulator = Type4TagEmulator(payload: payload)

        do {
            // Prevents the default contactless app from launching while presenting.
            presentmentIntent = try await NFCPresentmentIntentAssertion.acquire()
            let session = try await CardSession()
            cardSession = session
            status = .presenting
            nfcHCELogger.info("card session created, payload \(payload.count) chars")

            for try await event in session.eventStream {
                if Task.isCancelled { break }
                switch event {
                case .sessionStarted:
                    session.alertMessage = String(localized: "Hold near the payer's device.")
                    // Start emulating right away rather than waiting for a reader:
                    // the system presentment sheet only appears once emulation is
                    // in progress, and the device only answers reader polling then.
                    try await session.startEmulation()
                    nfcHCELogger.info("emulation running")
                case .readerDetected:
                    nfcHCELogger.info("reader detected")
                    if await !session.isEmulationInProgress {
                        try await session.startEmulation()
                    }
                case .readerDeselected:
                    // RF link lost before the payer wrote a token back: keep
                    // emulating so the payer can simply tap again.
                    nfcHCELogger.info("reader deselected")
                case .received(let apdu):
                    let (response, effect) = emulator.handle(apdu.payload)
                    nfcHCELogger.debug("rx \(self.hex(apdu.payload)) tx \(self.hex(response, limit: 8))")
                    try await apdu.respond(response: response)
                    switch effect {
                    case .requestRead:
                        nfcHCELogger.info("reader has read the full request")
                    case .messageReceived(let message):
                        if let token = Type4TagEmulator.extractCashuToken(from: message) {
                            nfcHCELogger.info("cashu token received")
                            status = .tokenReceived(token)
                            await session.stopEmulation(status: .success)
                            session.invalidate()
                        } else {
                            nfcHCELogger.warning("NDEF message without a cashu token ignored")
                        }
                    case nil:
                        break
                    }
                case .sessionInvalidated(let reason):
                    nfcHCELogger.info("session invalidated: \(String(describing: reason))")
                    finish(with: reason)
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            nfcHCELogger.error("card session error: \(String(describing: error))")
            if case .tokenReceived = status {
                // The token is already in hand; a late error is irrelevant.
            } else if let reason = error as? CardSession.Error {
                finish(with: reason)
            } else {
                status = .failed(Self.notReadyMessage)
            }
        }

        // A superseded session (see `start`) must not touch the replacement's state.
        guard !Task.isCancelled else { return }
        presentmentIntent = nil
        cardSession = nil
        if status == .presenting { status = .idle }
    }

    /// Maps the reason a session ended to a status. User cancellation, the
    /// 60 second session limit and our own invalidation are normal outcomes.
    private func finish(with reason: CardSession.Error) {
        if case .tokenReceived = status { return }
        switch reason {
        case .userInvalidated, .maxSessionDurationReached, .emulationStopped, .invalidated:
            status = .idle
        case .transmissionError:
            status = .failed(Self.connectionLostMessage)
        case .radioDisabled, .systemNotAvailable, .accessNotAccepted, .systemEligibilityFailed:
            status = .failed(Self.notReadyMessage)
        @unknown default:
            status = .failed(Self.notReadyMessage)
        }
    }

    private func hex(_ data: Data, limit: Int = 32) -> String {
        let shown = data.prefix(limit).map { String(format: "%02X", $0) }.joined()
        return data.count > limit ? "\(shown)… (\(data.count) B)" : shown
    }
}
