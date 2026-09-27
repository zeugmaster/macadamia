import SwiftUI
import SwiftData
import CashuSwift

/// Quote-source view for BOLT11 melts. Owns invoice input, mint
/// selection (single-mint and MPP), per-mint quote fetching and the
/// allocation/fee display. Publishes a `MeltSourceState` upward so the
/// host can decide when the user is allowed to execute.
///
/// This view knows nothing about how the melt is actually performed;
/// `MeltView` owns that. The split keeps `MeltView` payment-method
/// agnostic so other quote sources can plug in alongside this one.
struct BOLT11MeltQuoteSource: View {
    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]

    @Binding var state: MeltSourceState
    let initialInvoice: String?

    @StateObject private var loader = BOLT11QuoteLoader()
    @State private var invoiceString: String?
    @State private var parsed: BOLT11InvoiceInput?
    @State private var selectedMints = Set<UUID>()
    @State private var autoSelect = true
    @State private var showSelector = false
    @State private var loadTask: Task<Void, Never>?

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
                    invalidateQuotes()
                    withAnimation { invoiceString = input.payload }
                }
                .padding()
            }
        }
        .onChange(of: quoteKey, initial: true) { _, _ in updateQuotes() }
        .onChange(of: loader.state) { _, newState in state = newState }
        .onDisappear { invalidateQuotes() }
    }

    // MARK: - Derived state

    private var mints: [Mint] {
        wallets.first?.mints.filter { !$0.hidden }.sorted {
            let lhs = $0.userIndex ?? Int.max, rhs = $1.userIndex ?? Int.max
            return lhs == rhs ? $0.mintID.uuidString < $1.mintID.uuidString : lhs < rhs
        } ?? []
    }

    private var candidates: [BOLT11PaymentPlan.Candidate] { mints.map { .init($0) } }
    private var invoiceAmount: Int? { parsed?.amountSat }

    /// Balances and capabilities are part of the request identity, not just mint IDs.
    private struct QuoteKey: Equatable {
        let invoice: String?
        let candidates: [BOLT11PaymentPlan.Candidate]
        let selected: Set<UUID>
        let automatic: Bool
    }

    private var quoteKey: QuoteKey {
        .init(invoice: invoiceString, candidates: candidates, selected: selectedMints, automatic: autoSelect)
    }

    private var selected: [Mint] {
        let ids: Set<UUID>
        if autoSelect, let parsed {
            let chosen = (try? BOLT11PaymentPlan.automaticSelection(input: parsed, candidates: candidates)) ?? []
            ids = Set(chosen.map(\.mintID))
        } else {
            ids = selectedMints
        }
        return mints.filter { ids.contains($0.mintID) }
    }

    private var payers: [Mint] {
        guard let plan = loader.plan else { return selected }
        let ids = Set(plan.legs.map(\.mintID))
        return mints.filter { ids.contains($0.mintID) }
    }

    private var totalSelectedMintBalance: Double {
        payers.reduce(0) { $0 + Double($1.balance(for: .sat)) }
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
                        switch payers.count {
                        case 0:
                            Text("No mint selected")
                        case 1:
                            Text("Pay from: \(payers.first?.displayName ?? "nil")")
                        default:
                            Text("Pay from \(payers.count) mints")
                        }
                        subline
                            .font(.caption)
                    }
                    Spacer()
                    if payers.count > 1 && autoSelect {
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
            if parsed?.supportsWholeSatMPP == false {
                Text(BOLT11PaymentError.fractionalMPP.localizedDescription)
                    .lineLimit(nil)
            }
            if Double(invoiceAmount ?? 0) > totalSelectedMintBalance * 0.97 {
                Text("Payment amount approaching the total balance risks payment failure due to fees.")
                    .lineLimit(3)
            }
        }
    }

    private func mintRow(_ mint: Mint) -> some View {
        let disableRow = (!mint.supportsMPP || parsed?.supportsWholeSatMPP == false) && mint.balance(for: .sat) < (invoiceAmount ?? 0)
        return HStack {
            Button {
                toggleSelection(for: mint)
            } label: {
                Image(systemName: payers.contains(mint) ? "checkmark.circle.fill" : "circle")
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
                    if let entry = loader.entries[mint.mintID] {
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
        switch loader.state {
        case .awaitingInput, .needsAmount:
            Text("Tap to select a mint from the list")
                .foregroundStyle(.secondary)
        case .loading:
            Text("Loading quotes...")
                .foregroundStyle(.secondary)
        case .error(let message):
            Text(message)
                .foregroundStyle(.orange)
                .lineLimit(nil)
        case .insufficientBalance:
            Text("Insufficient balance (including fees)")
                .foregroundStyle(.red)
        case .ready(_, let totalFee):
            HStack(spacing: 4) {
                Text("Total Lightning Fees:")
                AmountView(amount: totalFee, unit: .sat, showUnit: false)
            }
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Selection and quote loading

    private func toggleSelection(for mint: Mint) {
        var selection = Set(payers.map(\.mintID))
        let hasNonMPP = payers.contains { !$0.supportsMPP }
        invalidateQuotes()
        withAnimation { autoSelect = false }
        if selection.contains(mint.mintID) {
            selection.remove(mint.mintID)
        } else if parsed?.supportsWholeSatMPP == false || !mint.supportsMPP || hasNonMPP {
            selection = [mint.mintID]
        } else {
            selection.insert(mint.mintID)
        }
        selectedMints = selection
    }

    private func invalidateQuotes() {
        loadTask?.cancel()
        loader.reset()
        state = .awaitingInput
    }

    private func updateQuotes() {
        invalidateQuotes()
        parsed = nil
        guard let invoiceString else { return }
        do {
            let input = try BOLT11InvoiceInput(invoiceString)
            parsed = input
            let currentMints = mints
            let currentCandidates = candidates.filter { autoSelect || selectedMints.contains($0.mintID) }
            let automatic = autoSelect
            loader.reset(state: .loading)
            state = .loading
            loadTask = Task {
                await loader.load(input: input, candidates: currentCandidates,
                                  automatic: automatic, mints: currentMints)
            }
        } catch {
            loader.reset(state: .error(error.localizedDescription))
            state = loader.state
        }
    }
}
