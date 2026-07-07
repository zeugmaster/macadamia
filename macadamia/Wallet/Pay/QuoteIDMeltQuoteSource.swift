import SwiftUI
import SwiftData
import CashuSwift

/// Quote-source view for melts initiated from a bare quote ID.
///
/// A quote ID carries no information about which mint issued it or through
/// which payment method, so this view probes every visible mint of the
/// active wallet — trying each advertised melt method, BOLT11 first — until
/// one of them returns the quote. The hit is displayed and published upward
/// as a ready-to-execute `MeltQuoteBundle` in the quote's own unit; the
/// actual melt stays in `MeltView`, same as for the BOLT11 source.
struct QuoteIDMeltQuoteSource: View {
    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]

    @Binding var state: MeltSourceState
    let quoteID: String

    @State private var loadedMint: Mint?
    @State private var loadedQuote: (any CashuSwift.MeltQuoteResponse)?
    @State private var statusMessage: String?
    @State private var isSearching = false

    init(quoteID: String, state: Binding<MeltSourceState>) {
        self.quoteID = quoteID
        self._state = state
    }

    var body: some View {
        List {
            Section {
                Text(quoteID)
                    .monospaced()
                if isSearching {
                    HStack {
                        Text("Checking your mints...")
                            .foregroundStyle(.secondary)
                        Spacer()
                        ProgressView()
                    }
                }
            } header: {
                Text("QUOTE ID")
            }

            if let loadedMint, let loadedQuote {
                quoteSection(mint: loadedMint, quote: loadedQuote)
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .foregroundStyle(.orange)
                        .lineLimit(3)
                }
            }

            Spacer(minLength: 50)
                .listRowBackground(Color.clear)
        }
        .lineLimit(1)
        .onAppear { findQuote() }
    }

    // MARK: - Sections

    private func quoteSection(mint: Mint, quote: any CashuSwift.MeltQuoteResponse) -> some View {
        let unit = Unit(code: quote.unit)
        return Section {
            HStack {
                Text("Mint")
                Spacer()
                Text(mint.displayName)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Amount")
                Spacer()
                AmountView(amount: quote.amount, unit: unit)
                    .monospaced()
            }
            HStack {
                Text("Fee Reserve")
                Spacer()
                AmountView(amount: QuoteExecutor.feeReserve(of: quote), unit: unit)
                    .monospaced()
                    .foregroundStyle(.secondary)
            }
            if quote.method != .bolt11 {
                HStack {
                    Text("Method")
                    Spacer()
                    Text(PaymentMethodKind(quote.method).displayName)
                        .foregroundStyle(.secondary)
                }
            }
            if let state = quote.state {
                HStack {
                    Text("State")
                    Spacer()
                    Text(state.rawValue.capitalized)
                        .foregroundStyle(.secondary)
                }
            }
            if let expiry = quote.expiry {
                HStack {
                    Text("Expires at")
                    Spacer()
                    Text(Date(timeIntervalSince1970: TimeInterval(expiry)).formatted())
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("MELT QUOTE")
        }
    }

    // MARK: - Derived state

    private var mints: [Mint] {
        wallets.first?.mints.filter({ $0.hidden == false })
            .sorted { ($0.userIndex ?? Int.max) < ($1.userIndex ?? Int.max) } ?? []
    }

    // MARK: - Lookup

    private func findQuote() {
        guard loadedQuote == nil, !isSearching else { return }

        let mintList = mints
        guard !mintList.isEmpty else {
            statusMessage = String(localized: "This wallet does not contain any mints to look the quote up with.")
            state = .error(String(localized: "No mints"))
            return
        }

        isSearching = true
        state = .loading
        let id = quoteID

        Task { @MainActor in
            // Method discovery touches the models (and the per-mint info cache),
            // so it happens here on the main actor; only the network probes fan out.
            var probes = [(mintID: UUID, sendable: CashuSwift.Mint, methods: [CashuSwift.PaymentMethodID])]()
            for mint in mintList {
                probes.append((mint.mintID, CashuSwift.Mint(mint), await mint.supportedQuoteMethodIDs(direction: .melt)))
            }

            let hit = await Self.probeMints(probes, for: id)

            isSearching = false
            guard let hit, let mint = mintList.first(where: { $0.mintID == hit.mintID }) else {
                statusMessage = String(localized: "None of your mints recognize this quote ID.")
                state = .error(String(localized: "Unknown quote ID"))
                return
            }

            withAnimation {
                loadedMint = mint
                loadedQuote = hit.quote
            }
            publishState()
        }
    }

    private static func probeMints(_ probes: [(mintID: UUID, sendable: CashuSwift.Mint, methods: [CashuSwift.PaymentMethodID])],
                                   for quoteID: String) async -> (mintID: UUID, quote: any CashuSwift.MeltQuoteResponse)? {
        await withTaskGroup(of: Optional<(UUID, any CashuSwift.MeltQuoteResponse)>.self) { group in
            for probe in probes {
                group.addTask {
                    for method in probe.methods {
                        if let quote = try? await QuoteExecutor.meltQuoteState(id: quoteID,
                                                                               method: method,
                                                                               from: probe.sendable) {
                            return (probe.mintID, quote)
                        }
                    }
                    return nil
                }
            }
            for await result in group {
                if let result {
                    group.cancelAll()
                    return (mintID: result.0, quote: result.1)
                }
            }
            return nil
        }
    }

    // MARK: - State publishing

    private func publishState() {
        guard let loadedMint, let loadedQuote else {
            state = .awaitingInput
            return
        }

        switch loadedQuote.state {
        case .paid:
            statusMessage = String(localized: "This quote has already been paid.")
            state = .error(String(localized: "Already paid"))
            return
        case .pending:
            statusMessage = String(localized: "A payment for this quote is already in flight. Check back later.")
            state = .error(String(localized: "Payment pending"))
            return
        default:
            break // unpaid, or a method that doesn't expose a state — let the mint decide
        }

        if let expiry = loadedQuote.expiry,
           Date(timeIntervalSince1970: TimeInterval(expiry)) < Date.now {
            statusMessage = String(localized: "This quote has expired.")
            state = .error(String(localized: "Quote expired"))
            return
        }

        let unit = Unit(code: loadedQuote.unit)
        let required = (try? loadedQuote.requiredInputAmount(inputFee: 0)) ?? loadedQuote.amount
        if loadedMint.balance(for: unit) < required {
            statusMessage = String(localized: "Insufficient balance (including fees) with mint \(loadedMint.displayName).")
            state = .insufficientBalance
            return
        }

        state = .ready(bundles: [MeltQuoteBundle(mint: loadedMint, quote: loadedQuote)],
                       totalFee: QuoteExecutor.feeReserve(of: loadedQuote))
    }
}
