import SwiftUI
import SwiftData
import CashuSwift

// TODO: remove unsafe unwrapping, nicer pending error

/// Hosts a payment-method-specific quote source (currently
/// `BOLT11MeltQuoteSource`), then executes the resulting
/// `MeltQuoteBundle`s — proof selection, blank outputs, persistent event
/// bookkeeping, and the actual `CashuSwift.Bolt11.melt` calls. Also handles
/// resume mode for pending payments and the post-execute "check state"
/// loop. Everything below the source is intentionally payment-method
/// agnostic so the source can be swapped without touching execution.
struct MeltView: View {

    struct MeltTaskInput {
        let mint: CashuSwift.Mint
        let proofs: [CashuSwift.Proof]
        let quote: CashuSwift.Bolt11.MeltQuote
        let blankOutputs: (outputs: [CashuSwift.Output], blindingFactors: [String], secrets: [String])?
    }

    struct MeltTaskResult {
        let mint: CashuSwift.Mint
        let quote: CashuSwift.Bolt11.MeltQuote
        let change: [CashuSwift.Proof]
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissToRoot) private var dismissToRoot

    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]

    private let initialInvoice: String?
    @State private var pendingMeltEvents: [Event]

    // What the source view publishes upward. Drives the action button and
    // gates execution.
    @State private var sourceState: MeltSourceState = .awaitingInput

    @State private var buttonState = ActionButtonState.idle("...")

    @State private var showAlert = false
    @State private var currentAlert: AlertDetail?

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

    init(events: [Event]? = nil, invoice: String? = nil) {
        if let events {
            _pendingMeltEvents = State(initialValue: events)
            self.initialInvoice = nil
        } else {
            _pendingMeltEvents = State(initialValue: [])
            self.initialInvoice = invoice
        }
    }

    var body: some View {
        ZStack {
            if !pendingMeltEvents.isEmpty {
                pendingMeltSummaryView
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
            if let invoiceString = pendingMeltEvents.first?.bolt11MeltQuote?.request {
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
            }

            Section {
                ForEach(pendingMeltEvents) { event in
                    if let mint = event.mints?.first {
                        VStack(alignment: .leading) {
                            HStack {
                                Text(mint.displayName)
                                Spacer()
                                if let q = event.bolt11MeltQuote {
                                    AmountView(amount: q.amount, unit: event.currencyUnit)
                                        .monospaced()
                                }
                            }
                            if let q = event.bolt11MeltQuote {
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

            guard let proofs = mint.select(amount: quote.amount + quote.feeReserve,
                                           unit: .sat) else {
                displayAlert(alert: AlertDetail(title: String(localized: "Proof Selection Error"),
                                                description: String(localized: "The wallet was not able to pick ecash proofs from mint \(mint.displayName).")))
                updateButtonState()
                return
            }

            let event = Event.pendingMeltEvent(unit: .sat,
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
            proofs.selected.setState(.pending)
        }

        pendingMeltEvents = events
        events.forEach({ modelContext.insert($0) })
        try? modelContext.save()

        runMelt(with: events)
    }

    private func runMelt(with events: [Event]) {

        let taskGroupInputs: [MeltTaskInput] = events.map { event in
            let blankOutputs = event.blankOutputs.flatMap { set in
                !set.outputs.isEmpty ? set.tuple() : nil
            }
            return MeltTaskInput(mint: CashuSwift.Mint(event.mints!.first!), // FIXME: unsafe unwrapping
                                proofs: event.proofs!.sendable(),
                                quote: event.bolt11MeltQuote!,
                                blankOutputs: blankOutputs)
        }

        Task {
            do {
                try await withThrowingTaskGroup(of: MeltTaskResult.self) { group in

                    for input in taskGroupInputs {
                        group.addTask {
                            let meltResult = try await CashuSwift.Bolt11.melt(quote: input.quote,
                                                                              from: input.mint,
                                                                              proofs: input.proofs,
                                                                              blankOutputs: input.blankOutputs)
                            return MeltTaskResult(mint: input.mint, quote: meltResult.quote, change: meltResult.change ?? [])
                        }
                    }

                    var results: [MeltTaskResult] = []

                    for try await result in group {
                        results.append(result)
                    }

                    await MainActor.run {
                        handleSuccess(with: results)
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
                  let quote = event.bolt11MeltQuote else {
                // show error
                return
            }

            taskInputs.append(MeltTaskInput(mint: CashuSwift.Mint(mint),
                                            proofs: proofs.sendable(),
                                            quote: quote,
                                            blankOutputs: event.blankOutputs?.tuple()))
        }

        buttonState = .loading()

        var results = [MeltTaskResult]()
        Task {
            do {
                for input in taskInputs {
                    let result = try await CashuSwift.Bolt11.meltState(input.quote.quote,
                                                                       from: input.mint,
                                                                       blankOutputs: input.blankOutputs)
                    results.append(MeltTaskResult(mint: input.mint,
                                                  quote: result.quote,
                                                  change: result.change ?? []))
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
            guard let mint = mints.first(where: { $0.matches(result.mint) }) else {
                // TODO: show error saving change
                return
            }

            let internalChange = try? mint.addProofs(result.change,
                                                     to: modelContext)

            events.append(Event.meltEvent(unit: .sat,
                                          shortDescription: "Payment",
                                          wallet: activeWallet,
                                          amount: result.quote.amount,
                                          longDescription: "",
                                          mints: [mint],
                                          change: internalChange,
                                          preImage: result.quote.paymentPreimage,
                                          groupingID: groupingID,
                                          meltQuote: result.quote))
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
        dismissToRoot()
    }

    private func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}
