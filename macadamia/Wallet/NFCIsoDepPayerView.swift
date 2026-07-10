//
//  NFCIsoDepPayerView.swift
//  macadamia
//
//  EXPERIMENTAL: payer counterpart to NFCRequestView.
//
//  Uses NFCTagReaderSession (ISO-DEP) instead of NFCNDEFReaderSession so
//  discovery selects this app's registered "cashu" AID (0000006361736875),
//  which iOS routes to another iPhone's HCE card session — the standard
//  NDEF tag AID D2760000850101 is filtered by the emulating device's
//  entitlement and never gets through. Speaks the same Type 4 tag protocol
//  as Numo and NFCRequestEmulation: select NDEF file, read the payment
//  request, write the token back via UPDATE BINARY.
//

import CashuSwift
import CoreNFC
import SwiftData
import SwiftUI

struct NFCIsoDepPayerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]

    private var activeWallet: Wallet? { wallets.first }

    private var mints: [Mint] {
        activeWallet?.mints.filter { !$0.hidden }
                          .sorted { ($0.userIndex ?? 0) < ($1.userIndex ?? 0) } ?? []
    }

    @State private var readerDelegate: IsoDepReaderDelegate?
    @State private var readerSession: NFCTagReaderSession?

    @State private var isProcessing = false
    @State private var paymentComplete = false
    @State private var errorMessage: String?
    @State private var lastPaymentAmount: Int?
    @State private var eventLog: [String] = []

    private var isNFCAvailable: Bool {
        NFCTagReaderSession.readingAvailable
    }

    var body: some View {
        List {
            Section {
                VStack {
                    HStack {
                        Image(systemName: paymentComplete ? "checkmark.circle.fill" : "iphone.gen2.crop.circle")
                            .foregroundStyle(.primary.opacity(0.5))
                            .fontWeight(.light)
                        if isProcessing {
                            RadioWaveSymbol()
                        }
                    }
                    .font(.system(size: 60))
                    .padding(20)

                    if !isNFCAvailable {
                        Text("NFC not available on this device")
                            .foregroundStyle(.secondary)
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }

                    if paymentComplete, let amount = lastPaymentAmount {
                        VStack(spacing: 8) {
                            Label("Payment sent!", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.headline)
                            AmountView(amount: amount, unit: .sat)
                                .font(.title2.bold().monospacedDigit())
                        }
                        .padding()
                    }

                    Button(action: { startPayment() }) {
                        if isProcessing {
                            ProgressView()
                                .controlSize(.regular)
                        } else {
                            Label(paymentComplete ? "Pay Again" : "Pay with NFC",
                                  systemImage: paymentComplete ? "arrow.counterclockwise" : "wave.3.right.circle.fill")
                        }
                    }
                    .disabled(isProcessing || !isNFCAvailable)
                    .padding()
                }
                .frame(maxWidth: .infinity)
            }

            Section {
                ForEach(Array(eventLog.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .listRowSeparator(.hidden)
                }
            } header: {
                HStack {
                    Text("Event Log")
                    Spacer()
                    Button {
                        UIPasteboard.general.string = eventLog.joined(separator: "\n")
                    } label: {
                        Image(systemName: "clipboard")
                    }
                }
            }
        }
        .navigationTitle("NFC Pay")
    }

    private func log(_ message: String) {
        logger.info("NFCIsoDepPayer: \(message, privacy: .public)")
        eventLog.append(message)
    }

    // MARK: - Reader Session

    private func startPayment() {
        guard isNFCAvailable else { return }

        errorMessage = nil
        paymentComplete = false
        lastPaymentAmount = nil
        isProcessing = true
        eventLog = []

        readerDelegate = IsoDepReaderDelegate(
            onTagDetected: { tag, session in
                await self.handleTag(tag, session: session)
            },
            onError: { error in
                self.log("session error: \(error)")
                self.errorMessage = error
                self.isProcessing = false
            },
            onSessionEnd: {
                self.isProcessing = false
                self.readerSession = nil
            }
        )

        readerSession = NFCTagReaderSession(pollingOption: .iso14443, delegate: readerDelegate!, queue: nil)
        readerSession?.alertMessage = "Hold near the requesting device"
        log("polling started")
        readerSession?.begin()
    }

    @MainActor
    private func handleTag(_ tag: NFCTag, session: NFCTagReaderSession) async {
        do {
            guard case .iso7816(let iso7816Tag) = tag else {
                throw NFCPaymentError.nfcReadFailed("Detected tag is not ISO 7816")
            }

            try await session.connect(to: tag)
            log("connected, initial AID: \(iso7816Tag.initialSelectedAID)")

            // Select the NDEF file and read the payment request.
            session.alertMessage = "Reading payment request..."
            try await selectNDEFFile(iso7816Tag)
            let requestString = try await readNDEFText(iso7816Tag)
            log("request read: \(requestString.prefix(30))…")

            let request = try parsePaymentRequest(requestString)

            // Create the token. This can involve network round trips to the
            // mint, so keep the user informed while the RF link stays up.
            session.alertMessage = "Preparing payment..."
            let tokenString = try await prepareToken(for: request)
            log("token prepared (\(tokenString.count) chars)")

            session.alertMessage = "Sending payment..."
            try await writeNDEFText(tokenString, to: iso7816Tag)
            log("token written back")

            lastPaymentAmount = request.amount
            paymentComplete = true
            session.alertMessage = "Payment sent!"
            session.invalidate()
        } catch let error as NFCPaymentError {
            log("failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            session.invalidate(errorMessage: error.localizedDescription)
        } catch {
            log("failed: \(String(describing: error))")
            errorMessage = error.localizedDescription
            session.invalidate(errorMessage: error.localizedDescription)
        }
    }

    // MARK: - Type 4 Tag Protocol

    private func send(_ tag: NFCISO7816Tag,
                      ins: UInt8, p1: UInt8, p2: UInt8,
                      data: Data = Data(),
                      expectedLength: Int = -1) async throws -> Data {
        let apdu = NFCISO7816APDU(instructionClass: 0x00,
                                  instructionCode: ins,
                                  p1Parameter: p1,
                                  p2Parameter: p2,
                                  data: data,
                                  expectedResponseLength: expectedLength)
        let (response, sw1, sw2) = try await tag.sendCommand(apdu: apdu)
        guard sw1 == 0x90, sw2 == 0x00 else {
            throw NFCPaymentError.nfcReadFailed(String(format: "APDU INS %02X failed: %02X%02X", ins, sw1, sw2))
        }
        return response
    }

    private func selectNDEFFile(_ tag: NFCISO7816Tag) async throws {
        _ = try await send(tag, ins: 0xA4, p1: 0x00, p2: 0x0C, data: Data([0xE1, 0x04]))
    }

    private func readNDEFText(_ tag: NFCISO7816Tag) async throws -> String {
        let header = try await send(tag, ins: 0xB0, p1: 0x00, p2: 0x00, expectedLength: 2)
        guard header.count == 2 else {
            throw NFCPaymentError.nfcReadFailed("Short NLEN response")
        }
        let nlen = (Int(header[0]) << 8) | Int(header[1])
        guard nlen > 0 else {
            throw NFCPaymentError.nfcReadFailed("Empty NDEF file")
        }

        var body = Data()
        while body.count < nlen {
            let offset = 2 + body.count
            let chunk = min(180, nlen - body.count)
            body += try await send(tag,
                                   ins: 0xB0,
                                   p1: UInt8((offset >> 8) & 0xFF),
                                   p2: UInt8(offset & 0xFF),
                                   expectedLength: chunk)
        }

        guard let text = Type4TagEmulator.parseNDEFFile([UInt8](header + body)) else {
            throw NFCPaymentError.nfcReadFailed("Could not parse NDEF message")
        }
        return text
    }

    private func writeNDEFText(_ text: String, to tag: NFCISO7816Tag) async throws {
        let file = Type4TagEmulator.type4NDEFFile(text: text)

        // Pattern B per the Numo spec: zero NLEN, write the body in chunks,
        // then write the real NLEN, which triggers processing on the tag side.
        _ = try await send(tag, ins: 0xD6, p1: 0x00, p2: 0x00, data: Data([0x00, 0x00]))

        var offset = 2
        while offset < file.count {
            let chunk = Array(file[offset ..< min(offset + 180, file.count)])
            _ = try await send(tag,
                               ins: 0xD6,
                               p1: UInt8((offset >> 8) & 0xFF),
                               p2: UInt8(offset & 0xFF),
                               data: Data(chunk))
            offset += chunk.count
        }

        _ = try await send(tag, ins: 0xD6, p1: 0x00, p2: 0x00, data: Data([file[0], file[1]]))
    }

    // MARK: - Token Creation

    /// Same behavior as Contactless.prepareToken: sat-only, first accepted
    /// mint with sufficient balance, no locking.
    @MainActor
    private func prepareToken(for request: CashuSwift.PaymentRequest) async throws -> String {
        guard let amount = request.amount else {
            throw NFCPaymentError.noAmountSpecified
        }

        guard let activeWallet else {
            throw macadamiaError.databaseError("No active wallet for this operation.")
        }

        let unit = Unit(code: request.unit ?? Unit.sat.currencyCode)
        guard unit == .sat else {
            throw NFCPaymentError.unsupportedUnit(unit.currencyCode)
        }

        let requestedMints = request.mints ?? []
        let matchingMints = mints.acceptedByPaymentRequest(mintURLs: requestedMints)

        guard !matchingMints.isEmpty else {
            throw NFCPaymentError.noMatchingMint(requestedMints: requestedMints)
        }

        guard let selectedMint = matchingMints.first(where: { $0.balance(for: .sat) >= amount }) else {
            let totalAvailable = matchingMints.map { $0.balance(for: .sat) }.max() ?? 0
            throw NFCPaymentError.insufficientBalance(required: amount, available: totalAvailable)
        }

        let token = try await AppSchemaV1.createToken(mint: selectedMint,
                                                      activeWallet: activeWallet,
                                                      amount: amount,
                                                      unit: .sat,
                                                      memo: "",
                                                      modelContext: modelContext,
                                                      lockingKey: nil)

        try modelContext.save()

        return try token.serialize(to: .V4)
    }
}

// MARK: - Reader Delegate

private final class IsoDepReaderDelegate: NSObject, NFCTagReaderSessionDelegate, @unchecked Sendable {
    private let onTagDetected: (NFCTag, NFCTagReaderSession) async -> Void
    private let onError: @MainActor (String) -> Void
    private let onSessionEnd: @MainActor () -> Void

    init(onTagDetected: @escaping (NFCTag, NFCTagReaderSession) async -> Void,
         onError: @escaping @MainActor (String) -> Void,
         onSessionEnd: @escaping @MainActor () -> Void) {
        self.onTagDetected = onTagDetected
        self.onError = onError
        self.onSessionEnd = onSessionEnd
    }

    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        Task { @MainActor in
            if let readerError = error as? NFCReaderError,
               readerError.code != .readerSessionInvalidationErrorUserCanceled,
               readerError.code != .readerSessionInvalidationErrorFirstNDEFTagRead {
                onError(readerError.localizedDescription)
            }
            onSessionEnd()
        }
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let tag = tags.first else { return }
        Task {
            await onTagDetected(tag, session)
        }
    }
}
