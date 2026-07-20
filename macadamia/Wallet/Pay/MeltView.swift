import SwiftUI
import SwiftData
import CashuSwift

// TODO: remove unsafe unwrapping, nicer pending error

/// Hosts a payment-method-specific quote source (`BOLT11MeltQuoteSource`
/// for invoices, `QuoteOfferMeltQuoteSource` for NUT-XX quote offers), then
/// executes the resulting `MeltQuoteBundle`s — proof selection, blank outputs,
/// persistent event bookkeeping, and the actual melt calls dispatched
/// through `QuoteExecutor`. Also handles resume mode for pending payments
/// and the post-execute "check state" loop. Everything below the source is
/// intentionally payment-method agnostic so sources can be swapped without
/// touching execution.
///
/// Offer melts are always asynchronous per NUT-XX: the mint answers the melt
/// request with `PENDING`, so this view auto-polls the quote state and shows
/// a teller-facing payment code (derived from the secret quote ID) until —
/// and after — the payment completes.
struct MeltView: View {

    /// The user input a quote source is derived from.
    enum PaymentInput: Equatable {
        case bolt11Invoice(String)
        case quoteOffer(CashuSwift.QuoteOffer)
    }

    struct MeltTaskInput {
        let mint: CashuSwift.Mint
        let proofs: [CashuSwift.Proof]
        let quote: any CashuSwift.MeltQuoteResponse
        let blankOutputs: (outputs: [CashuSwift.Output], blindingFactors: [String], secrets: [String])?
    }

    struct MeltTaskResult {
        let mint: CashuSwift.Mint
        let quote: any CashuSwift.MeltQuoteResponse
        let change: [CashuSwift.Proof]
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissToRoot) private var dismissToRoot

    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]

    @State private var paymentInput: PaymentInput?
    @State private var pendingMeltEvents: [Event]

    // What the source view publishes upward. Drives the action button and
    // gates execution.
    @State private var sourceState: MeltSourceState = .awaitingInput

    @State private var buttonState = ActionButtonState.idle("...")

    @State private var showAlert = false
    @State private var currentAlert: AlertDetail?

    // Offer-melt async execution: polling driver and terminal state.
    @State private var pollingTimer: Timer?
    @State private var isPollingMeltState = false
    @State private var offerMeltPaid = false

    // A mint offer scanned in the inline input (a teller hands out one QR for
    // either operation) routes onward to the offer-mint flow.
    @State private var routedMintOffer: CashuSwift.QuoteOffer?

    private var activeWallet: Wallet? {
        wallets.first
    }

    private var mints: [Mint] {
        activeWallet?.mints.filter({ $0.hidden == false })
            .sorted { ($0.userIndex ?? Int.max) < ($1.userIndex ?? Int.max) } ?? []
    }

    private var actionButtonDisabled: Bool {
        if !pendingMeltEvents.isEmpty { return false }
        if case .ready = sourceState { return false }
        return true
    }

    init(events: [Event]? = nil, invoice: String? = nil, quoteOffer: CashuSwift.QuoteOffer? = nil) {
        if let events {
            _pendingMeltEvents = State(initialValue: events)
            _paymentInput = State(initialValue: nil)
        } else {
            _pendingMeltEvents = State(initialValue: [])
            if let invoice {
                _paymentInput = State(initialValue: .bolt11Invoice(invoice))
            } else if let quoteOffer {
                _paymentInput = State(initialValue: .quoteOffer(quoteOffer))
            } else {
                _paymentInput = State(initialValue: nil)
            }
        }
    }

    var body: some View {
        ZStack {
            if !pendingMeltEvents.isEmpty {
                pendingMeltSummaryView
            } else {
                switch paymentInput {
                case .bolt11Invoice(let invoice):
                    BOLT11MeltQuoteSource(initialInvoice: invoice,
                                          state: $sourceState)
                case .quoteOffer(let offer):
                    QuoteOfferMeltQuoteSource(offer: offer,
                                              state: $sourceState)
                case nil:
                    InputView(supportedTypes: [.bolt11Invoice, .quoteOffer]) { input in
                        handleInput(input)
                    }
                    .padding()
                }
            }
            VStack {
                Spacer()
                ActionButton(state: $buttonState)
                    .actionDisabled(actionButtonDisabled)
            }
        }
        .alertView(isPresented: $showAlert, currentAlert: currentAlert)
        .onAppear {
            updateButtonState()
            // Resuming a pending offer melt: the payment is asynchronous, so
            // pick the state monitoring back up right away.
            if isOfferMelt && !pendingMeltEvents.isEmpty && !offerMeltPaid {
                startOfferMeltPolling()
            }
        }
        .onDisappear { pollingTimer?.invalidate() }
        .onChange(of: sourceState) { _, _ in updateButtonState() }
        .navigationDestination(isPresented: Binding(get: { routedMintOffer != nil },
                                                    set: { if !$0 { routedMintOffer = nil } })) {
            if let routedMintOffer {
                QuoteOfferMintView(offer: routedMintOffer)
            }
        }
    }

    /// Routes inline scanner results: BOLT11 invoices feed the invoice source,
    /// melt offers feed the offer source, and mint offers push the offer-mint
    /// flow — a teller hands out a single QR and the wallet must do the right
    /// thing for either operation.
    private func handleInput(_ input: InputView.Result) {
        switch input.type {
        case .quoteOffer:
            do {
                let offer = try CashuSwift.QuoteOffer(encodedOffer: input.payload)
                withAnimation {
                    if offer.operation == .melt {
                        paymentInput = .quoteOffer(offer)
                    } else {
                        routedMintOffer = offer
                    }
                }
            } catch {
                logger.error("could not decode quote offer: \(error)")
                displayAlert(alert: AlertDetail(title: String(localized: "Invalid Quote Offer"),
                                                description: error.localizedDescription))
            }
        default:
            withAnimation {
                paymentInput = .bolt11Invoice(input.payload)
            }
        }
    }

    /// Offer melts execute asynchronously and get the teller-facing payment
    /// code UI. Detected via the concrete quote type so resume mode (where
    /// only the stored events exist) is covered too.
    private var isOfferMelt: Bool {
        if case .quoteOffer = paymentInput { return true }
        return pendingMeltEvents.first?.storedMeltQuote is CashuSwift.Generic.MeltQuote
    }

    // MARK: - Resume mode summary

    /// Shown when the view is opened from a pending event row. Mirrors the
    /// fresh-flow source view visually but is read-only — the action goes
    /// straight to "Check Payment State".
    private var pendingMeltSummaryView: some View {
        List {
            if let offerQuote = pendingMeltEvents.first?.storedMeltQuote as? CashuSwift.Generic.MeltQuote {
                // Offer melt: the (secret) quote ID doubles as the wallet's
                // proof that it initiated the payment. The short code is the
                // last 6 characters of the quote ID, uppercased — the teller
                // compares it against their terminal before handing out cash.
                paymentCodeSection(for: offerQuote)
            } else if let invoiceString = pendingMeltEvents.first?.bolt11MeltQuote?.request {
                Section {
                    Text(invoiceString)
                        .monospaced()
                    HStack {
                        Text("Amount: ")
                        Spacer()
                        AmountView(amount: pendingMeltEvents.compactMap { $0.amount }.reduce(0, +),
                                   unit: pendingMeltEvents.first?.currencyUnit ?? .sat)
                            .monospaced()
                    }
                    .foregroundStyle(.secondary)
                } header: {
                    Text("BOLT11 INVOICE")
                }
            } else if let quoteID = pendingMeltEvents.first?.storedMeltQuote?.quote {
                // Older melts may not carry a payment request.
                Section {
                    Text(quoteID)
                        .monospaced()
                } header: {
                    Text("QUOTE ID")
                }
            }

            Section {
                ForEach(pendingMeltEvents) { event in
                    if let mint = event.mints?.first {
                        VStack(alignment: .leading) {
                            HStack {
                                Text(mint.displayName)
                                Spacer()
                                if let q = event.storedMeltQuote {
                                    AmountView(amount: q.amount, unit: event.currencyUnit)
                                        .monospaced()
                                }
                            }
                            if let q = event.storedMeltQuote {
                                HStack(spacing: 4) {
                                    Text("Fee:")
                                    AmountView(amount: QuoteExecutor.feeReserve(of: q), unit: event.currencyUnit, showUnit: false)
                                    Spacer()
                                }
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            }
                        }
                    }
                }
            } header: {
                Text(pendingMeltEvents.count > 1 ? "Pending Payment Parts" : "Pending Payment")
            }

            Spacer(minLength: 50)
                .listRowBackground(Color.clear)
        }
        .lineLimit(1)
    }

    private func paymentCodeSection(for quote: CashuSwift.Generic.MeltQuote) -> some View {
        Section {
            VStack(alignment: .center, spacing: 10) {
                Text(QuoteOfferTools.paymentCode(forQuoteID: quote.quote))
                    .font(.system(size: 52, weight: .bold, design: .monospaced))
                    .frame(maxWidth: .infinity)
                if offerMeltPaid {
                    Label(String(localized: "Payment complete"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                } else {
                    Text("Show this code to the teller")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ProgressView()
                        Text("Waiting for the payment to complete...")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
            CopyableRow(label: String(localized: "Quote ID"), value: quote.quote)
        } header: {
            Text("PAYMENT CODE")
        } footer: {
            Text("The teller verifies this code against their terminal before paying out.")
        }
    }

    // MARK: - Button orchestration

    private func updateButtonState() {
        if offerMeltPaid {
            buttonState = .idle(String(localized: "Done"), action: { dismissToRoot() })
            return
        }

        if !pendingMeltEvents.isEmpty {
            buttonState = .idle(String(localized: "Check Payment State"),
                                action: { checkMeltState(for: pendingMeltEvents) })
            return
        }

        switch sourceState {
        case .awaitingInput, .insufficientBalance, .error:
            buttonState = .idle(String(localized: "Pay"))
        case .loading:
            buttonState = .loading()
        case .ready:
            buttonState = .idle(String(localized: "Pay"), action: { executeMelt() })
        }
    }

    // MARK: - Execution

    /// Take the bundles the source has produced, allocate proofs and blank
    /// outputs, persist a pending event per bundle, then kick off the
    /// `CashuSwift.Bolt11.melt` task group.
    private func executeMelt() {
        guard case .ready(let bundles, _) = sourceState, let activeWallet else { return }

        buttonState = .loading()

        let groupingID = bundles.count > 1 ? UUID() : nil
        let disc = bundles.count > 1
            ? String(localized: "Pending Payment Part")
            : String(localized: "Pending Payment")

        var events = [Event]()
        for bundle in bundles {
            let mint = bundle.mint
            let quote = bundle.quote
            let unit = Unit(code: quote.unit)

            guard let requiredAmount = try? quote.requiredInputAmount(inputFee: 0) else {
                displayAlert(alert: AlertDetail(title: String(localized: "Quote Error"),
                                                description: String(localized: "The quote from mint \(mint.displayName) does not determine the amount it requires.")))
                updateButtonState()
                return
            }

            guard let proofs = mint.select(amount: requiredAmount,
                                           unit: unit) else {
                displayAlert(alert: AlertDetail(title: String(localized: "Proof Selection Error"),
                                                description: String(localized: "The wallet was not able to pick ecash proofs from mint \(mint.displayName).")))
                updateButtonState()
                return
            }

            let event = Event.pendingMeltEvent(unit: unit,
                                               shortDescription: disc,
                                               wallet: activeWallet,
                                               quote: quote,
                                               amount: quote.amount,
                                               expiration: quote.expiry.map({ Date(timeIntervalSince1970: TimeInterval($0)) }),
                                               mints: [mint],
                                               proofs: proofs.selected,
                                               groupingID: groupingID)

            do {
                let blankOutputs = try CashuSwift.generateBlankOutputs(quote: quote,
                                                                       proofs: proofs.selected,
                                                                       mint: mint,
                                                                       unit: quote.unit,
                                                                       seed: activeWallet.seed)
                if let keysetID = blankOutputs.outputs.first?.id, blankOutputs.outputs.count > 0 {
                    mint.increaseDerivationCounterForKeysetWithID(keysetID, by: blankOutputs.outputs.count)
                } else {
                    logger.error("\(blankOutputs.outputs.count) blank outputs where created but no keyset ID could be determined for counter increase.")
                }

                event.blankOutputs = BlankOutputSet(tuple: blankOutputs)
            } catch {
                logger.error("failed to create blank outputs for melt operation on mint \(mint.url) due to error \(error)")
            }

            events.append(event)
            proofs.selected.setState(.pending)
        }

        pendingMeltEvents = events
        events.forEach({ modelContext.insert($0) })
        try? modelContext.save()

        runMelt(with: events)
    }

    private func runMelt(with events: [Event]) {

        let taskGroupInputs: [MeltTaskInput] = events.compactMap { event in
            let blankOutputs = event.blankOutputs.flatMap { set in
                !set.outputs.isEmpty ? set.tuple() : nil
            }
            guard let mint = event.mints?.first,
                  let proofs = event.proofs,
                  let quote = event.storedMeltQuote else {
                return nil
            }
            return MeltTaskInput(mint: CashuSwift.Mint(mint),
                                proofs: proofs.sendable(),
                                quote: quote,
                                blankOutputs: blankOutputs)
        }

        guard taskGroupInputs.count == events.count else {
            displayAlert(alert: AlertDetail(title: String(localized: "Missing Payment Data"),
                                            description: String(localized: "One or more parts of this payment are missing their quote or proof data and cannot be executed.")))
            updateButtonState()
            return
        }

        Task {
            do {
                try await withThrowingTaskGroup(of: MeltTaskResult.self) { group in

                    for input in taskGroupInputs {
                        group.addTask {
                            let outcome = try await QuoteExecutor.melt(input.quote,
                                                                       from: input.mint,
                                                                       proofs: input.proofs,
                                                                       blankOutputs: input.blankOutputs)
                            return MeltTaskResult(mint: input.mint, quote: outcome.quote, change: outcome.change)
                        }
                    }

                    var results: [MeltTaskResult] = []

                    for try await result in group {
                        results.append(result)
                    }

                    await MainActor.run {
                        if isOfferMelt, results.contains(where: { $0.quote.state == .pending }) {
                            // Offer melts are asynchronous per NUT-XX: the mint
                            // answers PENDING after validating the request and the
                            // wallet monitors the quote until the payment completes.
                            startOfferMeltPolling()
                            updateButtonState()
                        } else {
                            handleSuccess(with: results)
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    logger.error("Unable to complete melt operation due to error \(error)")
                    displayAlert(alert: AlertDetail(with: error))
                    updateButtonState()
                }
            }
        }
    }

    private func checkMeltState(for events: [Event]) {
        var taskInputs = [MeltTaskInput]()
        for event in events {
            guard let mint = event.mints?.first,
                  let proofs = event.proofs,
                  let quote = event.storedMeltQuote else {
                displayAlert(alert: AlertDetail(title: String(localized: "Missing Payment Data"),
                                                description: String(localized: "This pending payment is missing its quote or proof data, so its state cannot be checked.")))
                return
            }

            // An empty blank-output set is a legitimate state (the melt had no overpayment
            // beyond the fee reserve), so map it to nil — exactly as runMelt does — instead
            // of handing meltState an empty tuple it can't derive a keyset id from.
            let blankOutputs = event.blankOutputs.flatMap { $0.outputs.isEmpty ? nil : $0.tuple() }
            taskInputs.append(MeltTaskInput(mint: CashuSwift.Mint(mint),
                                            proofs: proofs.sendable(),
                                            quote: quote,
                                            blankOutputs: blankOutputs))
        }

        buttonState = .loading()

        var results = [MeltTaskResult]()
        Task {
            do {
                for input in taskInputs {
                    let outcome = try await QuoteExecutor.meltState(input.quote,
                                                                    from: input.mint,
                                                                    blankOutputs: input.blankOutputs)
                    results.append(MeltTaskResult(mint: input.mint,
                                                  quote: outcome.quote,
                                                  change: outcome.change))
                }

                await MainActor.run {
                    if results.allSatisfy({ $0.quote.state == .paid }) {
                        handleSuccess(with: results)
                    } else if results.allSatisfy({ $0.quote.state == .pending }) {
                        displayAlert(alert: AlertDetail(title: String(localized: "Payment Pending ⏳"),
                                                        description: String(localized: "This payment is still pending. Please check again later to make sure the lightning payment was successful.")))
                        updateButtonState()
                    } else if results.allSatisfy({ $0.quote.state == .unpaid }) {
                        let primary = AlertButton(title: String(localized: "Retry"),
                                                  action: { runMelt(with: events) })
                        let secondary = AlertButton(title: String(localized: "Remove Payment"),
                                                    role: .destructive,
                                                    action: { removePendingPayment(events: events) })
                        displayAlert(alert: AlertDetail(title: String(localized: "Unpaid ⚠"),
                                                        description: String(localized: "This payment did not go through and is marked \"unpaid\" with the mint. Would you like to try again?"),
                                                        primaryButton: primary,
                                                        secondaryButton: secondary))
                        updateButtonState()
                    } else if results.contains(where: { $0.quote.state == .pending }) {
                        displayAlert(alert: AlertDetail(title: String(localized: "Payment Pending ⏳"),
                                                        description: String(localized: "One or more parts of this payment are still pending. Please check again later to make sure the lightning payment was successful.")))
                        updateButtonState()
                    } else if results.contains(where: { $0.quote.state == .unpaid }) {
                        let primary = AlertButton(title: String(localized: "Retry"),
                                                  action: { runMelt(with: events) })
                        let secondary = AlertButton(title: String(localized: "Remove Payment"),
                                                    role: .destructive,
                                                    action: { removePendingPayment(events: events) })
                        displayAlert(alert: AlertDetail(title: String(localized: "Unpaid ⚠"),
                                                        description: String(localized: "This payment did not go through and one or more parts are marked \"unpaid\". Would you like to try again?"),
                                                        primaryButton: primary,
                                                        secondaryButton: secondary))
                        updateButtonState()
                    }
                }
            } catch {
                await MainActor.run {
                    logger.error("unable to check one or more quote states due to error: \(error)")
                    displayAlert(alert: AlertDetail(with: error))
                    updateButtonState()
                }
            }
        }
    }

    // MARK: - Offer melt PENDING monitoring

    /// Auto-polls the melt quote state every few seconds while an offer melt
    /// is PENDING. Silent by design — unlike the manual "Check Payment State"
    /// button it never raises alerts, it just waits for PAID.
    private func startOfferMeltPolling() {
        guard pollingTimer == nil || pollingTimer?.isValid == false else { return }
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true, block: { _ in
            Task { @MainActor in
                pollOfferMeltState()
            }
        })
    }

    @MainActor
    private func pollOfferMeltState() {
        guard !isPollingMeltState, !offerMeltPaid, !pendingMeltEvents.isEmpty else { return }

        var taskInputs = [MeltTaskInput]()
        for event in pendingMeltEvents {
            guard let mint = event.mints?.first,
                  let proofs = event.proofs,
                  let quote = event.storedMeltQuote else {
                pollingTimer?.invalidate()
                return
            }
            let blankOutputs = event.blankOutputs.flatMap { $0.outputs.isEmpty ? nil : $0.tuple() }
            taskInputs.append(MeltTaskInput(mint: CashuSwift.Mint(mint),
                                            proofs: proofs.sendable(),
                                            quote: quote,
                                            blankOutputs: blankOutputs))
        }

        isPollingMeltState = true
        Task {
            defer { isPollingMeltState = false }
            do {
                var results = [MeltTaskResult]()
                for input in taskInputs {
                    let outcome = try await QuoteExecutor.meltState(input.quote,
                                                                    from: input.mint,
                                                                    blankOutputs: input.blankOutputs)
                    results.append(MeltTaskResult(mint: input.mint,
                                                  quote: outcome.quote,
                                                  change: outcome.change))
                }
                await MainActor.run {
                    if results.allSatisfy({ $0.quote.state == .paid }) {
                        handleSuccess(with: results)
                    }
                    // Still pending: keep polling silently.
                }
            } catch {
                // Transient poll errors are expected (network); keep the timer running.
                logger.warning("offer melt state poll failed with error: \(error)")
            }
        }
    }

    private func handleSuccess(with results: [MeltTaskResult]) {
        guard let activeWallet else {
            return
        }

        pollingTimer?.invalidate()

        for event in pendingMeltEvents {
            event.proofs?.setState(.spent)
            event.visible = false
        }

        let groupingID = results.count > 1 ? UUID() : nil

        var events = [Event]()
        for result in results {
            // Search ALL of the wallet's mints — an offer melt may spend from a
            // mint that was auto-added hidden when the offer was claimed.
            guard let mint = activeWallet.mints.first(where: { $0.matches(result.mint) }) else {
                // TODO: show error saving change
                return
            }

            let internalChange = try? mint.addProofs(result.change,
                                                     to: modelContext)

            events.append(Event.meltEvent(unit: Unit(code: result.quote.unit),
                                          shortDescription: "Payment",
                                          wallet: activeWallet,
                                          amount: result.quote.amount,
                                          longDescription: "",
                                          mints: [mint],
                                          change: internalChange,
                                          preImage: QuoteExecutor.paymentPreimage(of: result.quote),
                                          groupingID: groupingID,
                                          meltQuote: result.quote))
        }

        events.forEach({ modelContext.insert($0) })

        try? modelContext.save()

        buttonState = .success(String(localized: "Paid!"))

        if isOfferMelt {
            // Keep the payment code on screen: the teller compares it against
            // their terminal before handing out cash, so the view must not
            // dismiss itself on success.
            withAnimation { offerMeltPaid = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                updateButtonState()
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                dismissToRoot()
            }
        }
    }

    private func removePendingPayment(events: [Event]) {
        for e in events {
            e.proofs?.setState(.valid)
            e.visible = false
        }
        dismissToRoot()
    }

    private func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}
