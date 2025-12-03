//
//  Contactless.swift
//  macadamia
//
//  Created by zm on 02.12.25.
//

import SwiftUI
import SwiftData
import CoreNFC
import CashuSwift

// MARK: - Error Types

enum NFCPaymentError: LocalizedError {
    case nfcUnavailable
    case invalidPaymentRequest(String)
    case noAmountSpecified
    case unsupportedUnit(String)
    case noMatchingMint
    case insufficientBalance(required: Int, available: Int)
    case proofSelectionFailed
    case tokenCreationFailed(String)
    case nfcReadFailed(String)
    case nfcWriteFailed(String)
    case tagConnectionFailed
    
    var errorDescription: String? {
        switch self {
        case .nfcUnavailable:
            return "NFC is not available on this device"
        case .invalidPaymentRequest(let detail):
            return "Invalid payment request: \(detail)"
        case .noAmountSpecified:
            return "Payment request does not specify an amount"
        case .unsupportedUnit(let unit):
            return "Unsupported unit: \(unit)"
        case .noMatchingMint:
            return "No matching mint found for this request"
        case .insufficientBalance(let required, let available):
            return "Insufficient balance: need \(required), have \(available)"
        case .proofSelectionFailed:
            return "Failed to select proofs for payment"
        case .tokenCreationFailed(let detail):
            return "Failed to create token: \(detail)"
        case .nfcReadFailed(let detail):
            return "Failed to read NFC tag: \(detail)"
        case .nfcWriteFailed(let detail):
            return "Failed to write to NFC tag: \(detail)"
        case .tagConnectionFailed:
            return "Failed to connect to NFC tag"
        }
    }
}

// MARK: - Contactless View

struct Contactless: View {
    @Environment(\.modelContext) private var modelContext
    
    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]
    
    private var activeWallet: Wallet? { wallets.first }
    
    private var mints: [Mint] {
        activeWallet?.mints.filter { !$0.hidden }
                          .sorted { ($0.userIndex ?? 0) < ($1.userIndex ?? 0) } ?? []
    }
    
    @State private var nfcDelegate: NFCReaderDelegate?
    @State private var nfcSession: NFCNDEFReaderSession?
    
    @State private var isProcessing = false
    @State private var paymentComplete = false
    @State private var errorMessage: String?
    @State private var lastPaymentAmount: Int?
    
    private var isNFCAvailable: Bool {
        NFCNDEFReaderSession.readingAvailable
    }
    
    var body: some View {
        VStack {
            HStack {
                Image(systemName: "iphone.gen2.crop.circle")
                    .foregroundStyle(.primary.opacity(0.5))
                    .fontWeight(.light)
                RadioWaveSymbol()
            }
            .font(.system(size: 60))
            .padding(20)
            
            if !isNFCAvailable {
                Text("NFC not available on this device")
                    .foregroundStyle(.secondary)
                    .padding()
            }
            
            if let error = errorMessage {
                errorView(error)
            }
            
            if paymentComplete, let amount = lastPaymentAmount {
                VStack(spacing: 8) {
                    Label("Payment sent!", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.headline)
                    Text("\(amount) sat")
                        .font(.title2.bold().monospacedDigit())
                }
                .padding()
            }
            
            actionButtons
            
            Spacer()
        }
    }
    
    // MARK: - Action Buttons
    
    @ViewBuilder
    private var actionButtons: some View {
        if paymentComplete {
            Button(action: { reset() }) {
                Label("Pay Again", systemImage: "arrow.counterclockwise")
            }
            .padding()
        } else {
            Button(action: { startContactlessPayment() }) {
                if isProcessing {
                    ProgressView()
                        .controlSize(.regular)
                } else {
                    Label("Pay with NFC", systemImage: "wave.3.right.circle.fill")
                }
            }
            .disabled(isProcessing || !isNFCAvailable)
            .padding()
        }
    }
    
    // MARK: - NFC Payment Flow
    
    private func startContactlessPayment() {
        guard isNFCAvailable else {
            errorMessage = NFCPaymentError.nfcUnavailable.localizedDescription
            return
        }
        
        reset()
        isProcessing = true
        
        // Create delegate with the payment handler
        nfcDelegate = NFCReaderDelegate(
            onTagDetected: { tag, session in
                await self.handleTagDetected(tag: tag, session: session)
            },
            onError: { error in
                self.errorMessage = error
                self.isProcessing = false
            },
            onSessionEnd: {
                self.isProcessing = false
                self.nfcSession = nil
            }
        )
        
        // Use invalidateAfterFirstRead: false to keep session alive for writing
        nfcSession = NFCNDEFReaderSession(delegate: nfcDelegate!, queue: nil, invalidateAfterFirstRead: false)
        nfcSession?.alertMessage = "Hold your iPhone near the payment terminal"
        nfcSession?.begin()
    }
    
    @MainActor
    private func handleTagDetected(tag: NFCNDEFTag, session: NFCNDEFReaderSession) async {
        do {
            // 1. Connect to the tag
            session.alertMessage = "Reading payment request..."
            try await session.connect(to: tag)
            
            // 2. Read the NDEF message
            let ndefMessage = try await tag.readNDEF()
            
            guard let paymentRequestString = extractText(from: ndefMessage) else {
                throw NFCPaymentError.nfcReadFailed("No readable data on tag")
            }
            
            // 3. Decode the payment request
            let request = try decodePaymentRequest(paymentRequestString)
            
            // 4. Prepare the token
            session.alertMessage = "Preparing payment..."
            let tokenString = try await prepareToken(for: request)
            
            // 5. Write the token back to the tag
            session.alertMessage = "Sending payment..."
            let responseMessage = createNDEFMessage(with: tokenString)
            try await tag.writeNDEF(responseMessage)
            
            // 6. Success!
            lastPaymentAmount = request.amount
            paymentComplete = true
            session.alertMessage = "Payment sent!"
            session.invalidate()
            
        } catch let error as NFCPaymentError {
            errorMessage = error.localizedDescription
            session.invalidate(errorMessage: error.localizedDescription)
        } catch {
            errorMessage = error.localizedDescription
            session.invalidate(errorMessage: error.localizedDescription)
        }
    }
    
    private func reset() {
        errorMessage = nil
        paymentComplete = false
        lastPaymentAmount = nil
        isProcessing = false
    }
    
    // MARK: - Payment Request Handling
    
    private func decodePaymentRequest(_ string: String) throws -> CashuSwift.PaymentRequest {
        var input = string.trimmingCharacters(in: .whitespacesAndNewlines)
        input = input.replacingOccurrences(of: "cashu://", with: "")
        input = input.replacingOccurrences(of: "cashu:", with: "")
        
        do {
            return try CashuSwift.PaymentRequest(encodedRequest: input)
        } catch {
            throw NFCPaymentError.invalidPaymentRequest(error.localizedDescription)
        }
    }
    
    /// Prepares a token to fulfill the payment request
    @MainActor
    private func prepareToken(for request: CashuSwift.PaymentRequest) async throws -> String {
        // 1. Validate the request has an amount
        guard let amount = request.amount else {
            throw NFCPaymentError.noAmountSpecified
        }
        
        guard let activeWallet else {
            throw macadamiaError.databaseError("No active wallet for this operation.")
        }
        
        // 2. Validate the unit is supported
        let unit = request.unit ?? "sat"
        guard unit == "sat" else {
            throw NFCPaymentError.unsupportedUnit(unit)
        }
        
        // 3. Find matching mint
        let requestedMints = request.mints ?? []
        let matchingMints = mints.filter { mint in
            requestedMints.isEmpty || requestedMints.contains(mint.url.absoluteString)
        }
        
        guard !matchingMints.isEmpty else {
            throw NFCPaymentError.noMatchingMint
        }
        
        // 4. Find a mint with sufficient balance
        guard let selectedMint = matchingMints.first(where: { $0.balance(for: .sat) >= amount }) else {
            let totalAvailable = matchingMints.map { $0.balance(for: .sat) }.max() ?? 0
            throw NFCPaymentError.insufficientBalance(required: amount, available: totalAvailable)
        }
        
        // 5. Select proofs from the mint
        guard let proofs = selectedMint.select(amount: amount, unit: .sat) else {
            throw NFCPaymentError.proofSelectionFailed
        }
        
        proofs.selected.setState(.pending)
        
        let sendResult = try await CashuSwift.send(request: request,
                                                   mint: CashuSwift.Mint(selectedMint),
                                                   inputs: proofs.selected.sendable(),
                                                   amount: nil,
                                                   memo: nil,
                                                   seed: activeWallet.seed)
        
        if let counterIncrease = sendResult.counterIncrease {
            selectedMint.increaseDerivationCounterForKeysetWithID(counterIncrease.keysetID,
                                                                  by: counterIncrease.increase)
        }
        
        proofs.selected.setState(.spent)
        
        try selectedMint.addProofs(sendResult.change,
                                   to: modelContext,
                                   increaseDerivationCounter: false)
        
        // TODO: create send event
        
        return try sendResult.payload.toToken().serialize(to: .V4)
    }
    
    // MARK: - NDEF Helpers
    
    private func extractText(from message: NFCNDEFMessage) -> String? {
        for record in message.records {
            if let text = extractText(from: record) {
                return text
            }
        }
        return nil
    }
    
    private func extractText(from record: NFCNDEFPayload) -> String? {
        // Handle well-known text records (type "T")
        if record.typeNameFormat == .nfcWellKnown {
            if let type = String(data: record.type, encoding: .utf8), type == "T" {
                let payload = record.payload
                guard payload.count > 0 else { return nil }
                
                let statusByte = payload[0]
                let languageCodeLength = Int(statusByte & 0x3F)
                
                guard payload.count > 1 + languageCodeLength else { return nil }
                
                let textData = payload.dropFirst(1 + languageCodeLength)
                return String(data: Data(textData), encoding: .utf8)
            }
            
            // Handle URI records (type "U")
            if let type = String(data: record.type, encoding: .utf8), type == "U" {
                if let uri = record.wellKnownTypeURIPayload()?.absoluteString {
                    return uri
                }
            }
        }
        
        // Handle external type records (common for Android apps)
        if record.typeNameFormat == .nfcExternal {
            if let text = String(data: record.payload, encoding: .utf8) {
                return text
            }
        }
        
        // Handle media type records
        if record.typeNameFormat == .media {
            if let text = String(data: record.payload, encoding: .utf8) {
                return text
            }
        }
        
        // Fallback: try to decode any payload as UTF-8
        if let text = String(data: record.payload, encoding: .utf8), !text.isEmpty {
            return text
        }
        
        return nil
    }
    
    private func createNDEFMessage(with text: String) -> NFCNDEFMessage {
        // Manually create NDEF text record with explicit UTF-8 encoding
        // Format: [status byte][language code][text]
        // Status byte: bit 7 = encoding (0=UTF-8, 1=UTF-16), bits 5-0 = language code length
        
        let languageCode = "en"
        let languageCodeData = languageCode.data(using: .utf8)!
        let textData = text.data(using: .utf8)!
        
        // Status byte: UTF-8 encoding (bit 7 = 0) + language code length
        let statusByte = UInt8(languageCodeData.count & 0x3F)
        
        var payload = Data()
        payload.append(statusByte)
        payload.append(languageCodeData)
        payload.append(textData)
        
        let record = NFCNDEFPayload(
            format: .nfcWellKnown,
            type: "T".data(using: .utf8)!,
            identifier: Data(),
            payload: payload
        )
        
        return NFCNDEFMessage(records: [record])
    }
    
    // MARK: - Subviews
    
    @ViewBuilder
    private func errorView(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
        }
        .padding()
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal)
    }
}

// MARK: - NFC Reader Delegate

private final class NFCReaderDelegate: NSObject, NFCNDEFReaderSessionDelegate, @unchecked Sendable {
    let onTagDetected: @MainActor @Sendable (NFCNDEFTag, NFCNDEFReaderSession) async -> Void
    let onError: @MainActor @Sendable (String) -> Void
    let onSessionEnd: @MainActor @Sendable () -> Void
    
    init(onTagDetected: @escaping @MainActor @Sendable (NFCNDEFTag, NFCNDEFReaderSession) async -> Void,
         onError: @escaping @MainActor @Sendable (String) -> Void,
         onSessionEnd: @escaping @MainActor @Sendable () -> Void) {
        self.onTagDetected = onTagDetected
        self.onError = onError
        self.onSessionEnd = onSessionEnd
    }
    
    func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {
        // Session became active
    }
    
    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        let nfcError = error as? NFCReaderError
        let errorDescription = error.localizedDescription
        
        Task { @MainActor in
            if nfcError?.code != .readerSessionInvalidationErrorUserCanceled &&
               nfcError?.code != .readerSessionInvalidationErrorFirstNDEFTagRead {
                self.onError(errorDescription)
            }
            self.onSessionEnd()
        }
    }
    
    // This is called when tags are detected - we use this instead of didDetectNDEFs
    // so we can write back to the tag
    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        guard let tag = tags.first else {
            session.invalidate(errorMessage: "No tag found")
            return
        }
        
        Task { @MainActor in
            await self.onTagDetected(tag, session)
        }
    }
    
    // Required but not used when didDetect tags: is implemented
    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        // Not used - we handle tags directly in didDetect tags:
    }
}

// MARK: - Preview

#Preview {
    Contactless()
}

// MARK: - Radio Wave Symbol

struct RadioWaveSymbol: View {
    @State private var isOn = false

    var body: some View {
        Image(systemName: "wave.3.right")
            .symbolRenderingMode(.palette)
            .foregroundStyle(
                .primary.opacity(0.5),   // inner
                .primary.opacity(0.6),   // middle
            )
            .symbolEffect(
                .variableColor.iterative.nonReversing,
                options: .repeating,
                value: isOn
            )
            .onAppear { isOn.toggle() }
    }
}
