import SwiftUI
import SwiftData
import CashuSwift

struct BOLT12OfferInput: Sendable {
    let request: String
    let description: String?
    let amountMsat: Int?
    let expiry: UInt64?

    init(_ input: String, now: Date = Date()) throws {
        guard case .bolt12Offer(let offer) = try CashuSwift.decodeLightningRequest(input) else {
            throw CashuError.inputError(String(localized: "Enter a BOLT12 offer."))
        }
        guard offer.currency == nil else {
            throw CashuError.inputError(String(localized: "Offers priced in other currencies are not supported yet."))
        }
        guard offer.quantityMax == nil else {
            throw CashuError.inputError(String(localized: "Offers requiring a quantity are not supported yet."))
        }
        guard offer.issuerID != nil || offer.paths?.isEmpty == false else {
            throw CashuError.inputError(String(localized: "The offer has no payment destination."))
        }
        if let amount = offer.amount {
            guard let value = Int(exactly: amount), value > 0 else { throw CashuError.invalidAmount }
            amountMsat = value
        } else {
            amountMsat = nil
        }
        request = offer.message.normalizedString
        description = offer.description
        expiry = offer.absoluteExpiry
        try validateExpiry(now: now)
    }

    func validateExpiry(now: Date = Date()) throws {
        if let expiry, TimeInterval(expiry) <= now.timeIntervalSince1970 { throw CashuError.quoteIsExpired }
    }

    func paymentAmountMsat(enteredSats: Int) throws -> Int {
        if let amountMsat { return amountMsat }
        let (msat, overflow) = enteredSats.multipliedReportingOverflow(by: 1_000)
        guard enteredSats > 0, !overflow else { throw CashuError.invalidAmount }
        return msat
    }

    func paymentAmountSat(enteredSats: Int) throws -> Int {
        let msat = try paymentAmountMsat(enteredSats: enteredSats)
        // Cashu sat proofs cover fractional-satoshi Lightning amounts by rounding up.
        return msat / 1_000 + (msat % 1_000 == 0 ? 0 : 1)
    }

    func quoteRequest(enteredSats: Int) throws -> CashuSwift.Bolt12.MeltQuoteRequest {
        try validateExpiry()
        let msat = try paymentAmountMsat(enteredSats: enteredSats)
        return .init(unit: "sat", request: request,
                     options: amountMsat == nil ? .init(amountless: .init(amountMsat: msat)) : nil)
    }
}

/// A generation check protects against late responses even if a network request
/// ignores cancellation. Only the current mint/amount can publish a payable quote.
@MainActor
final class BOLT12QuoteLoader: ObservableObject {
    @Published private(set) var state: MeltSourceState = .awaitingInput
    private var generation = UUID()

    func reset() {
        generation = UUID()
        state = .awaitingInput
    }

    typealias FetchQuote = @Sendable (CashuSwift.Bolt12.MeltQuoteRequest, CashuSwift.Mint) async throws -> CashuSwift.Bolt12.MeltQuote
    nonisolated static let fetchFromMint: FetchQuote = { try await CashuSwift.Bolt12.requestMeltQuote($0, from: $1) }

    func load(offer: BOLT12OfferInput, amount: Int, mint: Mint, option: PaymentOption,
              fetch: FetchQuote = fetchFromMint) async {
        guard !Task.isCancelled else { return }
        reset()
        let currentGeneration = generation
        state = .loading
        do {
            let request = try offer.quoteRequest(enteredSats: amount)
            let expected = try offer.paymentAmountSat(enteredSats: amount)
            guard option.mintID == mint.mintID, option.direction == .withdraw,
                  option.method == .bolt12, option.unit == .sat else {
                throw CashuError.inputError(String(localized: "This mint does not support BOLT12 payments in sats."))
            }
            guard expected >= (option.minAmount ?? 0), expected <= (option.maxAmount ?? Int.max) else {
                throw CashuError.amountOutsideOfLimitRange
            }
            guard mint.balance(for: .sat) >= expected else {
                state = .insufficientBalance
                return
            }
            let response = try await fetch(request, CashuSwift.Mint(mint))
            guard generation == currentGeneration, !Task.isCancelled else { return }
            try offer.validateExpiry()
            guard !response.quote.isEmpty, response.amount == expected, response.unit == "sat", response.state == .unpaid,
                  response.request == nil || response.request == offer.request else {
                throw CashuError.inputError(String(localized: "The mint's quote does not match this payment."))
            }
            let quote = LightningMeltQuote.bolt12(.init(quote: response.quote, request: offer.request,
                                                       amount: response.amount, unit: response.unit,
                                                       feeReserve: response.feeReserve, state: response.state,
                                                       expiry: response.expiry, paymentPreimage: response.paymentPreimage,
                                                       change: response.change))
            try LightningMeltQuote.validatePayment([quote])
            let required = try quote.requiredInputAmount(inputFee: 0)
            guard mint.select(amount: required, unit: .sat) != nil else {
                state = .insufficientBalance
                return
            }
            state = .ready(bundles: [.init(mint: mint, quote: quote)], totalFee: quote.feeReserve)
        } catch {
            guard generation == currentGeneration, !Task.isCancelled else { return }
            state = .error(error.localizedDescription)
        }
    }
}

struct BOLT12MeltQuoteSource: View {
    let offer: String
    let fetchQuote: BOLT12QuoteLoader.FetchQuote
    @Binding var amountConfirmed: Bool
    @Binding var state: MeltSourceState
    @EnvironmentObject private var appState: AppState
    @Query(filter: #Predicate<Wallet> { $0.active }) private var wallets: [Wallet]
    @StateObject private var loader = BOLT12QuoteLoader()
    @State private var parsed: BOLT12OfferInput?
    @State private var inputError: String?
    @State private var amount = 0
    @State private var options: [UUID: PaymentOption] = [:]
    @State private var loadingMints = true
    @State private var selectedMintID: UUID?
    @State private var showSelector = false
    @State private var retry = 0

    init(offer: String, amountConfirmed: Binding<Bool>, state: Binding<MeltSourceState>,
         fetchQuote: @escaping BOLT12QuoteLoader.FetchQuote = BOLT12QuoteLoader.fetchFromMint) {
        self.offer = offer
        self._amountConfirmed = amountConfirmed
        self._state = state
        self.fetchQuote = fetchQuote
    }

    private var mints: [Mint] {
        wallets.first?.mints.filter { !$0.hidden }
            .sorted { ($0.userIndex ?? Int.max) < ($1.userIndex ?? Int.max) } ?? []
    }
    private var supportingMints: [Mint] { mints.filter { options[$0.mintID] != nil } }
    private var selectedMint: Mint? { supportingMints.first { $0.mintID == selectedMintID } }
    private var needsAmount: Bool { parsed?.amountMsat == nil && !amountConfirmed }
    private var expectedAmount: Int? { try? parsed?.paymentAmountSat(enteredSats: amount) }
    private var validAmount: Bool { (try? parsed?.paymentAmountMsat(enteredSats: amount)) != nil }

    private struct QuoteKey: Hashable {
        let mintID: UUID
        let amount: Int
        let retry: Int
    }
    private var quoteKey: QuoteKey? {
        guard parsed != nil, !needsAmount, !loadingMints, let selectedMint, let expectedAmount else { return nil }
        return QuoteKey(mintID: selectedMint.mintID, amount: expectedAmount, retry: retry)
    }

    var body: some View {
        List {
            Section {
                Text(parsed?.request ?? offer).monospaced().lineLimit(1)
                if let description = parsed?.description, !description.isEmpty {
                    Text(description).foregroundStyle(.secondary)
                }
                if parsed != nil {
                    if needsAmount {
                        NumericalInputView(output: $amount, baseUnit: .sat,
                                           exchangeRates: appState.exchangeRates, onReturn: confirmAmount)
                    } else {
                        HStack {
                            Text("Amount: ")
                            Spacer()
                            AmountView(amount: expectedAmount ?? 0, unit: .sat).monospaced()
                        }
                        if parsed?.amountMsat == nil {
                            Button("Change amount") {
                                loader.reset()
                                amountConfirmed = false
                                publishState()
                            }
                        }
                    }
                }
            } header: { Text("BOLT12 OFFER") }

            if let inputError {
                Section { Text(inputError).foregroundStyle(.orange) }
            } else if parsed != nil, !needsAmount {
                mintSelector
            }

            Spacer(minLength: 60).listRowBackground(Color.clear)
        }
        .task(id: offer) { await prepare() }
        .task(id: quoteKey) {
            guard quoteKey != nil, let parsed, let mint = selectedMint, let option = options[mint.mintID] else { return }
            await loader.load(offer: parsed, amount: amount, mint: mint, option: option, fetch: fetchQuote)
        }
        .onReceive(loader.$state) { newState in
            if !needsAmount, !loadingMints, selectedMint != nil { state = newState }
        }
        .onChange(of: amount) { _, _ in
            loader.reset()
            publishState()
        }
        .onChange(of: amountConfirmed) { _, _ in
            if amountConfirmed { autoSelectMint() }
            publishState()
        }
        .onDisappear { loader.reset() }
    }

    private var mintSelector: some View {
        Section {
            if loadingMints {
                HStack { ProgressView(); Text("Loading mints...").foregroundStyle(.secondary) }
            } else if supportingMints.isEmpty {
                Text("None of your mints supports BOLT12 payments in sats.").foregroundStyle(.secondary)
            } else {
                Button {
                    withAnimation { showSelector.toggle() }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(selectedMint.map { String(localized: "Pay from: \($0.displayName)") }
                                 ?? String(localized: "No mint selected"))
                            quoteStatus.font(.caption)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.secondary)
                            .rotationEffect(.degrees(showSelector ? 90 : 0))
                    }
                }
                if showSelector {
                    ForEach(supportingMints) { mint in
                        Button {
                            loader.reset()
                            selectedMintID = mint.mintID
                            retry += 1
                            publishState()
                        } label: {
                            HStack {
                                Image(systemName: selectedMintID == mint.mintID ? "checkmark.circle.fill" : "circle")
                                Text(mint.displayName)
                                Spacer()
                                AmountView(amount: mint.balance(for: .sat), unit: .sat).monospaced()
                            }
                        }
                        .disabled(mint.balance(for: .sat) < (expectedAmount ?? 0))
                    }
                }
                if case .error = loader.state {
                    Button("Try again") { loader.reset(); retry += 1; publishState() }
                }
            }
        } footer: {
            Text("BOLT12 payments must be paid in full from one mint.")
        }
    }

    @ViewBuilder private var quoteStatus: some View {
        switch loader.state {
        case .loading, .awaitingInput: Text("Loading quote...").foregroundStyle(.secondary)
        case .insufficientBalance: Text("Insufficient balance (including fees)").foregroundStyle(.red)
        case .error(let message): Text(message).foregroundStyle(.orange)
        case .ready(_, let fee):
            HStack(spacing: 4) {
                Text("Lightning fee reserve:")
                AmountView(amount: fee, unit: .sat, showUnit: false)
            }.foregroundStyle(.secondary)
        case .needsAmount: EmptyView()
        }
    }

    private func confirmAmount() {
        guard validAmount else { return }
        amountConfirmed = true
    }

    private func autoSelectMint() {
        selectedMintID = supportingMints.first(where: {
            $0.balance(for: .sat) >= (expectedAmount ?? 0)
                && (expectedAmount ?? 0) >= (options[$0.mintID]?.minAmount ?? 0)
                && (expectedAmount ?? 0) <= (options[$0.mintID]?.maxAmount ?? Int.max)
        })?.mintID ?? supportingMints.first?.mintID
        showSelector = selectedMint == nil || (selectedMint?.balance(for: .sat) ?? 0) < (expectedAmount ?? 0)
    }

    private func publishState() {
        if let inputError { state = .error(inputError) }
        else if parsed == nil { state = .loading }
        else if needsAmount { state = .needsAmount(canContinue: validAmount) }
        else if loadingMints { state = .loading }
        else if supportingMints.isEmpty { state = .error(String(localized: "No supporting mint")) }
        else { state = loader.state }
    }

    private func prepare() async {
        loader.reset()
        parsed = nil
        inputError = nil
        loadingMints = true
        options = [:]
        selectedMintID = nil
        do {
            parsed = try BOLT12OfferInput(offer)
        } catch {
            inputError = error.localizedDescription
            loadingMints = false
            publishState()
            return
        }
        publishState()
        var loaded: [UUID: PaymentOption] = [:]
        for mint in mints {
            let available = await mint.supportedPaymentOptions(direction: .withdraw)
            guard !Task.isCancelled else { return }
            loaded[mint.mintID] = available.first { $0.method == .bolt12 && $0.unit == .sat }
        }
        options = loaded
        loadingMints = false
        autoSelectMint()
        publishState()
    }
}
