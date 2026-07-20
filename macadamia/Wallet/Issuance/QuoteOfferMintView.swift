import CashuSwift
import SwiftData
import SwiftUI

/// Flow for claiming a NUT-XX mint offer (e.g. a cash deposit at a teller).
///
/// 1. Shows the offer's details and requires an explicit "Claim Offer" tap —
///    the single-use ticket must never be claimed implicitly on appear.
/// 2. Claiming requests a NUT-04 mint quote referencing the ticket, locked to
///    a NUT-20 pubkey derived deterministically from the wallet seed and the
///    ticket (see `QuoteOfferTools.nut20Counter`), and persists a pending
///    mint event so the claim survives an app restart.
/// 3. The claimed state is what the customer shows the teller BEFORE handing
///    over cash — per spec, the operator must not accept payment until the
///    payer confirms their wallet holds the claimed quote.
/// 4. The quote state is polled; once the operator marks it PAID the wallet
///    issues the ecash with a NUT-20 signature.
struct QuoteOfferMintView: View {

    let offer: CashuSwift.QuoteOffer

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]

    @State private var resolvedMint: Mint?
    @State private var isAddingMint = false

    @State private var quote: CashuSwift.Generic.MintQuote?
    @State private var pendingMintEvent: Event?

    @State private var buttonState: ActionButtonState = .idle("...")
    @State private var pollingTimer: Timer?
    @State private var isCheckingQuoteState = false
    @State private var isMinting = false
    @State private var minted = false

    @State private var showAlert = false
    @State private var currentAlert: AlertDetail?

    private var activeWallet: Wallet? {
        wallets.first
    }

    var body: some View {
        ZStack {
            List {
                QuoteOfferDetailSection(offer: offer,
                                        resolvedMintName: resolvedMint?.displayName)

                if resolvedMint == nil {
                    unknownMintSection
                }

                if quote != nil {
                    claimedSection
                } else {
                    Section {
                        EmptyView()
                    } footer: {
                        Text("Claiming is final: the offer's single-use ticket will be bound to this wallet's quote. Only claim while you are ready to complete the deposit.")
                    }
                }

                Spacer(minLength: 50)
                    .listRowBackground(Color.clear)
            }
            .lineLimit(1)

            VStack {
                Spacer()
                ActionButton(state: $buttonState)
                    .actionDisabled(actionButtonDisabled)
            }
        }
        .navigationTitle("Quote Offer")
        .alertView(isPresented: $showAlert, currentAlert: currentAlert)
        .onAppear {
            resolveMint()
            updateButtonState()
        }
        .onDisappear {
            pollingTimer?.invalidate()
        }
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

    @ViewBuilder
    private var claimedSection: some View {
        if let quote {
            Section {
                if minted {
                    Label {
                        Text("Ecash issued")
                            .bold()
                    } icon: {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    }
                    .font(.title3)
                } else {
                    Label {
                        Text("Quote claimed — show this to the teller")
                            .bold()
                            .lineLimit(2)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    .font(.title3)
                }

                HStack {
                    Text("Amount")
                    Spacer()
                    AmountView(amount: quote.amount ?? offer.amount ?? 0,
                               unit: Unit(code: quote.unit))
                        .monospaced()
                }
                // NOTE: claimed quotes for custom methods (cdk "branch") carry
                // no `state` field — paid-ness comes from the raw progress
                // fields via QuoteExecutor.mintQuoteIsPaid.
                if QuoteExecutor.mintQuoteIsPaid(quote) {
                    HStack {
                        Text("State")
                        Spacer()
                        Text("Paid")
                            .foregroundStyle(.green)
                    }
                } else if !minted {
                    HStack {
                        Text("Waiting for the teller to confirm...")
                            .foregroundStyle(.secondary)
                        Spacer()
                        ProgressView()
                    }
                }
                CopyableRow(label: String(localized: "Quote ID"), value: quote.quote)
            } header: {
                Text("CLAIMED QUOTE")
            } footer: {
                if !minted {
                    Text("Do not hand over cash before this screen shows the claimed quote. Ecash is issued automatically once the teller confirms the deposit.")
                }
            }
        }
    }

    // MARK: - Button orchestration

    private var actionButtonDisabled: Bool {
        if minted { return false }
        if quote == nil {
            return resolvedMint == nil || offer.isExpired()
        }
        return isMinting
    }

    private func updateButtonState() {
        if minted {
            buttonState = .idle(String(localized: "Done"), action: { dismiss() })
        } else if quote == nil {
            buttonState = .idle(String(localized: "Claim Offer"), action: { claimOffer() })
        } else {
            buttonState = .idle(String(localized: "Issue Ecash"), action: { requestMint() })
        }
    }

    // MARK: - Mint resolution

    private func resolveMint() {
        guard resolvedMint == nil, let activeWallet else { return }
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
            displayAlert(alert: AlertDetail(title: String(localized: "Invalid Mint URL"),
                                            description: String(localized: "The offer does not contain a valid mint URL.")))
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
        guard let resolvedMint, let activeWallet, quote == nil else { return }

        guard !offer.isExpired() else {
            displayAlert(alert: QuoteOfferTools.claimAlertDetail(for: CashuError.quoteOfferExpired))
            return
        }

        guard QuoteOfferTools.hasKeyset(for: offer.unit, on: resolvedMint) else {
            displayAlert(alert: AlertDetail(title: String(localized: "Unsupported Unit"),
                                            description: String(localized: "Mint \(resolvedMint.displayName) has no active keyset for unit \(offer.unit.uppercased()), so this offer cannot be claimed.")))
            return
        }

        buttonState = .loading()
        let sendableMint = CashuSwift.Mint(resolvedMint)

        Task { @MainActor in
            do {
                let key = try QuoteOfferTools.quoteLockingKey(seed: activeWallet.seed,
                                                              ticket: offer.ticket)
                let newQuote = try await CashuSwift.QuoteOffers.requestMintQuote(offer: offer,
                                                                                 pubkey: key.publicKey,
                                                                                 from: sendableMint)

                let event = Event.pendingMintEvent(unit: Unit(code: newQuote.unit),
                                                   shortDescription: String(localized: "Pending Ecash"),
                                                   wallet: activeWallet,
                                                   quote: newQuote,
                                                   amount: newQuote.amount ?? offer.amount ?? 0,
                                                   expiration: Date(timeIntervalSince1970: TimeInterval(newQuote.expiry ?? offer.expiry ?? 0)),
                                                   mint: resolvedMint)
                AppSchemaV1.insert([event], into: modelContext)

                withAnimation {
                    quote = newQuote
                    pendingMintEvent = event
                }
                updateButtonState()
                startPolling()
            } catch {
                logger.error("claiming mint offer failed with error \(error)")
                displayAlert(alert: QuoteOfferTools.claimAlertDetail(for: error))
                buttonState = .fail()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    updateButtonState()
                }
            }
        }
    }

    // MARK: - Quote state polling

    private func startPolling() {
        guard pollingTimer == nil || pollingTimer?.isValid == false else { return }
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true, block: { _ in
            Task { @MainActor in
                checkQuoteState()
            }
        })
    }

    @MainActor
    private func checkQuoteState() {
        guard let quote, let resolvedMint, !isCheckingQuoteState, !isMinting, !minted else { return }

        isCheckingQuoteState = true
        let sendableMint = CashuSwift.Mint(resolvedMint)

        Task {
            defer { isCheckingQuoteState = false }
            do {
                let refreshed = try await CashuSwift.QuoteOffers.mintQuoteState(quote.quote,
                                                                                method: quote.method,
                                                                                from: sendableMint)
                await MainActor.run {
                    withAnimation { self.quote = refreshed }
                    // No `state` on custom-method quotes: paid when
                    // amount_paid >= amount (raw bolt12-style progress fields).
                    if QuoteExecutor.mintQuoteIsPaid(refreshed) {
                        requestMint()
                    }
                }
            } catch {
                // Transient poll errors (network) are tolerable; keep polling.
                logger.warning("mint offer quote state poll failed with error: \(error)")
            }
        }
    }

    // MARK: - Issuance

    @MainActor
    private func requestMint() {
        guard let quote, let resolvedMint, let activeWallet, !isMinting, !minted else { return }

        pollingTimer?.invalidate()
        isMinting = true
        buttonState = .loading()

        Task {
            do {
                let issueResult = try await QuoteOfferTools.mint(offerLockedQuote: quote,
                                                                 from: CashuSwift.Mint(resolvedMint),
                                                                 seed: activeWallet.seed)

                logger.info("DLEQ check on offer issuance \(String(describing: issueResult.dleqResult))")

                try resolvedMint.addProofs(issueResult.proofs, to: modelContext)

                let event = Event.mintEvent(unit: Unit(code: quote.unit),
                                            shortDescription: "Ecash created",
                                            wallet: activeWallet,
                                            quote: quote,
                                            mint: resolvedMint,
                                            amount: issueResult.proofs.sum)

                modelContext.insert(event)
                try modelContext.save()

                pendingMintEvent?.visible = false

                withAnimation { minted = true }
                buttonState = .success()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    updateButtonState()
                }
            } catch {
                logger.error("an error occurred during offer issuance \(error)")
                await MainActor.run {
                    isMinting = false
                    displayAlert(alert: AlertDetail(with: error))
                    buttonState = .fail()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        updateButtonState()
                        startPolling()
                    }
                }
            }
            isMinting = false
        }
    }

    private func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}
