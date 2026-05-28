import SwiftUI
import SwiftData
import CashuSwift

/// A `(Mint, MeltQuote)` pair that's been validated and is ready for execution.
///
/// Produced by a quote-source view and consumed by `MeltView` to run the
/// actual melt operation. The bundle is intentionally specific to BOLT11
/// today; future payment methods will either add their own bundle shape or
/// drive a generalization here.
struct MeltQuoteBundle: Equatable {
    let mint: Mint
    let quote: CashuSwift.Bolt11.MeltQuote

    static func == (lhs: MeltQuoteBundle, rhs: MeltQuoteBundle) -> Bool {
        lhs.mint.mintID == rhs.mint.mintID &&
        lhs.quote.quote == rhs.quote.quote
    }
}

/// What a quote-source view publishes back to its host so the host can
/// drive its action button and decide when to invoke execution.
enum MeltSourceState: Equatable {
    case awaitingInput
    case loading
    case insufficientBalance
    case error(String)
    case ready(bundles: [MeltQuoteBundle], totalFee: Int)
}

/// Quote-source view for BOLT11 melts. Owns invoice input, mint
/// selection (single-mint and MPP), per-mint quote fetching and the
/// allocation/fee display. Publishes a `MeltSourceState` upward so the
/// host can decide when the user is allowed to execute.
///
/// This view knows nothing about how the melt is actually performed;
/// `MeltView` owns that. The split keeps `MeltView` payment-method
/// agnostic so future quote sources (BOLT12, on-chain, generic) can
/// plug in alongside this one.
struct BOLT11MeltQuoteSource: View {
    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]

    @Binding var state: MeltSourceState
    let initialInvoice: String?

    private enum QuoteEntry: Equatable {
        case quote(CashuSwift.Bolt11.MeltQuote)
        case error(String)

        static func == (lhs: QuoteEntry, rhs: QuoteEntry) -> Bool {
            switch (lhs, rhs) {
            case (.quote(let l), .quote(let r)):
                return l.quote == r.quote && l.amount == r.amount && l.feeReserve == r.feeReserve
            case (.error(let l), .error(let r)):
                return l == r
            default:
                return false
            }
        }
    }

    @State private var invoiceString: String?
    @State private var quoteEntries: [Mint: QuoteEntry] = [:]
    @State private var selectedMints = Set<Mint>()
    @State private var autoSelect = true
    @State private var showSelector = false

    init(initialInvoice: String?, state: Binding<MeltSourceState>) {
        self.initialInvoice = initialInvoice
        self._state = state
        if let initialInvoice {
            _invoiceString = State(initialValue: initialInvoice)
        }
    }

    var body: some View {
        Group {
            if let invoiceString {
                List {
                    invoiceSection(invoiceString)
                    mintSelector
                    Spacer(minLength: 50)
                        .listRowBackground(Color.clear)
                }
                .lineLimit(1)
            } else {
                InputView(supportedTypes: [.bolt11Invoice]) { input in
                    withAnimation { invoiceString = input.payload }
                }
                .padding()
            }
        }
        .onAppear {
            recomputeState()
            updateQuotes()
        }
        .onChange(of: invoiceString) { _, _ in
            // Old quotes belong to the previous invoice.
            quoteEntries = [:]
            recomputeState()
            updateQuotes()
        }
        .onChange(of: selectedMints) { _, _ in recomputeState() }
        .onChange(of: autoSelect) { _, _ in recomputeState() }
        .onChange(of: quoteEntries) { _, _ in recomputeState() }
    }

    // MARK: - Derived state

    private var activeWallet: Wallet? { wallets.first }

    private var mints: [Mint] {
        activeWallet?.mints.filter({ $0.hidden == false })
            .sorted { ($0.userIndex ?? Int.max) < ($1.userIndex ?? Int.max) } ?? []
    }

    private var invoiceAmount: Int? {
        try? invoiceString.map({ try CashuSwift.Bolt11.satAmount(from: $0) })
    }

    private var totalFee: Int {
        quoteEntries.values.compactMap { entry -> Int? in
            if case .quote(let q) = entry { return q.feeReserve }
            return nil
        }.reduce(0, +)
    }

    private var totalSelectedMintBalance: Int {
        selected.reduce(0, { $0 + $1.balance(for: .sat) })
    }

    private var insufficientBalance: Bool {
        totalSelectedMintBalance < (invoiceAmount ?? 0) + totalFee
    }

    /// The mints the user is paying from — either the explicit selection or
    /// — while `autoSelect` is on — the auto-derived selection that satisfies
    /// the invoice amount.
    private var selected: Set<Mint> {
        if autoSelect {
            guard let amount = invoiceAmount, amount > 0 else { return [] }
            let ordered = mints
            if let single = ordered.first(where: { $0.balance(for: .sat) >= amount }) {
                return [single]
            }
            let mpp = ordered.filter { $0.supportsMPP }
            let total = mpp.reduce(0) { $0 + $1.balance(for: .sat) }
            if total < amount {
                DispatchQueue.main.async { self.autoSelect = false }
                return []
            }
            let ranked = mpp.sorted {
                let lb = $0.balance(for: .sat), rb = $1.balance(for: .sat)
                return lb == rb ? (($0.userIndex ?? Int.max) < ($1.userIndex ?? Int.max)) : (lb > rb)
            }
            var acc = 0
            var chosen = [Mint]()
            for mint in ranked where acc < amount {
                chosen.append(mint)
                acc += mint.balance(for: .sat)
            }
            return Set(chosen)
        }
        return selectedMints
    }

    private var hasQuoteError: Bool {
        quoteEntries.values.contains(where: { if case .error = $0 { true } else { false } })
    }

    private var allSelectedHaveQuotes: Bool {
        let s = selected
        guard !s.isEmpty else { return false }
        return s.allSatisfy { mint in
            if case .quote = quoteEntries[mint] { return true }
            return false
        }
    }

    /// Sum of `quote.amount` across all loaded quotes for the current
    /// selection. Used to cross-check against the invoice's own amount —
    /// a mismatch (MPP allocation rounding, mint disagreement, …) is
    /// surfaced as an error rather than silently overpaying or underpaying.
    private var quoteAmountSum: Int {
        quoteEntries.values.compactMap { entry -> Int? in
            if case .quote(let q) = entry { return q.amount }
            return nil
        }.reduce(0, +)
    }

    private var hasAmountMismatch: Bool {
        guard allSelectedHaveQuotes, let expectedAmount = invoiceAmount else {
            return false
        }
        return quoteAmountSum != expectedAmount
    }

    // MARK: - Sections

    private func invoiceSection(_ invoiceString: String) -> some View {
        Section {
            Text(invoiceString)
                .monospaced()
            HStack {
                Text("Amount: ")
                Spacer()
                AmountView(amount: invoiceAmount ?? 0, unit: .sat)
                    .monospaced()
            }
            .foregroundStyle(.secondary)
        } header: {
            Text("BOLT11 INVOICE")
        }
    }

    private var mintSelector: some View {
        Section {
            Button {
                withAnimation { showSelector.toggle() }
            } label: {
                HStack {
                    VStack(alignment: .leading) {
                        switch selected.count {
                        case 0:
                            Text("No mint selected")
                        case 1:
                            Text("Pay from: \(selected.first?.displayName ?? "nil")")
                        default:
                            Text("Pay from \(selected.count) mints")
                        }
                        subline
                            .font(.caption)
                    }
                    Spacer()
                    if selected.count > 1 && autoSelect {
                        Image(systemName: "wand.and.stars")
                            .foregroundColor(.secondary)
                            .font(.title3)
                            .transition(.scale.combined(with: .opacity))
                            .help("Mints automatically selected for optimal payment")
                    }
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.footnote)
                        .rotationEffect(.degrees(showSelector ? 90 : 0))
                }
            }

            if showSelector {
                ForEach(mints) { mint in
                    mintRow(mint)
                }
            }
        } footer: {
            if Double(invoiceAmount ?? 0) > Double(totalSelectedMintBalance) * 0.97 {
                Text("Payment amount approaching the total balance risks payment failure due to fees.")
                    .lineLimit(3)
            }
        }
    }

    private func mintRow(_ mint: Mint) -> some View {
        let disableRow = !mint.supportsMPP && mint.balance(for: .sat) < (invoiceAmount ?? 0)
        return HStack {
            Button {
                toggleSelection(for: mint)
            } label: {
                Image(systemName: selected.contains(mint) ? "checkmark.circle.fill" : "circle")
            }
            .disabled(disableRow)

            VStack {
                HStack {
                    Text(mint.displayName)
                    Spacer()
                    AmountView(amount: mint.balance(for: .sat), unit: .sat)
                        .monospaced()
                }
                .foregroundStyle(disableRow ? .secondary : .primary)
                HStack {
                    if mint.supportsMPP {
                        Text(String(localized: "MPP"))
                        Image(systemName: "checkmark")
                    } else {
                        Text(String(localized: "Full payment"))
                    }
                    Spacer()
                    if let entry = quoteEntries[mint] {
                        switch entry {
                        case .quote(let quote):
                            HStack(spacing: 4) {
                                Text("Fee:")
                                AmountView(amount: quote.feeReserve, unit: .sat, showUnit: false)
                                Text("• Allocation:")
                                AmountView(amount: quote.amount, unit: .sat, showUnit: false)
                            }
                        case .error(let error):
                            Text(error)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .foregroundStyle(.secondary)
                .font(.caption)
            }
        }
    }

    @ViewBuilder
    private var subline: some View {
        if selected.isEmpty {
            Text("Tap to select a mint from the list")
                .foregroundStyle(.secondary)
        } else if hasQuoteError {
            Text("Error")
                .foregroundStyle(.orange)
        } else if !allSelectedHaveQuotes {
            Text("Loading quotes...")
                .foregroundStyle(.secondary)
        } else if hasAmountMismatch {
            Text("Quote amounts don't match invoice")
                .foregroundStyle(.orange)
        } else if insufficientBalance {
            Text("Insufficient balance (including fees)")
                .foregroundStyle(.red)
        } else {
            HStack(spacing: 4) {
                Text("Total Lightning Fees:")
                AmountView(amount: totalFee, unit: .sat, showUnit: false)
            }
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Selection

    private func toggleSelection(for mint: Mint) {
        if autoSelect { selectedMints = selected }
        withAnimation { autoSelect = false }

        let hasNonMPP = selectedMints.contains { !$0.supportsMPP }
        switch (selectedMints.contains(mint), mint.supportsMPP, hasNonMPP) {
        case (true, _, _):
            selectedMints.remove(mint)
        case (false, false, _):
            selectedMints.removeAll()
            selectedMints.insert(mint)
        case (false, true, true):
            selectedMints.removeAll()
            selectedMints.insert(mint)
        case (false, true, false):
            selectedMints.insert(mint)
        }
        quoteEntries = [:]

        updateQuotes()
    }

    // MARK: - Quote fetching

    private func updateQuotes() {
        guard let total = invoiceAmount, let invoiceString else {
            recomputeState()
            return
        }

        let currentSelected = selected
        guard !currentSelected.isEmpty else {
            recomputeState()
            return
        }

        let totalSelectedBalance = currentSelected.reduce(0) { $0 + $1.balance(for: .sat) }
        if total > totalSelectedBalance {
            // Don't bother asking the mints — recomputeState will surface
            // the insufficientBalance signal.
            recomputeState()
            return
        }

        let allocationsSendable = msatAllocations(for: total,
                                                  mints: Array(currentSelected)).map { (mint, allocation) in
            (CashuSwift.Mint(mint), allocation)
        }

        Task {
            var results = [(CashuSwift.Mint, QuoteEntry)]()
            for (mint, msat) in allocationsSendable {
                do {
                    let quote = try await loadQuote(mint: mint,
                                                    invoice: invoiceString,
                                                    msat: msat,
                                                    isMPP: allocationsSendable.count > 1)
                    results.append((mint, .quote(quote)))
                } catch CashuError.networkError {
                    results.append((mint, .error(String(localized: "Network error"))))
                } catch CashuError.unknownError(let message) where message.contains("internal mpp not allowed") {
                    logger.warning("user tried to perform self-pay")
                    results.append((mint, .error(String(localized: "Self-pay not possible"))))
                } catch {
                    logger.warning("Error when fetching quote: \(error)")
                    results.append((mint, .error(String(localized: "Unknown error"))))
                }
            }
            await MainActor.run {
                for result in results {
                    if let mint = currentSelected.first(where: { $0.matches(result.0) }) {
                        quoteEntries[mint] = result.1
                    }
                }
            }
        }
    }

    private func loadQuote(mint: CashuSwift.Mint,
                           invoice: String,
                           msat: Int,
                           isMPP: Bool) async throws -> CashuSwift.Bolt11.MeltQuote {
        if isMPP {
            let request = CashuSwift.Generic.MeltQuoteRequest(
                method: .bolt11,
                unit: Unit.sat.currencyCode,
                request: invoice,
                extra: [
                    "options": .object([
                        "mpp": .object([
                            "amount": .integer(Int64(msat))
                        ])
                    ])
                ]
            )
            let quote = try await CashuSwift.Generic.requestMeltQuote(request, from: mint)
            return CashuSwift.Bolt11.MeltQuote(quote: quote.quote,
                                               request: invoice,
                                               amount: quote.amount,
                                               unit: quote.unit,
                                               feeReserve: quote.feeReserve,
                                               state: quote.state,
                                               expiry: quote.expiry,
                                               paymentPreimage: quote.paymentPreimage,
                                               change: quote.change)
        }

        let request = CashuSwift.Bolt11.MeltQuoteRequest(unit: Unit.sat.currencyCode,
                                                         request: invoice,
                                                         options: nil)
        return try await CashuSwift.Bolt11.requestMeltQuote(request, from: mint)
    }

    private func msatAllocations(for total: Int, mints: [Mint]) -> [Mint: Int] {
        let totalBalance = mints.reduce(0) { $0 + $1.balance(for: .sat) }
        guard totalBalance > 0, total > 0 else {
            return Dictionary(uniqueKeysWithValues: mints.map { ($0, 0) })
        }

        let totalMsat = total * 1_000

        // Per-mint share is balance-weighted, but cashu proofs are whole
        // sats, so each share has to be a multiple of 1000 msat. Floor
        // each share, then hand out the leftover sats using the
        // largest-remainder method — the mint whose share got truncated
        // the most picks up the extra sat first. This keeps the per-mint
        // shares close to their proportional ideal AND makes the sum
        // exactly equal the invoice amount (vs. the old per-mint round-up,
        // which could overshoot the invoice and produce quote sums larger
        // than the invoice amount).
        var allocations: [Mint: Int] = [:]
        var remainders: [(mint: Mint, remainder: Int)] = []

        for mint in mints {
            let exactMsat = mint.balance(for: .sat) * totalMsat / totalBalance
            let floored = (exactMsat / 1000) * 1000
            allocations[mint] = floored
            remainders.append((mint, exactMsat - floored))
        }

        let assigned = allocations.values.reduce(0, +)
        var leftover = totalMsat - assigned

        // Distribute the leftover whole sats. Largest remainder first;
        // ties broken by larger balance.
        remainders.sort { lhs, rhs in
            if lhs.remainder != rhs.remainder { return lhs.remainder > rhs.remainder }
            return lhs.mint.balance(for: .sat) > rhs.mint.balance(for: .sat)
        }

        var idx = 0
        while leftover >= 1000 && idx < remainders.count {
            allocations[remainders[idx].mint, default: 0] += 1000
            leftover -= 1000
            idx += 1
        }

        logger.info("created payment amount splits for \(total): \(allocations.map({ $0.key.url.absoluteString + ": " + String($0.value) }).joined(separator: ", "))")

        return allocations
    }

    // MARK: - State publishing

    private func recomputeState() {
        let currentSelected = selected

        guard invoiceString != nil, let expectedAmount = invoiceAmount else {
            state = .awaitingInput
            return
        }

        if currentSelected.isEmpty {
            state = .awaitingInput
            return
        }

        if hasQuoteError {
            state = .error(String(localized: "Quote fetch failed"))
            return
        }

        if !allSelectedHaveQuotes {
            state = .loading
            return
        }

        // Mints' quoted amounts must sum to the BOLT11 invoice amount.
        // A mismatch (MPP allocation rounding, mint disagreement, etc.) is
        // surfaced rather than silently over- or under-paying.
        if quoteAmountSum != expectedAmount {
            logger.warning("BOLT11MeltQuoteSource: quote sum (\(quoteAmountSum)) doesn't match invoice amount (\(expectedAmount))")
            state = .error(String(localized: "Quote amount mismatch"))
            return
        }

        if insufficientBalance {
            state = .insufficientBalance
            return
        }

        var bundles: [MeltQuoteBundle] = []
        for mint in currentSelected {
            if case .quote(let quote) = quoteEntries[mint] {
                bundles.append(MeltQuoteBundle(mint: mint, quote: quote))
            }
        }
        state = .ready(bundles: bundles, totalFee: totalFee)
    }
}
