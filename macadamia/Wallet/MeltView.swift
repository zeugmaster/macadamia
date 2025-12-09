import SwiftUI
import SwiftData
import CashuSwift

// TODO: remove unsafe unwrapping, nicer pending error

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
    
    enum QuoteState { case quote(CashuSwift.Bolt11.MeltQuote), error(String)}
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]
    
    @State private var invoiceString: String?
    @State private var pendingMeltEvents = [Event]()
    
    @State private var quoteEntries: [Mint: QuoteState] = [:]
    @State private var selectedMints = Set<Mint>()
    @State private var showSelector = false
    @State private var autoSelect = true
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
    
    private var invoiceAmount: Int? {
        try? invoiceString.map({ try CashuSwift.Bolt11.satAmountFromInvoice(pr: $0) })
    }
    
    private var actionButtonDisabled: Bool {
        if pendingMeltEvents.isEmpty {
            if quoteEntries.values.contains(where: { if case .error(_) = $0 { true } else { false } }) ||
                quoteEntries.isEmpty {
                return true
            } else if insufficientBalance {
                return true
            } else {
                return false
            }
        } else {
            return false
        }
    }
    
    private var totalSelectedMintBalance: Int {
        selected.reduce(0, { $0 + $1.balance(for: .sat) })
    }
    
    private var insufficientBalance: Bool {
        totalSelectedMintBalance < (invoiceAmount ?? 0) + totalFee
    }
    
    private var selected: Set<Mint> {
        if pendingMeltEvents.isEmpty {
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
        } else {
            return Set(pendingMeltEvents.compactMap { $0.mints }.joined())
        }
    }
    
    private var totalFee: Int {
        let totalFeeArray = quoteEntries.values.compactMap { state in
            switch state {
            case .quote(let quote):
                return quote.feeReserve
            case .error(_):
                return nil
            }
        }
        return totalFeeArray.reduce(0, { $0 + $1 })
    }
    
    @ViewBuilder
    private var subline: some View {
        
        if selected.isEmpty {
            Text("Tap to select a mint from the list")
                .foregroundStyle(.secondary)
        } else if buttonState.type == .loading {
            Text("Attempting payment...")
                .foregroundStyle(.secondary)
        } else if buttonState.type == .success {
            Text("Payment successful!")
                .foregroundStyle(.secondary)
        } else if insufficientBalance {
            Text("Insufficient balance (including fees)")
                .foregroundStyle(.red)
        } else if quoteEntries.values.contains(where: { if case .error(_) = $0 { true } else { false } }) {
            Text("Error")
                .foregroundStyle(.orange)
        } else {
            
            Text("Total Lightning Fees: \(totalFee)")
                .foregroundStyle(.secondary)
        }
    }

    private var selectorDisabled: Bool {
        if pendingMeltEvents.isEmpty {
            return buttonState.type == .loading ? true : false
        } else {
            return true
        }
    }
    
    private var dynamicButtonState: ActionButtonState {
        switch (pendingMeltEvents.isEmpty, selected.isEmpty) {
        case (true, true): return .idle("Pay")
        case (true, false): return .idle("Pay", action: { prepareMelt() })
        case (false, _): return .idle("Check Payment State",
                                      action: { checkMeltState(for: pendingMeltEvents) })
        }
    }
    
    init(events: [Event]? = nil, invoice: String? = nil) {
        if let events {
            _pendingMeltEvents = State(initialValue: events)
            let invoices = Set(events.map({ $0.bolt11MeltQuote?.quoteRequest?.request }))
            if invoices.count == 1 {
                _invoiceString = State(initialValue: invoices.first!)
            } else {
                _invoiceString = State(initialValue: "Initialization Error") // FIXME: suboptimal and potentially leading to wonky behaviour
                logger.error("unable to initialize melt view, because none or too many invoice strings where gathered from pending events")
            }
            _autoSelect = State(initialValue: false)
        } else if let invoice {
            _invoiceString = State(initialValue: invoice)
        }
    }
    
    var body: some View {
        Group {
            if let invoiceString {
                ZStack {
                    List {
                        Section {
                            Text(invoiceString)
                                .monospaced()
                            HStack {
                                Text("Amount: ")
                                Spacer()
                                Text(amountDisplayString(invoiceAmount ?? 0, unit: .sat))
                                    .monospaced()
                            }
                            .foregroundStyle(.secondary)
                        } header: {
                            Text("BOLT11 INVOICE")
                        }
                        mintSelector
                        Spacer(minLength: 50)
                            .listRowBackground(Color.clear)
                    }
                    .lineLimit(1) // applies to entire list view, no text in this view should be more than 1 line
                    VStack {
                        Spacer()
                        ActionButton(state: $buttonState)
                            .actionDisabled(actionButtonDisabled)
                    }
                }
                .alertView(isPresented: $showAlert, currentAlert: currentAlert)
                .onAppear {
                    buttonState = dynamicButtonState
                    updateQuotes()
                }
            } else {
                InputView(supportedTypes: [.bolt11Invoice]) { input in
                    withAnimation {
                        invoiceString = input.payload
                    }
                }
                .padding()
            }
        }
    }
    
    var mintSelector: some View {
        Section {
            Button {
                withAnimation {
                    showSelector.toggle()
                }
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
            
            // expanding mint list
            if showSelector {
                ForEach(mints) { mint in
                    let disableRow = !mint.supportsMPP && mint.balance(for: .sat) < invoiceAmount ?? 0
                    HStack {
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
                                Group {
                                    let balance = mint.balance(for: .sat)

                                    Text(balance, format: .number)
                                        .contentTransition(.numericText(value: Double(balance)))
                                        .animation(.snappy, value: balance)

                                    Text(" sat")
                                }
                                .monospaced()
                            }
                            .foregroundStyle(disableRow ? .secondary : .primary)
                            HStack {
                                Text(mint.supportsMPP ? "MPP \(Image(systemName: "checkmark"))" : "Full payment")
                                Spacer()
                                if let quoteEntry = quoteEntries[mint] {
                                    switch quoteEntry {
                                    case .quote(let quote):
                                        Text("Fee: \(quote.feeReserve) • Allocation: \(quote.amount)")
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
                .disabled(selectorDisabled)
            }
        } footer: {
            if Double(invoiceAmount ?? 0) > Double(totalSelectedMintBalance) * 0.97 {
                Text("Payment amount approaching the total balance risks payment failure due to fees.")
                    .lineLimit(3)
            }
        }
    }
    
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

    
    private func updateQuotes(selectedMints: Set<Mint>? = nil) {
        // load quotes and set action button state .loading
        guard let total = invoiceAmount, let invoiceString else {
            return
        }
        
        let selectedMints = selectedMints ?? selected
        
        let totalSelectedBalance = selectedMints.reduce(0) { $0 + $1.balance(for: .sat) }
        if total > totalSelectedBalance { return }
        
        buttonState = .loading()
        
        let allocationsSendable = msatAllocations(for: total,
                                                  mints: Array(selectedMints)).map { (mint, allocation) in
            (CashuSwift.Mint(mint), allocation)
        }
        
        Task {
            var results = [(CashuSwift.Mint, QuoteState)]()
            for (mint, msat) in allocationsSendable {
                do {
                    let quote = try await loadQuote(mint: mint,
                                                    invoice: invoiceString,
                                                    msat: msat,
                                                    isMPP: allocationsSendable.count > 1)
                    results.append((mint, QuoteState.quote(quote)))
                } catch CashuError.networkError {
                    results.append((mint, QuoteState.error("Network error")))
                } catch CashuError.unknownError(let message) where message.contains("internal mpp not allowed") {
                    logger.warning("user tried to perform self-pay")
                    results.append((mint, QuoteState.error("Self-pay not possible")))
                } catch {
                    logger.warning("Error when fetching quote: \(error)")
                    results.append((mint, QuoteState.error("Unknown error")))
                }
            }
            await MainActor.run {
                for result in results {
                    if let mint = selectedMints.first(where: { $0.matches(result.0) }) {
                        quoteEntries[mint] = result.1
                    }
                }
                buttonState = dynamicButtonState
            }
        }
    }
    
    private func loadQuote(mint: CashuSwift.Mint,
                           invoice: String,
                           msat: Int,
                           isMPP: Bool) async throws -> CashuSwift.Bolt11.MeltQuote {
        let options = isMPP ? CashuSwift.Bolt11.RequestMeltQuote.Options(mpp: CashuSwift.Bolt11.RequestMeltQuote.Options.MPP(amount: msat)) : nil
        let request = CashuSwift.Bolt11.RequestMeltQuote(unit: "sat", request: invoice, options: options)
        guard let quote = try await CashuSwift.getQuote(mint: mint, quoteRequest: request) as? CashuSwift.Bolt11.MeltQuote else {
            throw CashuError.typeMismatch("CashuSwift returned unexpected type.")
        }
        return quote
    }
    
    private func msatAllocations(for total: Int, mints: [Mint]) -> [Mint: Int] {
        let totalBalance = mints.reduce(0) { $0 + $1.balance(for: .sat) }
        guard totalBalance > 0, total > 0 else { return Dictionary(uniqueKeysWithValues: mints.map { ($0, 0) }) }

        let totalMsat = total * 1_000
        var out = [Mint: Int](minimumCapacity: mints.count)
        
        for mint in mints {
            let allocation = (mint.balance(for: .sat) * totalMsat) / totalBalance
            let roundedUp = ((allocation + 999) / 1000) * 1000
            out[mint] = roundedUp
        }
        
        logger.info("created payment amount splits for \(total): \(out.map({ $0.key.url.absoluteString + ": " + String($0.value) }).joined(separator: ", "))")
        
        return out
    }
    
    private func prepareMelt() {
        guard let activeWallet else {
            return
        }
        
        buttonState = .loading()
        
        var quotes = [Mint: CashuSwift.Bolt11.MeltQuote]()
        for (mint, quoteEntry) in quoteEntries {
            switch quoteEntry {
            case .quote(let quote):
                quotes[mint] = quote
            case .error(_):
                logger.error("tried to initiate mint while quote entries contains errors, leaving.")
                return
            }
        }
        
        //pick proofs,  create pending events (optional grouping id)
        let groupingID = quotes.count > 1 ? UUID() : nil
        let disc = quotes.count > 1 ? "Pending Payment Part" : "Pending Payment"
        var events = [Event]()
        for (mint, quote) in quotes {
            guard let proofs = mint.select(amount: quote.amount + quote.feeReserve,
                                           unit: .sat) else {
                displayAlert(alert: AlertDetail(title: "Proof Selection Error",
                                                description: "The wallet was not able to pick ecash proofs from mint \(mint.displayName)."))
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
                                                                           unit: "sat",
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
        
        melt(with: events)
    }
    
    private func melt(with events: [Event]) {
        
        // convert event info into labeled, sendable task group inputs
        let taskGroupInputs: [MeltTaskInput]
        
        taskGroupInputs = events.map { event in
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
                            let meltResult = try await CashuSwift.melt(quote: input.quote,
                                                                       mint: input.mint,
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
                    buttonState = dynamicButtonState
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
                    let result = try await CashuSwift.meltState(for: input.quote.quote,
                                                                with: input.mint,
                                                                blankOutputs: input.blankOutputs)
                    results.append(MeltTaskResult(mint: input.mint,
                                                  quote: result.quote,
                                                  change: result.change ?? []))
                }
                
                await MainActor.run {
                    if results.allSatisfy({ $0.quote.state == .paid }) {
                        handleSuccess(with: results)
                    } else if results.allSatisfy({ $0.quote.state == .pending }) {
                        displayAlert(alert: AlertDetail(title: "Payment Pending ⏳",
                                                        description: "This payment is still pending. Please check again later to make sure the lightning payment was successful."))
                        buttonState = dynamicButtonState
                    } else if results.allSatisfy({ $0.quote.state == .unpaid }) {
                        let primary = AlertButton(title: "Retry",
                                                  action: { melt(with: events) })
                        let secondary = AlertButton(title: "Remove Payment",
                                                    role: .destructive,
                                                    action: { removePendingPayment(events: events) })
                        displayAlert(alert: AlertDetail(title: "Unpaid ⚠",
                                                        description: "This payment did not go through and is marked \"unpaid\" with the mint. Would you like to try again?",
                                                        primaryButton: primary,
                                                        secondaryButton: secondary))
                        buttonState = dynamicButtonState
                    } else if results.contains(where: { $0.quote.state == .pending }) {
                        displayAlert(alert: AlertDetail(title: "Payment Pending ⏳",
                                                        description: "One or more parts of this payment are still pending. Please check again later to make sure the lightning payment was successful."))
                        buttonState = dynamicButtonState
                    } else if results.contains(where: { $0.quote.state == .unpaid }) {
                        let primary = AlertButton(title: "Retry",
                                                  action: { melt(with: events) })
                        let secondary = AlertButton(title: "Remove Payment",
                                                    role: .destructive,
                                                    action: { removePendingPayment(events: events) })
                        displayAlert(alert: AlertDetail(title: "Unpaid ⚠",
                                                        description: "This payment did not go through and one or more parts are marked \"unpaid\". Would you like to try again?",
                                                        primaryButton: primary,
                                                        secondaryButton: secondary))
                        buttonState = dynamicButtonState
                    }
                }
            } catch {
                await MainActor.run {
                    logger.error("unable to check one or more quote states due to error: \(error)")
                    displayAlert(alert: AlertDetail(with: error))
                    buttonState = dynamicButtonState
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
        
        buttonState = .success("Paid!")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            dismiss()
        }
    }
    
    private func removePendingPayment(events: [Event]) {
        for e in events {
            e.proofs?.setState(.valid)
            e.visible = false
        }
        dismiss()
    }
    
    private func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}
