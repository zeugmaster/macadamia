//
//  MultiMeltViewV2.swift
//  macadamia
//
//  Created by zm on 18.08.25.
//

import SwiftUI
import SwiftData
import CashuSwift

struct MultiMeltViewV2: View {
    
    // MARK: - Helper Structs
    
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
    @State private var autoSelected = false
    @State private var selectorDisabled = false
    @State private var actionButtonState = ActionButtonState.idle("Select Mint")
    
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
        quoteEntries.values.contains { if case .error(_) = $0 { true } else { false } } ||
        quoteEntries.isEmpty
    }
    
    var body: some View {
        if let invoiceString {
            ZStack {
                List {
                    Section {
                        Text(invoiceString)
                            .monospaced()
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
                    ActionButton(state: $actionButtonState)
                        .actionDisabled(actionButtonDisabled)
                }
            }
            .alertView(isPresented: $showAlert, currentAlert: currentAlert)
        } else {
            InputView(supportedTypes: [.bolt11Invoice]) { input in
                withAnimation {
                    invoiceString = input.payload
                }
            }
            .padding()
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
                        switch selectedMints.count {
                        case 0:
                            Text("No mint selected")
                        case 1:
                            Text("Pay from: \(selectedMints.first?.displayName ?? "nil")")
                        default:
                            Text("Pay from \(selectedMints.count) mints")
                        }
                        
                        Text("Summary line")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    Spacer()
                    if selectedMints.count > 1 && autoSelected {
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
                            Image(systemName: selectedMints.contains(mint) ? "checkmark.circle.fill" : "circle")
                        }
                        .disabled(disableRow)
                        
                        VStack {
                            HStack {
                                Text(mint.displayName)
                                Spacer()
                                Text(String(mint.balance(for: .sat)) + " sat")
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
        }
    }
    
    private func initiateSelector() {
        if pendingMeltEvents.isEmpty {
            // auto select mints...
            autoSelected = true
        } else {
            // assign quotes and selection
            selectorDisabled = true
        }
    }
    
    private func toggleSelection(for mint: Mint) {
        withAnimation { autoSelected = false }

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

        let totalSelectedBalance = selectedMints.reduce(0) { $0 + $1.balance(for: .sat) }
        if (invoiceAmount ?? 0) > totalSelectedBalance { return }
        
        updateQuotes()
    }

    
    private func updateQuotes() {
        // load quotes and set action button state .loading
        guard let total = invoiceAmount, let invoiceString else {
            return
        }
        
        actionButtonState = .loading()
        selectorDisabled = true
        
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
                } catch {
                    logger.warning("Error when fetching quote: \(error)")
                    results.append((mint, QuoteState.error(String(describing: error))))
                }
            }
            await MainActor.run {
                for result in results {
                    if let mint = selectedMints.first(where: { $0.matches(result.0) }) {
                        quoteEntries[mint] = result.1
                    }
                }
                actionButtonState = .idle("Pay", action: buttonPressed)
                selectorDisabled = false
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

        let totBal = Decimal(totalBalance), tot = Decimal(total)
        var floors = [Int](), fracs = [Decimal]()
        floors.reserveCapacity(mints.count); fracs.reserveCapacity(mints.count)

        for m in mints {
            let raw = Decimal(m.balance(for: .sat)) / totBal * tot
            var tmp = raw, flr = Decimal()
            NSDecimalRound(&flr, &tmp, 0, .down)
            floors.append(NSDecimalNumber(decimal: flr).intValue)
            fracs.append(raw - flr)
        }

        let remainder = max(0, total - floors.reduce(0, +))
        let winners = Set(fracs.enumerated().sorted { $0.element > $1.element }.prefix(remainder).map { $0.offset })

        var out = [Mint: Int](minimumCapacity: mints.count)
        for i in mints.indices {
            out[mints[i]] = (floors[i] + (winners.contains(i) ? 1 : 0)) * 1_000
        }
        return out
    }
    
    private func buttonPressed() {
        if pendingMeltEvents.isEmpty {
            prepareMelt()
        } else {
            // check state
        }
    }
    
    private func prepareMelt() {
        guard let activeWallet else {
            return
        }
        
        selectorDisabled = true
        
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
                            let (quote, change, _) = try await CashuSwift.melt(quote: input.quote,
                                                                               mint: input.mint,
                                                                               proofs: input.proofs,
                                                                               blankOutputs: input.blankOutputs)
                            return MeltTaskResult(mint: input.mint, quote: quote, change: change ?? [])
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
                }
            }
        }
    }
    
    private func checkMeltState(for events: [Event]) {
        // load quote states:
        // if all paid: run on success
        // unpaid: allow retry
        // pending: prompt user to check again later
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
            
            let internalChange = try? mint.addProofs(result.change, to: modelContext, unit: .sat)
            
            events.append(Event.meltEvent(unit: .sat,
                                          shortDescription: "Payment",
                                          wallet: activeWallet,
                                          amount: result.quote.amount,
                                          longDescription: "",
                                          mints: [mint],
                                          change: internalChange,
                                          preImage: result.quote.paymentPreimage,
                                          groupingID: groupingID))
        }
        
        events.forEach({ modelContext.insert($0) })
        
        try? modelContext.save()
        
        actionButtonState = .success()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            dismiss()
        }
    }
    
    private func removePendingPayment() {
        // set pending ecash as valid
        // set events as hidden
        // dismiss
    }
    
    private func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}
