//
//  DepositView.swift
//  macadamia
//
//  Created by zm on 15.09.26.
//

import SwiftUI
import SwiftData
import CashuSwift

/// In-memory quote and the context needed to display and later redeem it.
struct DepositQuote: Identifiable, Hashable {
    let id = UUID()
    let response: any CashuSwift.MintQuoteResponse
    let mint: Mint
    let option: PaymentOption
    let requestedAmount: Int?
    let lockingKeyCounter: UInt32?

    var quoteID: String { response.quote }
    var request: String { response.request }
    var method: CashuSwift.PaymentMethodID { response.method }
    var paymentMethodKind: PaymentMethodKind { method.kind }
    var paymentMethodName: String { option.methodDisplayName }
    var unit: Unit { Unit(code: response.unit) }
    var amount: Int? { response.amount ?? requestedAmount }
    var expiry: Date? { response.expiry.map { Date(timeIntervalSince1970: TimeInterval($0)) } }

    /// The generic transport preserves method-specific fields such as accounting.
    var raw: CashuSwift.JSONObject? { (response as? CashuSwift.Generic.MintQuote)?.raw }
    var amountPaid: Int? { integerField("amount_paid") }
    var amountIssued: Int? { integerField("amount_issued") }

    private func integerField(_ name: String) -> Int? {
        guard case .integer(let value) = raw?[name] else { return nil }
        return Int(exactly: value)
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct DepositQuoteView: View {
    
    let quote: DepositQuote

    private var paymentMethodKind: PaymentMethodKind { quote.paymentMethodKind }

    @Environment(\.dismissToRoot) private var dismissToRoot
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var copied = false
    @State private var hourglassStatus: HourglassProgressView.Status = .waiting
    @State private var statusText = String(localized: "Waiting for payment...")
    @State private var pollingTimer: Timer?
    @State private var pollingTask: Task<Void, Never>?
    @State private var isIssuing = false

    private var statusColor: Color {
        switch hourglassStatus {
        case .waiting: .primary
        case .success: .successGreen
        case .failure: .failureRed
        }
    }
    
    var body: some View {
        List {
            Section {
                    if let amount = quote.amount {
                        HStack {
                            Text("Amount:")
                            Spacer()
                            Text(amountDisplayString(amount, unit: quote.unit))
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fontWeight(.semibold)
                        .listRowSeparator(.hidden)
                    }
                Group {
                    switch paymentMethodKind {
                    case .bolt11, .bolt12, .onchain:
                        QRView(string: quote.request)
                    case .generic:
                        QRView(string: quote.quoteID)
                    }
                }
                .listRowInsets(EdgeInsets(top: quote.amount == nil ? 16 : 0,
                                          leading: 16,
                                          bottom: 16,
                                          trailing: 16))
                if quote.paymentMethodKind != .generic {
                    Button {
                        if copied { return }
                            UIPasteboard.general.string = quote.request
                        withAnimation {
                            copied = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation {
                                copied = false
                            }
                        }
                    } label: {
                        HStack {
                            Text(quote.request)
                                .lineLimit(1)
                            Image(systemName: copied ? "clipboard.fill" : "clipboard")
                        }
                    }
                    .listRowSeparator(.hidden)
                }
                HStack {
                    Text("Quote ID")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Spacer()
                    Text(quote.quoteID)
                        .lineLimit(1)
                        .font(.caption)
                        .monospaced()
                        .foregroundStyle(.secondary)
                }
                .contextMenu {
                    Button(action: {
                        UIPasteboard.general.string = quote.quoteID
                    }) {
                        Text("Copy Quote ID")
                        Image(systemName: "doc.on.clipboard")
                    }
                }
                .onTapGesture(count: 2) {
                    UIPasteboard.general.string = quote.quoteID
                }
            } header: {
                switch quote.paymentMethodKind {
                case .bolt11: Text("Invoice")
                case .bolt12: Text("Offer")
                case .onchain: Text("Address")
                case .generic: Text("Quote")
                }
            }

            Section {
                HStack {
                    Spacer()
                    HourglassProgressView(status: hourglassStatus)
                        .accessibilityHidden(true)
                    Text(statusText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .foregroundStyle(statusColor)
                .animation(.easeInOut(duration: 0.25), value: hourglassStatus)
                .listRowBackground(EmptyView())
                .font(.title3)
                .fontDesign(.rounded)
                .listRowInsets(.none)
                .lineLimit(hourglassStatus == .failure ? nil : 2)
            }
            .listSectionSpacing(12)
        }
        .navigationTitle("\(quote.paymentMethodName) Deposit")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)    // we replace the system back button
        .toolbar {                              // with one that dismisses to root
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    withAnimation {
                        dismissToRoot()
                    }
                } label: {
                    Label("Done", systemImage: "chevron.backward")
                }
            }
        }
        .onAppear(perform: startPolling)
        .onDisappear {
            stopPolling()
            // Once issuance starts, let it finish saving any returned proofs.
            if !isIssuing { pollingTask?.cancel() }
        }
        .sensoryFeedback(trigger: hourglassStatus) { _, status in
            switch status {
            case .waiting: nil
            case .success: .success
            case .failure: .error
            }
        }
        .task(id: hourglassStatus) {
            guard hourglassStatus == .success else { return }
            do {
                try await Task.sleep(for: .seconds(2))
                try Task.checkCancellation()
                withAnimation(reduceMotion ? nil : .default) {
                    dismissToRoot()
                }
            } catch {
                // Leaving the view cancels its pending dismissal.
            }
        }
    }

    @MainActor
    private func startPolling() {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }
        #endif
        guard hourglassStatus == .waiting, pollingTimer == nil, !isIssuing else { return }
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            Task { @MainActor in
                checkPaymentState()
            }
        }
    }

    private func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    @MainActor
    private func checkPaymentState() {
        guard pollingTimer != nil, pollingTask == nil, hourglassStatus == .waiting else { return }

        pollingTask = Task { @MainActor in
            defer {
                pollingTask = nil
                isIssuing = false
            }
            do {
                let mint = CashuSwift.Mint(quote.mint)
                let response: any CashuSwift.MintQuoteResponse
                if quote.method == .bolt11 {
                    response = try await CashuSwift.Bolt11.mintQuoteState(quote.quoteID, from: mint)
                } else {
                    response = try await CashuSwift.Generic.mintQuoteState(quote.quoteID,
                                                                          method: quote.method,
                                                                          from: mint)
                }
                try Task.checkCancellation()
                guard response.quote == quote.quoteID, response.unit == quote.response.unit,
                      response.method == quote.method else {
                    throw CashuError.inputError("The mint returned payment status for a different quote.")
                }
                guard let amount = try Self.amountToIssue(for: response, requestedAmount: quote.amount) else {
                    return
                }

                stopPolling()
                isIssuing = true
                statusText = String(localized: "Payment received. Issuing ecash...")
                try await Self.issueEcash(for: quote, amount: amount, in: modelContext)
                statusText = String(localized: "Ecash received!")
                hourglassStatus = .success
            } catch {
                guard !Task.isCancelled else { return }
                stopPolling()
                let detail = Self.errorDescription(error)
                statusText = isIssuing
                    ? String(localized: "Could not issue ecash. \(detail)")
                    : String(localized: "Could not check payment. \(detail)")
                hourglassStatus = .failure
                logger.error("Deposit failed: \(error)")
            }
        }
    }

    /// Accounting-based methods can receive multiple payments, including amountless deposits.
    static func amountToIssue(for response: any CashuSwift.MintQuoteResponse,
                              requestedAmount: Int?) throws -> Int? {
        let generic = response as? CashuSwift.Generic.MintQuote
        let state: String?
        if case .string(let rawState) = generic?.raw["state"] {
            state = rawState.uppercased()
        } else {
            state = response.state?.rawValue
        }

        switch state {
        case "ISSUED": throw CashuError.proofsAlreadyIssuedForQuote
        case "EXPIRED": throw CashuError.quoteIsExpired
        case "FAILED": throw CashuError.inputError("The mint reported that this deposit failed.")
        default: break
        }

        if let raw = generic?.raw, raw["amount_paid"] != nil || raw["amount_issued"] != nil {
            guard case .integer(let paid) = raw["amount_paid"],
                  case .integer(let issued) = raw["amount_issued"] ?? .integer(0),
                  issued >= 0, paid >= issued,
                  let available = Int(exactly: paid - issued) else {
                throw CashuError.invalidQuoteAccounting
            }
            if available > 0 { return available }
        } else if state == "PAID" {
            guard let amount = response.amount ?? requestedAmount, amount > 0 else {
                throw CashuError.inputError("The mint marked the quote as paid without an amount to issue.")
            }
            return amount
        }

        // Paid funds remain claimable even after the payment request has expired.
        if state != "PENDING", let expiry = response.expiry,
           Date(timeIntervalSince1970: TimeInterval(expiry)) <= Date() {
            throw CashuError.quoteIsExpired
        }
        return nil
    }

    @MainActor
    static func issueEcash(for quote: DepositQuote, amount: Int, in context: ModelContext) async throws {
        guard let wallet = quote.mint.wallet else {
            throw CashuError.inputError("The wallet associated with this deposit is no longer available.")
        }
        let mint = CashuSwift.Mint(quote.mint)
        let result: CashuSwift.IssueResult
        let event: Event

        switch quote.response {
        case let bolt11 as CashuSwift.Bolt11.MintQuote:
            result = try await CashuSwift.Bolt11.mint(quote: bolt11, from: mint, seed: wallet.seed)
            event = Event.mintEvent(unit: quote.unit, shortDescription: "Ecash created", wallet: wallet,
                                    quote: bolt11, mint: quote.mint, amount: result.proofs.sum)
        case var generic as CashuSwift.Generic.MintQuote:
            if let pubkey = generic.lockingPubkey {
                guard let counter = quote.lockingKeyCounter else {
                    throw CashuError.inputError("The signing-key counter for this locked deposit is missing.")
                }
                let key = try CashuSwift.Generic.quoteLockingKey(seed: wallet.seed, counter: counter)
                guard key.publicKey.lowercased() == pubkey.lowercased() else {
                    throw CashuError.invalidKey("The deposit's signing key does not match this wallet.")
                }
                generic = generic.addingNut20Counter(counter)
                result = try await CashuSwift.Generic.mint(quote: generic, from: mint, seed: wallet.seed,
                                                          quoteKey: key.privateKey, amount: amount,
                                                          signatureFormat: .legacyConcat) // Matches MintView's CDK compatibility.
            } else {
                guard quote.lockingKeyCounter == nil else {
                    throw CashuError.invalidKey("The locked deposit is missing its public key.")
                }
                result = try await CashuSwift.Generic.mint(quote: generic, from: mint,
                                                          amount: amount, seed: wallet.seed)
            }
            event = Event.mintEvent(unit: quote.unit, shortDescription: "Ecash created", wallet: wallet,
                                    genericQuote: generic, mint: quote.mint, amount: result.proofs.sum)
        default:
            throw CashuError.unsupportedPaymentMethod("This deposit's quote format cannot be issued.")
        }

        // Do not check cancellation between receiving proofs and persisting them.
        do {
            try quote.mint.addProofs(result.proofs, to: context)
            context.insert(event)
            try context.save()
        } catch {
            throw macadamiaError.databaseError("Ecash was issued, but could not be saved to the wallet. \(error.localizedDescription)")
        }
        logger.info("DLEQ check on deposit issuance: \(String(describing: result.dleqResult))")
    }

    private static func errorDescription(_ error: Error) -> String {
        switch error {
        case CashuError.networkError:
            String(localized: "The mint could not be reached. Check your internet connection.")
        case CashuError.quoteIsExpired:
            String(localized: "This payment request has expired. Create a new deposit to continue.")
        case CashuError.proofsAlreadyIssuedForQuote:
            String(localized: "The mint reports that ecash has already been issued for this quote.")
        case CashuError.invalidQuoteAccounting:
            String(localized: "The mint returned inconsistent paid and issued amounts. The deposit could not be redeemed.")
        case macadamiaError.databaseError(let message):
            message
        default:
            error.localizedDescription
        }
    }
}

struct HourglassProgressView: View {
    enum Status: Equatable {
        case waiting, success, failure
    }

    let status: Status

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation = 0.0

    private var shouldRotate: Bool {
        switch (status, scenePhase, reduceMotion) {
        case (.waiting, .active, false): true
        default: false
        }
    }

    private var symbol: String {
        switch status {
        case .waiting: "hourglass.bottomhalf.filled"
        case .success: "checkmark"
        case .failure: "xmark"
        }
    }

    var body: some View {
        Image(systemName: symbol)
            .contentTransition(reduceMotion ? .identity : .symbolEffect)
            .frame(width: 32, height: 32)
            .animation(shouldRotate ? .easeInOut(duration: 0.5) : nil) { content in
                content.rotationEffect(.degrees(shouldRotate ? rotation : 0))
            }
            .task(id: shouldRotate) {
                var reset = Transaction(animation: nil)
                reset.disablesAnimations = true
                withTransaction(reset) {
                    rotation = 0
                }
                guard shouldRotate else { return }
                do {
                    while !Task.isCancelled {
                        try await Task.sleep(for: .seconds(2))
                        try Task.checkCancellation()
                        rotation += 360
                    }
                } catch {

                }
            }
    }
}

#if DEBUG
#Preview("BOLT11") {
    NavigationStack {
        DepositQuoteView(quote: DepositQuotePreview.bolt11)
    }
    .previewEnvironment()
}

#Preview("BOLT12 · Amountless") {
    NavigationStack {
        DepositQuoteView(quote: DepositQuotePreview.bolt12)
    }
    .previewEnvironment()
}

#Preview("On-chain") {
    NavigationStack {
        DepositQuoteView(quote: DepositQuotePreview.onchain)
    }
    .previewEnvironment()
}

#Preview("Generic") {
    NavigationStack {
        DepositQuoteView(quote: DepositQuotePreview.generic)
    }
    .previewEnvironment()
}
#endif
