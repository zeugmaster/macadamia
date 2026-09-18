import SwiftUI
import SwiftData
import CashuSwift

/// Hosts a BOLT11 or BOLT12 quote source, then executes the resulting
/// `MeltQuoteBundle`s — proof selection, blank outputs, persistent event
/// bookkeeping, and the actual method-specific melt calls. Also handles
/// resume mode for pending payments and the post-execute "check state"
/// loop. Everything below the source is intentionally payment-method
/// agnostic so the source can be swapped without touching execution.
struct MeltView: View {

    struct MeltTaskInput {
        let mint: CashuSwift.Mint
        let proofs: [CashuSwift.Proof]
        let quote: LightningMeltQuote
        let blankOutputs: (outputs: [CashuSwift.Output], blindingFactors: [String], secrets: [String])?
    }

    struct MeltTaskResult {
        let mint: CashuSwift.Mint
        let quote: LightningMeltQuote
        let change: [CashuSwift.Proof]
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismissToRoot) private var dismissToRoot

    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]

    private let initialInvoice: String?
    private let initialOffer: String?
    private let bolt12QuoteFetcher: BOLT12QuoteLoader.FetchQuote
    @State private var amountConfirmed = false
    @State private var pendingMeltEvents: [Event]

    // What the source view publishes upward. Drives the action button and
    // gates execution.
    @State private var sourceState: MeltSourceState = .awaitingInput

    @State private var buttonState = ActionButtonState.idle("...")
    @State private var isProcessing = false

    @State private var showAlert = false
    @State private var currentAlert: AlertDetail?

    private var activeWallet: Wallet? {
        wallets.first
    }

    private var actionButtonDisabled: Bool {
        if isProcessing { return true }
        if !pendingMeltEvents.isEmpty { return false }
        if case .ready = sourceState { return false }
        if case .needsAmount(let canContinue) = sourceState { return !canContinue }
        return true
    }

    init(events: [Event]? = nil, invoice: String? = nil, offer: String? = nil,
         bolt12QuoteFetcher: @escaping BOLT12QuoteLoader.FetchQuote = BOLT12QuoteLoader.fetchFromMint) {
        self.bolt12QuoteFetcher = bolt12QuoteFetcher
        if let events {
            _pendingMeltEvents = State(initialValue: events)
            self.initialInvoice = nil
            self.initialOffer = nil
        } else {
            _pendingMeltEvents = State(initialValue: [])
            self.initialInvoice = invoice
            self.initialOffer = offer
        }
    }

    var body: some View {
        ZStack {
            if !pendingMeltEvents.isEmpty {
                pendingMeltSummaryView
            } else if let initialOffer {
                BOLT12MeltQuoteSource(offer: initialOffer, amountConfirmed: $amountConfirmed,
                                      state: $sourceState, fetchQuote: bolt12QuoteFetcher)
            } else {
                BOLT11MeltQuoteSource(initialInvoice: initialInvoice,
                                      state: $sourceState)
            }
            VStack {
                Spacer()
                ActionButton(state: $buttonState)
                    .actionDisabled(actionButtonDisabled)
            }
        }
        .alertView(isPresented: $showAlert, currentAlert: currentAlert)
        .onAppear { updateButtonState() }
        .onChange(of: sourceState) { _, _ in updateButtonState() }
    }

    // MARK: - Resume mode summary

    /// Shown when the view is opened from a pending event row. Mirrors the
    /// fresh-flow source view visually but is read-only — the action goes
    /// straight to "Check Payment State".
    private var pendingMeltSummaryView: some View {
        List {
            if let invoiceString = pendingMeltEvents.first?.lightningMeltQuote?.request {
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
                    Text(pendingMeltEvents.first?.lightningMeltQuote?.requestLabel ?? "")
                }
            }

            Section {
                ForEach(pendingMeltEvents) { event in
                    if let mint = event.mints?.first {
                        VStack(alignment: .leading) {
                            HStack {
                                Text(mint.displayName)
                                Spacer()
                                if let q = event.lightningMeltQuote {
                                    AmountView(amount: q.amount, unit: event.currencyUnit)
                                        .monospaced()
                                }
                            }
                            if let q = event.lightningMeltQuote {
                                HStack(spacing: 4) {
                                    Text("Fee:")
                                    AmountView(amount: q.feeReserve, unit: event.currencyUnit, showUnit: false)
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

    // MARK: - Button orchestration

    private func updateButtonState() {
        guard !isProcessing else { return }
        if !pendingMeltEvents.isEmpty {
            buttonState = .idle(String(localized: "Check Payment State"),
                                action: { checkMeltState(for: pendingMeltEvents) })
            return
        }

        switch sourceState {
        case .needsAmount:
            buttonState = .idle(String(localized: "Next"), action: { amountConfirmed = true })
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
    /// method-specific melt task group.
    private func executeMelt() {
        guard !isProcessing, pendingMeltEvents.isEmpty, case .ready(let bundles, _) = sourceState, let activeWallet else { return }

        do {
            try LightningMeltQuote.validatePayment(bundles.map(\.quote))
        } catch {
            displayAlert(alert: AlertDetail(with: error))
            return
        }
        buttonState = .loading()

        // Select every part before reserving any proofs.
        var selections = [[Proof]]()
        for bundle in bundles {
            guard let required = try? bundle.quote.requiredInputAmount(inputFee: 0),
                  let selection = bundle.mint.select(amount: required, unit: .sat) else {
                displayAlert(alert: AlertDetail(title: String(localized: "Insufficient Balance"),
                                                description: String(localized: "The selected mint cannot cover the payment and fees.")))
                updateButtonState()
                return
            }
            selections.append(selection.selected)
        }

        let groupingID = bundles.count > 1 ? UUID() : nil
        let disc = bundles.count > 1
            ? String(localized: "Pending Payment Part")
            : String(localized: "Pending Payment")

        var events = [Event]()
        for (bundle, proofs) in zip(bundles, selections) {
            let mint = bundle.mint
            let quote = bundle.quote

            let event = Event(date: Date(), unit: .sat, shortDescription: disc,
                              visible: true, kind: .pendingMelt, wallet: activeWallet,
                              amount: quote.amount,
                              expiration: quote.expiry.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                              proofs: proofs, mints: [mint], groupingID: groupingID)

            event.lightningMeltQuote = quote

            do {
                let blankOutputs = try CashuSwift.generateBlankOutputs(quote: quote,
                                                                       proofs: proofs,
                                                                       mint: mint,
                                                                       unit: Unit.sat.currencyCode,
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
        }

        events.forEach {
            modelContext.insert($0)
            $0.proofs?.setState(.pending)
        }
        do {
            try modelContext.save()
        } catch {
            for event in events {
                event.proofs?.setState(.valid)
                modelContext.delete(event)
            }
            displayAlert(alert: AlertDetail(with: error))
            updateButtonState()
            return
        }
        pendingMeltEvents = events
        runMelt(with: events)
    }

    private func runMelt(with events: [Event]) {
        guard !isProcessing else { return }

        var taskGroupInputs = [MeltTaskInput]()
        for event in events {
            guard let mint = event.mints?.first, let proofs = event.proofs,
                  let quote = event.lightningMeltQuote else {
                displayAlert(alert: AlertDetail(title: String(localized: "Payment Unavailable"),
                                                description: String(localized: "The saved payment is missing its quote or proofs.")))
                updateButtonState()
                return
            }
            taskGroupInputs.append(MeltTaskInput(mint: CashuSwift.Mint(mint), proofs: proofs.sendable(),
                                                quote: quote,
                                                blankOutputs: event.blankOutputs.flatMap { $0.outputs.isEmpty ? nil : $0.tuple() }))
        }
        do {
            try LightningMeltQuote.validatePayment(taskGroupInputs.map(\.quote))
        } catch {
            displayAlert(alert: AlertDetail(with: error))
            updateButtonState()
            return
        }
        isProcessing = true
        buttonState = .loading()

        Task {
            do {
                try await withThrowingTaskGroup(of: MeltTaskResult.self) { group in

                    for input in taskGroupInputs {
                        group.addTask {
                            let meltResult = try await input.quote.melt(from: input.mint,
                                                                         proofs: input.proofs,
                                                                         blankOutputs: input.blankOutputs)
                            return MeltTaskResult(mint: input.mint, quote: meltResult.quote, change: meltResult.change)
                        }
                    }

                    var results: [MeltTaskResult] = []

                    for try await result in group {
                        results.append(result)
                    }

                    await MainActor.run {
                        isProcessing = false
                        if results.allSatisfy({ $0.quote.state == .paid }) {
                            handleSuccess(with: results)
                        } else {
                            updateButtonState()
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    logger.error("Unable to complete melt operation due to error \(error)")
                    displayAlert(alert: AlertDetail(with: error))
                    updateButtonState()
                }
            }
        }
    }

    private func checkMeltState(for events: [Event]) {
        guard !isProcessing, !events.isEmpty else { return }
        var taskInputs = [MeltTaskInput]()
        for event in events {
            guard let mint = event.mints?.first,
                  let proofs = event.proofs,
                  let quote = event.lightningMeltQuote else {
                displayAlert(alert: AlertDetail(title: String(localized: "Payment Unavailable"),
                                                description: String(localized: "The saved payment is missing its quote or proofs.")))
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

        isProcessing = true
        buttonState = .loading()

        var results = [MeltTaskResult]()
        Task {
            do {
                for input in taskInputs {
                    let result = try await input.quote.checkState(from: input.mint,
                                                                  blankOutputs: input.blankOutputs)
                    results.append(MeltTaskResult(mint: input.mint,
                                                  quote: result.quote,
                                                  change: result.change))
                }

                await MainActor.run {
                    isProcessing = false
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
                    } else {
                        displayAlert(alert: AlertDetail(title: String(localized: "Payment State Unknown"),
                                                        description: String(localized: "The mint did not return a recognized payment state. Please check again later.")))
                        updateButtonState()
                    }
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    logger.error("unable to check one or more quote states due to error: \(error)")
                    displayAlert(alert: AlertDetail(with: error))
                    updateButtonState()
                }
            }
        }
    }

    private func handleSuccess(with results: [MeltTaskResult]) {
        guard let activeWallet else {
            return
        }

        for event in pendingMeltEvents {
            event.proofs?.setState(.spent)
            event.visible = false
        }

        let groupingID = results.count > 1 ? UUID() : nil

        var events = [Event]()
        for result in results {
            guard let mint = pendingMeltEvents.compactMap({ $0.mints?.first }).first(where: { $0.matches(result.mint) }) else {
                // TODO: show error saving change
                return
            }

            let internalChange = try? mint.addProofs(result.change,
                                                     to: modelContext)

            let completed = Event.meltEvent(unit: .sat,
                                          shortDescription: "Payment",
                                          wallet: activeWallet,
                                          amount: result.quote.amount,
                                          longDescription: "",
                                          mints: [mint],
                                          change: internalChange,
                                          preImage: result.quote.paymentPreimage,
                                          groupingID: groupingID,
                                          meltQuote: nil)
            completed.lightningMeltQuote = result.quote
            events.append(completed)
        }

        events.forEach({ modelContext.insert($0) })

        try? modelContext.save()

        buttonState = .success(String(localized: "Paid!"))

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            dismissToRoot()
        }
    }

    private func removePendingPayment(events: [Event]) {
        for e in events {
            e.proofs?.setState(.valid)
            e.visible = false
        }
        try? modelContext.save()
        dismissToRoot()
    }

    private func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}

/// Self-contained withdrawal flow for non-Lightning NUT-05 melt methods (e.g. a
/// custom "branch" method): amount + optional memo -> generic melt quote ->
/// execute with prefer_async -> poll until the operator settles or fails the
/// payout. Single mint, single unit, no MPP. Lightning payments stay in
/// `MeltView`.
struct GenericMeltView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismissToRoot) private var dismissToRoot
    @EnvironmentObject private var appState: AppState

    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]

    @State private var amount: Int = 0
    @State private var memo: String = ""
    @State private var selectedMint: Mint?
    @State private var selectedOption: PaymentOption?
    @State private var quote: CashuSwift.Generic.MeltQuote?
    @State private var pendingMeltEvent: Event?
    @State private var showDetails = false

    @State private var buttonState = ActionButtonState.idle("...")
    @State private var pollingTimer: Timer?
    @State private var isCheckingState = false

    @State private var showAlert = false
    @State private var currentAlert: AlertDetail?

    private var activeWallet: Wallet? {
        wallets.first
    }

    init(pendingEvent: Event? = nil) {
        _pendingMeltEvent = State(initialValue: pendingEvent)
        if let pendingEvent, let quote = pendingEvent.genericMeltQuote {
            _quote = State(initialValue: quote)
            _amount = State(initialValue: quote.amount)
            _memo = State(initialValue: pendingEvent.memo ?? "")
            if let mint = pendingEvent.mints?.first {
                _selectedMint = State(initialValue: mint)
                _selectedOption = State(initialValue: PaymentOption(mintID: mint.mintID,
                                                                    direction: .withdraw,
                                                                    unit: Unit(code: quote.unit),
                                                                    method: quote.method))
            }
        }
    }

    var body: some View {
        ZStack {
            Form {
                Section {
                    NumericalInputView(output: $amount,
                                       baseUnit: selectedOption?.unit ?? .sat,
                                       exchangeRates: selectedOption?.unit.kind == .other ? nil : appState.exchangeRates,
                                       onReturn: getQuote)
                    MintPicker(label: String(localized: "Mint"), selectedMint: $selectedMint)
                    PaymentOptionPicker(direction: .withdraw,
                                        label: String(localized: "Method"),
                                        selectedMint: $selectedMint,
                                        selectedOption: $selectedOption,
                                        excludedMethods: [.bolt11, .bolt12],
                                        hidesWhenSingleOption: false)
                    TextField(String(localized: "Memo (optional)"), text: $memo)
                        .autocorrectionDisabled()
                        .onChange(of: memo) { _, newValue in
                            if newValue.count > 1024 { memo = String(newValue.prefix(1024)) }
                        }
                }
                .disabled(quote != nil || pendingMeltEvent != nil)

                if let quote {
                    Section {
                        HStack {
                            Text("Amount: ")
                            Spacer()
                            AmountView(amount: quote.amount, unit: Unit(code: quote.unit))
                                .monospaced()
                        }
                        if quote.feeReserve > 0 {
                            HStack {
                                Text("Fee:")
                                Spacer()
                                AmountView(amount: quote.feeReserve, unit: Unit(code: quote.unit))
                                    .monospaced()
                            }
                            .foregroundStyle(.secondary)
                        }
                        if let expiry = quote.expiry {
                            HStack {
                                Text("Expires at: ")
                                Spacer()
                                Text(Date(timeIntervalSince1970: TimeInterval(expiry)).formatted())
                            }
                            .foregroundStyle(.secondary)
                        }
                    }

                    if pendingMeltEvent != nil {
                        Section {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("Waiting for the mint operator to confirm the payout. This can take a few minutes.")
                                    .foregroundStyle(.secondary)
                                    .font(.callout)
                            }
                        }
                    }

                    Section {
                        Button {
                            withAnimation {
                                showDetails.toggle()
                            }
                        } label: {
                            HStack {
                                if showDetails {
                                    Text("Hide details")
                                } else {
                                    Text("Show details")
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                                    .font(.footnote)
                                    .rotationEffect(.degrees(showDetails ? 90 : 0))
                            }
                            .opacity(0.8)
                        }

                        if showDetails {
                            CopyableRow(label: String(localized: "Quote ID"), value: quote.quote)
                        }
                    }
                }

                Spacer(minLength: 50)
                    .listRowBackground(Color.clear)
            }
            VStack {
                Spacer()
                ActionButton(state: $buttonState)
                    .actionDisabled(actionButtonDisabled)
            }
        }
        .navigationTitle("Withdrawal")
        .alertView(isPresented: $showAlert, currentAlert: currentAlert)
        .onAppear {
            updateButtonState()
            if pendingMeltEvent != nil {
                startPolling()
            }
        }
        .onDisappear {
            pollingTimer?.invalidate()
        }
    }

    // MARK: - Button orchestration

    private var actionButtonDisabled: Bool {
        if pendingMeltEvent != nil || quote != nil { return false }
        guard amount > 0, let selectedMint, let selectedOption else { return true }
        if let minAmount = selectedOption.minAmount, amount < minAmount { return true }
        if let maxAmount = selectedOption.maxAmount, amount > maxAmount { return true }
        return selectedMint.balance(for: selectedOption.unit) < amount
    }

    private func updateButtonState() {
        if pendingMeltEvent != nil {
            buttonState = .idle(String(localized: "Check Payment State"), action: { checkState(manual: true) })
        } else if quote != nil {
            buttonState = .idle(String(localized: "Withdraw"), action: { executeMelt() })
        } else {
            buttonState = .idle(String(localized: "Get Quote"), action: { getQuote() })
        }
    }

    // MARK: - Quote

    private func getQuote() {
        guard let selectedMint, let selectedOption, amount > 0, quote == nil else { return }

        buttonState = .loading()

        let sendableMint = CashuSwift.Mint(selectedMint)
        let methodID = selectedOption.method
        // cdk requires `method` repeated inside the body and the payout declared
        // as a flattened `amount` field; harmless for mints that ignore extras.
        let quoteRequest = CashuSwift.Generic.MeltQuoteRequest(
            method: methodID,
            unit: selectedOption.unitCode,
            request: memo,
            extra: ["method": .string(methodID.rawValue),
                    "amount": .integer(Int64(amount))]
        )
        let requestedAmount = amount

        Task {
            do {
                let freshQuote = try await CashuSwift.Generic.requestMeltQuote(quoteRequest, from: sendableMint)
                await MainActor.run {
                    guard freshQuote.amount == requestedAmount else {
                        displayAlert(alert: AlertDetail(title: String(localized: "Amount Mismatch"),
                                                        description: String(localized: "The mint's quote amount does not match the requested amount.")))
                        updateButtonState()
                        return
                    }
                    self.quote = freshQuote
                    updateButtonState()
                }
            } catch {
                await MainActor.run {
                    displayAlert(alert: AlertDetail(with: error))
                    buttonState = .fail()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        updateButtonState()
                    }
                }
            }
        }
    }

    // MARK: - Execution

    private func executeMelt() {
        guard let quote, let selectedMint, let selectedOption, let activeWallet,
              pendingMeltEvent == nil else { return }

        guard let selection = selectedMint.select(amount: quote.amount + quote.feeReserve,
                                                  unit: selectedOption.unit) else {
            displayAlert(alert: AlertDetail(title: String(localized: "Proof Selection Error"),
                                            description: String(localized: "The wallet was not able to pick ecash proofs from mint \(selectedMint.displayName).")))
            return
        }

        buttonState = .loading()

        let event = Event.pendingMeltEvent(unit: selectedOption.unit,
                                           shortDescription: String(localized: "Pending Withdrawal"),
                                           wallet: activeWallet,
                                           genericQuote: quote,
                                           amount: quote.amount,
                                           expiration: quote.expiry.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                                           mints: [selectedMint],
                                           proofs: selection.selected,
                                           memo: memo.isEmpty ? nil : memo)

        do {
            let blankOutputs = try CashuSwift.generateBlankOutputs(quote: quote,
                                                                   proofs: selection.selected,
                                                                   mint: selectedMint,
                                                                   unit: quote.unit,
                                                                   seed: activeWallet.seed)
            // An empty set is legitimate (no overpayment beyond the fee reserve).
            if !blankOutputs.outputs.isEmpty, let keysetID = blankOutputs.outputs.first?.id {
                selectedMint.increaseDerivationCounterForKeysetWithID(keysetID, by: blankOutputs.outputs.count)
                event.blankOutputs = BlankOutputSet(tuple: blankOutputs)
            }
        } catch {
            logger.error("failed to create blank outputs for generic melt on mint \(selectedMint.url) due to error \(error)")
        }

        modelContext.insert(event)
        try? modelContext.save()
        selection.selected.setState(.pending)
        pendingMeltEvent = event

        runMelt(event: event)
    }

    private func runMelt(event: Event) {
        guard let selectedMint, let quote = event.genericMeltQuote else { return }

        buttonState = .loading()

        let sendableMint = CashuSwift.Mint(selectedMint)
        let sendableProofs = event.proofs?.sendable() ?? []
        let blankOutputs = event.blankOutputs.flatMap { $0.outputs.isEmpty ? nil : $0.tuple() }

        Task {
            do {
                let result = try await CashuSwift.Generic.melt(quote: quote,
                                                               from: sendableMint,
                                                               proofs: sendableProofs,
                                                               blankOutputs: blankOutputs,
                                                               preferAsync: true)
                await MainActor.run {
                    if result.quote.state == .paid {
                        finalize(result: result)
                    } else if result.quote.isFailed {
                        fail()
                    } else {
                        startPolling()
                    }
                }
            } catch CashuError.quoteIsPending {
                // Error code 20005: the operator has not settled the payout inside
                // the mint's synchronous window — not a failure, keep polling.
                await MainActor.run { startPolling() }
            } catch {
                await MainActor.run {
                    displayAlert(alert: AlertDetail(with: error))
                    updateButtonState()
                }
            }
        }
    }

    // MARK: - Polling

    private func startPolling() {
        updateButtonState()
        guard pollingTimer?.isValid != true else { return }
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true, block: { _ in
            Task { @MainActor in
                checkState()
            }
        })
    }

    private func checkState(manual: Bool = false) {
        guard let pendingMeltEvent, let quote = pendingMeltEvent.genericMeltQuote,
              let mint = pendingMeltEvent.mints?.first else { return }
        if isCheckingState { return }
        isCheckingState = true

        let sendableMint = CashuSwift.Mint(mint)
        let blankOutputs = pendingMeltEvent.blankOutputs.flatMap { $0.outputs.isEmpty ? nil : $0.tuple() }

        Task {
            do {
                let result = try await CashuSwift.Generic.meltState(quote.quote,
                                                                    method: quote.method,
                                                                    from: sendableMint,
                                                                    blankOutputs: blankOutputs)
                await MainActor.run {
                    isCheckingState = false
                    switch result.quote.state {
                    case .paid:
                        finalize(result: result)
                    case .unpaid:
                        pollingTimer?.invalidate()
                        let primary = AlertButton(title: String(localized: "Retry"),
                                                  action: { runMelt(event: pendingMeltEvent) })
                        let secondary = AlertButton(title: String(localized: "Remove Payment"),
                                                    role: .destructive,
                                                    action: { removePending() })
                        displayAlert(alert: AlertDetail(title: String(localized: "Unpaid ⚠"),
                                                        description: String(localized: "This payment did not go through and is marked \"unpaid\" with the mint. Would you like to try again?"),
                                                        primaryButton: primary,
                                                        secondaryButton: secondary))
                        updateButtonState()
                    case .pending:
                        if manual {
                            displayAlert(alert: AlertDetail(title: String(localized: "Payment Pending ⏳"),
                                                            description: String(localized: "Waiting for the mint operator to confirm the payout. This can take a few minutes.")))
                            updateButtonState()
                        }
                    default:
                        // FAILED and UNKNOWN decode to a nil typed state; the raw
                        // string distinguishes them.
                        if result.quote.isFailed {
                            fail()
                        } else if manual {
                            displayAlert(alert: AlertDetail(title: String(localized: "Withdrawal"),
                                                            description: String(localized: "The state of this withdrawal could not be determined. Please check again later.")))
                            updateButtonState()
                        }
                    }
                }
            } catch CashuError.quoteIsPending {
                await MainActor.run { isCheckingState = false }
            } catch {
                await MainActor.run {
                    isCheckingState = false
                    pollingTimer?.invalidate()
                    displayAlert(alert: AlertDetail(with: error))
                    updateButtonState()
                }
            }
        }
    }

    // MARK: - Settlement

    private func finalize(result: CashuSwift.MeltResult<CashuSwift.Generic.MeltQuote>) {
        guard let activeWallet, let pendingMeltEvent,
              let storedQuote = pendingMeltEvent.genericMeltQuote,
              let mint = pendingMeltEvent.mints?.first else { return }

        pollingTimer?.invalidate()

        pendingMeltEvent.proofs?.setState(.spent)
        pendingMeltEvent.visible = false

        let internalChange = try? mint.addProofs(result.change ?? [], to: modelContext)

        // Melt results come off the wire without a method — re-graft the stored
        // quote's method so the persisted event routes to the generic accessor.
        let finalQuote = result.quote.settingMethod(storedQuote.method)

        let event = Event.meltEvent(unit: pendingMeltEvent.currencyUnit,
                                    shortDescription: String(localized: "Withdrawal"),
                                    wallet: activeWallet,
                                    amount: result.quote.amount,
                                    longDescription: "",
                                    mints: [mint],
                                    change: internalChange,
                                    preImage: result.quote.paymentPreimage,
                                    memo: pendingMeltEvent.memo,
                                    genericQuote: finalQuote)
        modelContext.insert(event)
        try? modelContext.save()

        buttonState = .success(String(localized: "Paid!"))

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            dismissToRoot()
        }
    }

    private func fail() {
        pollingTimer?.invalidate()
        // A FAILED quote means the mint has released the locked inputs.
        pendingMeltEvent?.proofs?.setState(.valid)
        pendingMeltEvent?.visible = false
        try? modelContext.save()
        pendingMeltEvent = nil
        quote = nil
        displayAlert(alert: AlertDetail(title: String(localized: "Withdrawal Failed"),
                                        description: String(localized: "The mint reported this withdrawal as failed. Your ecash has been returned to your balance.")))
        updateButtonState()
    }

    private func removePending() {
        pollingTimer?.invalidate()
        pendingMeltEvent?.proofs?.setState(.valid)
        pendingMeltEvent?.visible = false
        try? modelContext.save()
        dismissToRoot()
    }

    private func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}
