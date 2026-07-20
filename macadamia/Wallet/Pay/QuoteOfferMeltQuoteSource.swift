import SwiftUI
import SwiftData
import CashuSwift

/// Quote-source view for melts initiated from a NUT-XX quote offer.
///
/// Shows the offer's details (description, amount, mint, method, expiry)
/// BEFORE claiming and requires an explicit "Claim Offer" tap: claiming is
/// the point of no return for the single-use ticket, so it must never happen
/// implicitly on appear. The claim requests a melt quote with the ticket as
/// the payment request; the resulting quote's amount is authoritative (the
/// mint's backend derives it from the ticket) and is what gets displayed and
/// spent. The claimed quote is published upward as a ready-to-execute
/// `MeltQuoteBundle`; execution and PENDING monitoring stay in `MeltView`.
struct QuoteOfferMeltQuoteSource: View {
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]

    @Binding var state: MeltSourceState
    let offer: CashuSwift.QuoteOffer

    @State private var resolvedMint: Mint?
    @State private var isAddingMint = false
    @State private var isClaiming = false
    @State private var claimedQuote: CashuSwift.Generic.MeltQuote?
    @State private var statusMessage: String?

    @State private var showAlert = false
    @State private var currentAlert: AlertDetail?

    init(offer: CashuSwift.QuoteOffer, state: Binding<MeltSourceState>) {
        self.offer = offer
        self._state = state
    }

    var body: some View {
        List {
            QuoteOfferDetailSection(offer: offer,
                                    resolvedMintName: resolvedMint?.displayName)

            if resolvedMint == nil {
                unknownMintSection
            }

            if let claimedQuote, let resolvedMint {
                quoteSection(mint: resolvedMint, quote: claimedQuote)
            } else {
                claimSection
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
        .onAppear { resolveMint() }
        .alertView(isPresented: $showAlert, currentAlert: currentAlert)
    }

    // MARK: - Sections

    private var unknownMintSection: some View {
        Section {
            Button {
                confirmAddMint()
            } label: {
                HStack {
                    Text("Add Mint")
                    Spacer()
                    if isAddingMint {
                        ProgressView()
                    } else {
                        Image(systemName: "plus.circle")
                    }
                }
            }
            .disabled(isAddingMint)
        } footer: {
            Text("This offer is from a mint that is not in your wallet yet. It has to be added before the offer can be claimed.")
        }
    }

    private var claimSection: some View {
        Section {
            Button {
                claimOffer()
            } label: {
                HStack {
                    Text("Claim Offer")
                    Spacer()
                    if isClaiming {
                        ProgressView()
                    } else {
                        Image(systemName: "ticket")
                    }
                }
            }
            .disabled(claimDisabled)
        } footer: {
            Text("Claiming is final: the offer's single-use ticket will be bound to this wallet's quote.")
        }
    }

    private func quoteSection(mint: Mint, quote: CashuSwift.Generic.MeltQuote) -> some View {
        let unit = Unit(code: quote.unit)
        return Section {
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
            if let state = quote.state {
                HStack {
                    Text("State")
                    Spacer()
                    Text(state.rawValue.capitalized)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("CLAIMED MELT QUOTE")
        } footer: {
            Text("The amount is determined by the mint from the offer's ticket.")
        }
    }

    // MARK: - Derived state

    private var activeWallet: Wallet? { wallets.first }

    private var claimDisabled: Bool {
        resolvedMint == nil || isClaiming || claimedQuote != nil || offer.isExpired()
    }

    // MARK: - Mint resolution

    private func resolveMint() {
        guard resolvedMint == nil else { return }
        guard let activeWallet else {
            statusMessage = String(localized: "No active wallet could be found for this operation.")
            state = .error(String(localized: "No wallet"))
            return
        }

        // Hidden mints count: they can hold spendable proofs (e.g. added by swaps).
        if let match = QuoteOfferTools.matchMint(url: offer.mintURL, in: activeWallet.mints) {
            resolvedMint = match
        }
    }

    private func confirmAddMint() {
        let host = URL(string: offer.mintURL)?.host() ?? offer.mintURL
        displayAlert(alert: AlertDetail(title: String(localized: "Add Mint?"),
                                        description: String(localized: "This offer is from mint \(host) which is not in your wallet. Would you like to add it?"),
                                        primaryButton: AlertButton(title: String(localized: "Add"),
                                                                   action: { addMint() }),
                                        secondaryButton: AlertButton(title: String(localized: "Cancel"),
                                                                     role: .cancel,
                                                                     action: {})))
    }

    private func addMint() {
        guard let url = URL(string: offer.mintURL) else {
            statusMessage = String(localized: "The offer does not contain a valid mint URL.")
            state = .error(String(localized: "Invalid mint URL"))
            return
        }

        isAddingMint = true
        Task {
            do {
                let sendableMint = try await CashuSwift.loadMint(url: url)
                try await MainActor.run {
                    let mint = try AppSchemaV1.addMint(sendableMint, to: modelContext, hidden: true)
                    try modelContext.save()
                    logger.info("added mint \(sendableMint.url.absoluteString) while claiming a quote offer")
                    withAnimation { resolvedMint = mint }
                    isAddingMint = false
                }
            } catch {
                await MainActor.run {
                    isAddingMint = false
                    logger.error("could not add mint \(offer.mintURL) for quote offer due to error \(error)")
                    displayAlert(alert: AlertDetail(with: error))
                }
            }
        }
    }

    // MARK: - Claiming

    private func claimOffer() {
        guard let resolvedMint, !isClaiming, claimedQuote == nil else { return }

        guard !offer.isExpired() else {
            statusMessage = String(localized: "This offer has expired. Ask the teller to issue a new one.")
            state = .error(String(localized: "Offer expired"))
            return
        }

        guard QuoteOfferTools.hasKeyset(for: offer.unit, on: resolvedMint) else {
            statusMessage = String(localized: "Mint \(resolvedMint.displayName) has no active keyset for unit \(offer.unit.uppercased()), so this offer cannot be claimed.")
            state = .error(String(localized: "Unsupported unit"))
            return
        }

        isClaiming = true
        state = .loading
        let sendableMint = CashuSwift.Mint(resolvedMint)

        Task { @MainActor in
            do {
                let quote = try await CashuSwift.QuoteOffers.requestMeltQuote(offer: offer,
                                                                              from: sendableMint)
                withAnimation { claimedQuote = quote }
                statusMessage = nil
                publishState()
            } catch {
                logger.error("claiming melt offer failed with error \(error)")
                let alert = QuoteOfferTools.claimAlertDetail(for: error)
                statusMessage = alert.alertDescription ?? alert.title
                state = .error(alert.title)
                displayAlert(alert: alert)
            }
            isClaiming = false
        }
    }

    // MARK: - State publishing

    private func publishState() {
        guard let resolvedMint, let claimedQuote else {
            state = .awaitingInput
            return
        }

        switch claimedQuote.state {
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

        if let expiry = claimedQuote.expiry,
           Date(timeIntervalSince1970: TimeInterval(expiry)) < Date.now {
            statusMessage = String(localized: "This quote has expired.")
            state = .error(String(localized: "Quote expired"))
            return
        }

        let unit = Unit(code: claimedQuote.unit)
        let required = (try? claimedQuote.requiredInputAmount(inputFee: 0)) ?? claimedQuote.amount
        if resolvedMint.balance(for: unit) < required {
            statusMessage = String(localized: "Insufficient balance (including fees) with mint \(resolvedMint.displayName).")
            state = .insufficientBalance
            return
        }

        state = .ready(bundles: [MeltQuoteBundle(mint: resolvedMint, quote: claimedQuote)],
                       totalFee: QuoteExecutor.feeReserve(of: claimedQuote))
    }

    private func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}
