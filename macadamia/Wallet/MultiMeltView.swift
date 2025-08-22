import SwiftUI
import SwiftData
import CashuSwift

struct MintRowInfo: Identifiable {
    let mint: Mint
    var partialAmount: Int = 0
    var fee: Int?
    var quote: CashuSwift.Bolt11.MeltQuote?
    
    // Use mint's URL as stable identifier
    var id: String {
        mint.url.absoluteString
    }
    
    var balance: Int {
        mint.balance(for: .sat)
    }
}

struct MultiMeltView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]
    
    var activeWallet: Wallet? {
        wallets.first
    }
    
    @State private var pendingMeltEvents: [Event]?
    
    @State private var actionButtonState: ActionButtonState = .idle("Scan or paste invoice")
    @State private var invoiceString: String?
    @State private var mintRowInfoArray: [MintRowInfo] = []
    
    @State private var mintListEditing = false
    @State private var multiMintRequired: Bool = false
    @State private var automaticallySelected: Bool = false
    
    @State private var selectedMintIds: Set<String> = []
    
    @State private var showAlert: Bool = false
    @State private var currentAlert: AlertDetail?
    @State private var showMintSelector: Bool = false
    @State private var insufficientFundsError: String? = nil
    @State private var scannerResetID = UUID() // Used to force InputView recreation on reset
    @State private var insufficientSelectionError: String? = nil
    
    init(pendingMeltEvents: [Event]? = nil, invoice: String? = nil) {
        self._pendingMeltEvents = State(initialValue: pendingMeltEvents)
        self._invoiceString = State(initialValue: invoice)
        // Set appropriate action button state based on whether we have an invoice
        if invoice != nil {
            self._actionButtonState = State(initialValue: .idle("Loading..."))
        } else if pendingMeltEvents != nil && !pendingMeltEvents!.isEmpty {
            // If we have pending events, show check payment button
            self._actionButtonState = State(initialValue: .idle("Check Payment Status", action: nil))
        }
    }
    
    var body: some View {
        ZStack {
            List {
                if let invoiceString {
                    Group {
                        Section {
                            Text(invoiceString)
                            .foregroundStyle(.gray)
                            .monospaced()
                            .lineLimit(1)
                        } header: {
                            HStack {
                                Text("Invoice")
                                Spacer()
                                Button {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        // Reset to scanner view
                                        self.invoiceString = nil
                                        selectedMintIds = []
                                        mintRowInfoArray = []
                                        insufficientFundsError = nil
                                        insufficientSelectionError = nil
                                        multiMintRequired = false
                                        automaticallySelected = false
                                        showMintSelector = false
                                        actionButtonState = .idle("Scan or paste invoice")
                                        // Force InputView to be recreated
                                        scannerResetID = UUID()
                                    }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .help("Clear invoice and return to scanner")
                            }
                        }
                        .onAppear {
                            populateMintList(invoice: invoiceString)
                            // Only auto-select if we don't have pending events
                            if pendingMeltEvents == nil || pendingMeltEvents!.isEmpty {
                                autoSelectMintsAndFetchQuotes()
                                if selectedMintIds.isEmpty {
                                    actionButtonState = .idle("Select Mints")
                                } else {
                                    actionButtonState = .idle("Pay", action: initiateMelt)
                                }
                            }
                        }
                        .onChange(of: insufficientFundsError) { _, newValue in
                            // Don't modify action button if we have pending events
                            if pendingMeltEvents == nil || pendingMeltEvents!.isEmpty {
                                if newValue != nil {
                                    actionButtonState = .idle("Insufficient Funds")
                                } else if !selectedMintIds.isEmpty {
                                    actionButtonState = .idle("Pay", action: initiateMelt)
                                }
                            }
                        }
                        .onChange(of: insufficientSelectionError) { _, newValue in
                            // Don't modify action button if we have pending events
                            if pendingMeltEvents == nil || pendingMeltEvents!.isEmpty {
                                if newValue != nil {
                                    actionButtonState = .idle("Insufficient Selection")
                                } else if !selectedMintIds.isEmpty && insufficientFundsError == nil {
                                    actionButtonState = .idle("Pay", action: initiateMelt)
                                }
                            }
                        }
                        .onChange(of: selectedMintIds) { _, newValue in
                            // Don't modify action button if we have pending events
                            if pendingMeltEvents == nil || pendingMeltEvents!.isEmpty {
                                if newValue.isEmpty {
                                    actionButtonState = .idle("Select Mints")
                                } else if insufficientFundsError == nil && insufficientSelectionError == nil {
                                    actionButtonState = .idle("Pay", action: initiateMelt)
                                }
                            }
                        }
                        
                        Section {
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    showMintSelector.toggle()
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(mintSelectionSummary)
                                            .foregroundColor(.primary)
                                        Text(mintSelectionDetails)
                                            .font(.caption)
                                            .foregroundColor(insufficientSelectionError != nil ? .orange : .secondary)
                                    }
                                    Spacer()
                                    
                                    // Show wand icon if selection was automatic
                                    if multiMintRequired && automaticallySelected {
                                        Image(systemName: "wand.and.stars")
                                            .foregroundColor(.secondary)
                                            .font(.title3)
                                            .transition(.scale.combined(with: .opacity))
                                            .help("Mints automatically selected for optimal payment")
                                    }
                                    
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                        .font(.footnote)
                                        .rotationEffect(.degrees(showMintSelector ? 90 : 0))
                                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showMintSelector)
                                }
                                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: automaticallySelected)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(insufficientFundsError != nil || (pendingMeltEvents != nil && !pendingMeltEvents!.isEmpty))
                            
                            if showMintSelector {
                                let invoiceAmount = (try? CashuSwift.Bolt11.satAmountFromInvoice(pr: invoiceString.lowercased())) ?? 0
                                
                                ForEach(mintRowInfoArray) { mintInfo in
                                    mintRowView(for: mintInfo, invoiceAmount: invoiceAmount)
                                }
                                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedMintIds)
                            }
                        } header: {
                            Text("Pay from")
                        }
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: insufficientFundsError)
                        
                        // Show insufficient funds error if present
                        if let errorMessage = insufficientFundsError {
                            Section {
                                HStack(spacing: 12) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.orange)
                                        .font(.title2)
                                    
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Insufficient Balance")
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        
                                        Text(errorMessage)
                                            .font(.footnote)
                                            .foregroundColor(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    
                                    Spacer()
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.orange.opacity(0.1))
                                )
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity),
                                    removal: .scale.combined(with: .opacity)
                                ))
                                .listRowBackground(EmptyView())
                            }
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    Group {
                        InputView(supportedTypes: [.bolt11Invoice]) { result in
                            guard result.type == .bolt11Invoice else { return }
                            withAnimation(.easeInOut(duration: 0.3)) {
                                invoiceString = result.payload
                            }
                        }
                        .id(scannerResetID)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    }
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
                }
                
                Spacer(minLength: 50)
                    .listRowBackground(Color.clear)
            }
            .animation(.easeInOut(duration: 0.3), value: invoiceString)
            
            VStack {
                Spacer()
                ActionButton(state: $actionButtonState)
                    .actionDisabled(
                        // Allow action if we have pending events (for checking status)
                        (pendingMeltEvents == nil || pendingMeltEvents!.isEmpty) &&
                        (insufficientFundsError != nil ||
                         insufficientSelectionError != nil ||
                         selectedMintIds.isEmpty ||
                         invoiceString == nil)
                    )
            }
        }
        .alertView(isPresented: $showAlert, currentAlert: currentAlert)
        .onAppear {
            // If we have pending events, setup the recovery UI
            if let pendingEvents = pendingMeltEvents, !pendingEvents.isEmpty {
                setupPendingEventsUI(pendingEvents)
            }
        }
    }
    
    private var mintSelectionSummary: String {
        if selectedMintIds.isEmpty {
            return "Select mints to pay from"
        } else {
            let selectedMints = mintRowInfoArray.filter { selectedMintIds.contains($0.id) }
            if selectedMints.count == 1 {
                return selectedMints.first?.mint.displayName ?? "1 mint selected"
            } else {
                return "\(selectedMints.count) mints selected"
            }
        }
    }
    
    private var mintSelectionDetails: String {
        if selectedMintIds.isEmpty {
            return "No mint selected"
        }
        
        let selectedMints = mintRowInfoArray.filter { selectedMintIds.contains($0.id) }
        let totalBalance = selectedMints.map { $0.balance }.reduce(0, +)
        let totalFees = selectedMints.compactMap { $0.fee }.reduce(0, +)
        
        if let error = insufficientSelectionError {
            return "⚠️ \(error)"
        } else if totalFees > 0 {
            return "Balance: \(totalBalance) sats • Total fees: \(totalFees) sats"
        } else {
            return "Balance: \(totalBalance) sats"
        }
    }
    
    @ViewBuilder
    private func mintRowView(for mintInfo: MintRowInfo, invoiceAmount: Int) -> some View {
        let canPayFull = mintInfo.balance >= invoiceAmount
        let supportsMPP = mintInfo.mint.supportsMPP
        let hasPendingEvents = pendingMeltEvents != nil && !pendingMeltEvents!.isEmpty
        let isDisabled = (!canPayFull && !supportsMPP) || hasPendingEvents
        let isSelected = selectedMintIds.contains(mintInfo.id)
        
        HStack {
            Button {
                if !isDisabled {
                    toggleSelection(for: mintInfo.id)
                }
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isDisabled ? .gray : (isSelected ? .accentColor : .secondary))
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isDisabled)
            
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(mintInfo.mint.displayName)
                    Spacer()
                    Text("\(mintInfo.balance) sats")
                        .font(.footnote)
                        .monospaced()
                }
                .foregroundColor(isDisabled ? .gray : .primary)
                
                HStack {
                    // MPP support indicator
                    if supportsMPP {
                        Text("MPP \(Image(systemName: "arrow.triangle.branch"))")
                            .font(.caption2)
                    } else if canPayFull {
                        HStack(spacing: 2) {
                            Text("Full payment")
                                .font(.caption2)
                        }
                    } else {
                        Text("Insufficient balance")
                            .font(.caption2)
                    }
                    
                    Spacer()
                    
                    // Only show fee and allocation if selected and quote loaded
                    if isSelected, let fee = mintInfo.fee, mintInfo.partialAmount > 0 {
                        Text("Fee: \(fee) • Allocation: \(mintInfo.partialAmount)")
                            .font(.caption2)
                            .monospaced()
                    }
                }
                .foregroundStyle(isDisabled ? .gray : .secondary)
            }
        }
        .opacity(isDisabled ? 0.6 : 1.0)
        .transition(.asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .move(edge: .top).combined(with: .opacity)
        ))
    }
    
    private func populateMintList(invoice: String) {
        let amount = (try? CashuSwift.Bolt11.satAmountFromInvoice(pr: invoice.lowercased())) ?? 0
        let filteredMints = activeWallet?.mints.filter({ ($0.balance(for: .sat) > 0 && $0.supportsMPP) ||
                                                          $0.balance(for: .sat) > amount })
            .filter({ !$0.hidden }) ?? []
        
        // Group mints by URL and take only the one with highest balance per URL
        var mintsByURL: [String: Mint] = [:]
        for mint in filteredMints {
            let url = mint.url.absoluteString
            if let existing = mintsByURL[url] {
                // Keep the mint with higher balance
                if mint.balance(for: .sat) > existing.balance(for: .sat) {
                    mintsByURL[url] = mint
                }
            } else {
                mintsByURL[url] = mint
            }
        }
        
        mintRowInfoArray = mintsByURL.values
            .map({ mint in
                return MintRowInfo(mint: mint)
            })
            .sorted(by: { ($0.mint.userIndex ?? Int.max) < ($1.mint.userIndex ?? Int.max) })
    }
    
    // GENERAL SELECTION METHODS:
    
    private func toggleSelection(for id: String) {
        // Disable selection if we have pending events
        if pendingMeltEvents != nil && !pendingMeltEvents!.isEmpty {
            return
        }
        
        // Mark that user has manually changed selection
        automaticallySelected = false
        // Clear any errors when user takes control - they will be recalculated
        insufficientFundsError = nil
        insufficientSelectionError = nil
        
        // Implement mutual exclusion for non-MPP mints:
        // - Non-MPP mints that can pay the full invoice must be used exclusively
        // - Selecting such a mint deselects all others
        // - Selecting any other mint deselects non-MPP exclusive mints
        
        guard let mintInfo = mintRowInfoArray.first(where: { $0.id == id }) else { return }
        let invoiceAmount = (try? CashuSwift.Bolt11.satAmountFromInvoice(pr: invoiceString?.lowercased() ?? "")) ?? 0
        
        if selectedMintIds.contains(id) {
            // Deselecting
            selectedMintIds.remove(id)
        } else {
            // Selecting
            let isNonMPPFullPayment = !mintInfo.mint.supportsMPP && mintInfo.balance >= invoiceAmount
            
            if isNonMPPFullPayment {
                // Non-MPP mint that can pay full invoice - deselect all others
                selectedMintIds = [id]
            } else {
                // Check if any currently selected mint is a non-MPP full payment mint
                let hasNonMPPSelected = mintRowInfoArray.contains { info in
                    selectedMintIds.contains(info.id) && 
                    !info.mint.supportsMPP && 
                    info.balance >= invoiceAmount
                }
                
                if hasNonMPPSelected {
                    // Remove non-MPP mints when selecting an MPP mint
                    selectedMintIds = selectedMintIds.filter { selectedId in
                        guard let selectedMint = mintRowInfoArray.first(where: { $0.id == selectedId }) else { return false }
                        return selectedMint.mint.supportsMPP || selectedMint.balance < invoiceAmount
                    }
                }
                
                selectedMintIds.insert(id)
            }
        }
        reloadMintQuotes()
    }
    

    private func reloadMintQuotes() {
        // Don't reload quotes if we have pending events
        if pendingMeltEvents != nil && !pendingMeltEvents!.isEmpty {
            return
        }
        
        if selectedMintIds.isEmpty { 
            insufficientSelectionError = nil
            return 
        }
        guard let invoiceString,
              let invoiceAmountSat = try? CashuSwift.Bolt11.satAmountFromInvoice(pr: invoiceString.lowercased())
        else { return }
        
        // Reset mint row info data before loading new quotes
        for i in mintRowInfoArray.indices {
            mintRowInfoArray[i].quote = nil
            mintRowInfoArray[i].partialAmount = 0
            mintRowInfoArray[i].fee = 0
        }

        let selected = mintRowInfoArray.filter { selectedMintIds.contains($0.id) }
        let totalBalance = selected.map { $0.mint.balance(for: .sat) }.reduce(0, +)
        
        // Early check: ensure total balance is at least the invoice amount
        // The real check including fees happens after quotes are loaded
        if totalBalance < invoiceAmountSat {
            let shortage = invoiceAmountSat - totalBalance
            insufficientSelectionError = "Need \(shortage) more sats (have \(totalBalance)/\(invoiceAmountSat)+fees)"
            return
        } else {
            insufficientSelectionError = nil
        }
        let totalBalanceDec = Decimal(totalBalance)
        let totalSatDec = Decimal(invoiceAmountSat)

        struct ShareInfo {
            let row: MintRowInfo
            let floorPart: Int
            let fraction: Decimal
        }

        var shares = [ShareInfo]()
        for row in selected {
            let balDec = Decimal(row.mint.balance(for: .sat))
            let raw = balDec / totalBalanceDec * totalSatDec
            var tmp = raw, flr = Decimal()
            NSDecimalRound(&flr, &tmp, 0, .down)
            let floorInt = NSDecimalNumber(decimal: flr).intValue
            shares.append(ShareInfo(row: row, floorPart: floorInt, fraction: raw - flr))
        }

        let floorSum = shares.map(\.floorPart).reduce(0, +)
        let remainder = invoiceAmountSat - floorSum
        let sorted = shares.enumerated().sorted { $0.element.fraction > $1.element.fraction }

        var list: [(String, CashuSwift.Mint, Int)] = []
        for (index, info) in shares.enumerated() {
            let extraSat = sorted.prefix(remainder).map(\.offset).contains(index) ? 1 : 0
            let sats = info.floorPart + extraSat
            let msats = sats * 1_000
            list.append((info.row.id, CashuSwift.Mint(info.row.mint), msats))
        }

        Task {
            do {
                let result = try await loadQuotes(for: list, invoice: invoiceString)
                await MainActor.run {
                    // Check if any quotes failed to load
                    if !result.failedMints.isEmpty {
                        if result.failedMints.count == list.count {
                            // All quotes failed
                            insufficientSelectionError = "Cannot reach selected mints"
                        } else {
                            // Some quotes failed
                            let failedList = result.failedMints.joined(separator: ", ")
                            insufficientSelectionError = "Cannot reach: \(failedList)"
                        }
                        return
                    }
                    
                    // Process successful quotes
                    for quote in result.quotes {
                        guard let i = mintRowInfoArray.firstIndex(where: { $0.id == quote.0 }) else { continue }
                        mintRowInfoArray[i].quote = quote.1
                        mintRowInfoArray[i].partialAmount = Int(quote.2 / 1000)
                        mintRowInfoArray[i].fee = quote.1.feeReserve
                    }
                    
                    // Recheck balance after fees are known
                    var totalRequired = 0
                    for mintInfo in mintRowInfoArray where selectedMintIds.contains(mintInfo.id) {
                        let required = mintInfo.partialAmount + (mintInfo.fee ?? 0)
                        if mintInfo.mint.balance(for: .sat) < required {
                            let shortage = required - mintInfo.mint.balance(for: .sat)
                            insufficientSelectionError = "\(mintInfo.mint.displayName): need \(shortage) more sats (fee: \(mintInfo.fee ?? 0))"
                            return
                        }
                        totalRequired += required
                    }
                    
                    // Clear error if all mints have sufficient balance
                    insufficientSelectionError = nil
                }
            } catch {
                await MainActor.run {
                    insufficientSelectionError = "Connection error - check network"
                }
                print("error fetching quotes: \(error)")
            }
        }
    }

    
    private func loadQuotes(for list: [(id: String, mint: CashuSwift.Mint, amount: Int)],
                              invoice: String) async throws -> (quotes: [(String, CashuSwift.Bolt11.MeltQuote, Int)], failedMints: [String]) {
        var quotes: [(String, CashuSwift.Bolt11.MeltQuote, Int)] = []
        var failedMints: [String] = []
        
        for entry in list {
            let options = CashuSwift.Bolt11.RequestMeltQuote.Options(mpp: CashuSwift.Bolt11.RequestMeltQuote.Options.MPP(amount: entry.amount))
            let request = CashuSwift.Bolt11.RequestMeltQuote(unit: "sat",
                                                             request: invoice,
                                                             options: list.count < 2 ? nil : options)
            do {
                guard let quote = try await CashuSwift.getQuote(mint: entry.mint,
                                                                quoteRequest: request) as? CashuSwift.Bolt11.MeltQuote else {
                    fatalError("quote request returned unexpected type")
                }
                quotes.append((entry.id, quote, entry.amount))
            } catch {
                print("error fetching quote from mint: \(entry.mint.url.absoluteString), error: \(error), target amount: \(entry.amount)")
                failedMints.append(entry.mint.url.host() ?? entry.mint.url.absoluteString)
            }
        }
        return (quotes, failedMints)
    }
    
    private func initiateMelt() {
        // skip pending mint events for now
        guard let activeWallet else {
            return
        }
        
        // Don't proceed if there's insufficient balance or selection
        guard insufficientFundsError == nil && insufficientSelectionError == nil else {
            return
        }
        
        let selectedMintsInfo = mintRowInfoArray.filter({ selectedMintIds.contains($0.id) })
        guard !selectedMintsInfo.isEmpty else { return }
        
        actionButtonState = .loading()
        
        
        let disc = selectedMintsInfo.count > 1 ? "Payment Part" : "Payment"
        
        // Generate grouping ID for multi-mint payments
        let eventGroupingID = selectedMintsInfo.count > 1 ? UUID() : nil
        
        var pendingEvents: [Event] = []
        
        let mintsAndProofs = selectedMintsInfo.compactMap { row -> (mint: Mint, quote: CashuSwift.Bolt11.MeltQuote, proofs: [Proof])? in
            
            // Select proofs for the required amount
            guard let selected = row.mint.select(amount: row.partialAmount + (row.fee ?? 0), unit: .sat) else {
                print("Failed to select proofs for mint: \(row.mint.displayName)")
                return nil
            }
            guard let quote = row.quote else {
                print("Missing quote for mint: \(row.mint.displayName)")
                return nil
            }
            
            // Generate blank outputs for potential change
            var blankOutputSet: BlankOutputSet? = nil
            do {
                let blankOutputs = try CashuSwift.generateBlankOutputs(
                    quote: quote,
                    proofs: selected.selected.sendable(),
                    mint: CashuSwift.Mint(row.mint),
                    unit: "sat",
                    seed: activeWallet.seed
                )
                blankOutputSet = BlankOutputSet(tuple: blankOutputs)
                
                // Increase derivation counter for the keyset
                if let keysetId = blankOutputs.outputs.first?.id {
                    row.mint.increaseDerivationCounterForKeysetWithID(keysetId, by: blankOutputs.outputs.count)
                }
            } catch {
                print("Failed to generate blank outputs for mint \(row.mint.displayName): \(error)")
                // Continue without blank outputs - we won't be able to claim change
            }
            
            // Create pending melt event for this mint
            // Persisting quote, proofs and blank outputs for proper recovery
            let pendingEvent = Event.pendingMeltEvent(
                unit: .sat,
                shortDescription: disc,
                visible: true, // Explicitly set visible to true
                wallet: activeWallet,
                quote: quote,
                amount: row.partialAmount,
                expiration: quote.expiry.map({ Date(timeIntervalSince1970: TimeInterval($0)) }) ?? Date.now + 3600,
                mints: [row.mint],
                proofs: selected.selected,
                groupingID: eventGroupingID
            )
            
            // Assign blank outputs to the event
            pendingEvent.blankOutputs = blankOutputSet
            pendingEvents.append(pendingEvent)
            
            // Mark proofs as pending
            selected.selected.setState(.pending)
            
            return (mint: row.mint, quote: quote, proofs: selected.selected)
        }
        
        // Check if we failed to prepare any mints
        if mintsAndProofs.count != selectedMintsInfo.count {
            actionButtonState = .fail()
            displayAlert(alert: AlertDetail(title: "Preparation Error", 
                                            description: "Failed to prepare payment for one or more mints"))
            return
        }
        
        // Persist all pending events (quote, associated proofs, and blank outputs)
        // This allows for tracking payment attempts, properly updating proof states
        // when checking payment status later, and claiming any change
        pendingEvents.forEach { modelContext.insert($0) }
        
        // Save the model context to ensure events and proof states are persisted before starting the melt operation
        do {
            try modelContext.save()
        } catch {
            print("Failed to save pending events: \(error)")
        }
        
        let taskGroupInputs = mintsAndProofs.enumerated().map { index, entry in
            let blankOutputs = pendingEvents[index].blankOutputs
            return (CashuSwift.Mint(entry.mint), entry.quote, entry.proofs.sendable(), blankOutputs)
        }
        
        Task {
            do {
                try await withThrowingTaskGroup(of: (CashuSwift.Mint, CashuSwift.Bolt11.MeltQuote, [CashuSwift.Proof]).self) { group in
                    for input in taskGroupInputs {
                        group.addTask {
                            let (quote, change) = try await melt(with: input.1, on: input.0, proofs: input.2, blankOutputs: input.3)
                            return (input.0, quote,change)
                        }
                    }
                    var results: [(CashuSwift.Mint, CashuSwift.Bolt11.MeltQuote, [CashuSwift.Proof])] = []
                    for try await result in group {
                        results.append(result)
                    }
                    
                    // return to main thread with change and save, mark inputs as spent
                    try await MainActor.run {
                        try handleSuccessfulMelt(
                            mintsAndProofs: mintsAndProofs,
                            meltResults: results,
                            activeWallet: activeWallet,
                            shortDescription: disc,
                            eventGroupingID: eventGroupingID,
                            pendingEvents: pendingEvents
                        )
                    }
                }
            } catch {
                await MainActor.run {
                    // Revert all selected proofs back to valid state
                    for entry in mintsAndProofs {
                        entry.proofs.setState(.valid)
                    }
                    
                    // Remove pending events on failure
                    for event in pendingEvents {
                        modelContext.delete(event)
                    }
                    
                    displayAlert(alert: AlertDetail(with: error))
                    actionButtonState = .fail()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        actionButtonState = .idle("Pay", action: initiateMelt)
                    }
                }
            }
        }
    }
    
    // as simple as possible, non-det change outputs
    private func melt(with quote: CashuSwift.Bolt11.MeltQuote,
                      on mint: CashuSwift.Mint,
                      proofs: [CashuSwift.Proof],
                      blankOutputs: BlankOutputSet?) async throws -> (CashuSwift.Bolt11.MeltQuote, [CashuSwift.Proof]) {
        let outputs: (outputs: [CashuSwift.Output], blindingFactors: [String], secrets: [String])?
        if let blankOutputs {
            outputs = (blankOutputs.outputs, blankOutputs.blindingFactors, blankOutputs.secrets)
        } else {
            // Fallback: generate blank outputs if not provided
            outputs = try CashuSwift.generateBlankOutputs(quote: quote, proofs: proofs, mint: mint, unit: "sat", seed: activeWallet?.seed)
        }
        let result = try await CashuSwift.melt(quote: quote, mint: mint, proofs: proofs, blankOutputs: outputs)
        return (result.quote, result.change ?? [])
    }
    
    private func handleSuccessfulMelt(mintsAndProofs: [(mint: Mint, quote: CashuSwift.Bolt11.MeltQuote, proofs: [Proof])],
                                      meltResults: [(CashuSwift.Mint, CashuSwift.Bolt11.MeltQuote, [CashuSwift.Proof])],
                                activeWallet: Wallet,
                                shortDescription: String,
                                eventGroupingID: UUID?,
                                pendingEvents: [Event]) throws {
        // Mark all used proofs as spent
        for entry in mintsAndProofs {
            entry.proofs.setState(.spent)
        }
        
        // Hide pending events instead of deleting them to avoid view state inconsistencies
        for event in pendingEvents {
            event.visible = false
        }
        
        // Add change proofs and create events
        for result in meltResults {
            if let internalMint = activeWallet.mints.first(where: { $0.url == result.0.url }) { // FIXME: DO NOT MATCH MINTS BY URL
                try internalMint.addProofs(result.2,
                                           to: modelContext,
                                           unit: .sat) // TODO: remove hard coded unit
                
                let event = Event.meltEvent(unit: .sat,
                                            shortDescription: shortDescription,
                                            wallet: activeWallet,
                                            amount: result.1.amount,
                                            longDescription: "",
                                            mints: [internalMint],
                                            preImage: result.1.paymentPreimage,
                                            groupingID: eventGroupingID)
                modelContext.insert(event)
                
                // Debug logging
                if let groupingID = eventGroupingID {
                    print("Created melt event with groupingID: \(groupingID) for mint: \(internalMint.displayName)")
                }
            }
        }
        
        // Save context to ensure groupingID is persisted
        try modelContext.save()
        
        // Update UI state
        actionButtonState = .success()
        
        // Dismiss the view after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            dismiss()
        }
    }
    
    private func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
    
    private func autoSelectMintsAndFetchQuotes() {
        guard let invoiceString,
              let invoiceAmountSat = try? CashuSwift.Bolt11.satAmountFromInvoice(pr: invoiceString.lowercased())
        else { return }
        
        // Sort mints by balance (descending) to optimize selection
        let sortedMints = mintRowInfoArray.sorted { $0.balance > $1.balance }
        
        // Clear any previous error
        insufficientFundsError = nil
        
        // Check if any single mint can pay the full amount
        // This includes non-MPP mints, which must be used exclusively
        if let singleMint = sortedMints.first(where: { $0.balance >= invoiceAmountSat }) {
            // Single mint can pay - allow selection from the beginning
            multiMintRequired = false
            selectedMintIds = [singleMint.id]
            automaticallySelected = false
        } else {
            // Need multiple mints - find minimum set that supports MPP
            var totalBalance = 0
            var selectedMints: [MintRowInfo] = []
            
            // First, select all MPP-supporting mints until we have enough balance
            for mint in sortedMints where mint.mint.supportsMPP {
                selectedMints.append(mint)
                totalBalance += mint.balance
                if totalBalance >= invoiceAmountSat {
                    break
                }
            }
            
            // Check if we have enough with MPP mints
            if totalBalance < invoiceAmountSat {
                // Not enough even with all MPP mints - show error
                let shortage = invoiceAmountSat - totalBalance
                let mppMintCount = sortedMints.filter { $0.mint.supportsMPP }.count
                insufficientFundsError = "You have \(totalBalance) sats across \(mppMintCount) MPP mints, but need \(invoiceAmountSat) sats total. Add \(shortage) more sats to any MPP-supporting mint to complete this payment."
                multiMintRequired = false
                automaticallySelected = false
                selectedMintIds = []
                return
            }
            
            // Set the selected mints and update state
            multiMintRequired = true
            automaticallySelected = true
            selectedMintIds = Set(selectedMints.map { $0.id })
            mintListEditing = false
        }
        
        // Fetch quotes for selected mints
        reloadMintQuotes()
    }
    
    private func checkPendingMeltEvents(_ events: [Event]) async {
        // Group events by groupingID (or treat individually if no groupingID)
        var groupedEvents: [UUID?: [Event]] = [:]
        for event in events {
            let key = event.groupingID
            if groupedEvents[key] == nil {
                groupedEvents[key] = []
            }
            groupedEvents[key]?.append(event)
        }
        
        // Process each group
        for (groupingID, groupEvents) in groupedEvents {
            await checkMeltEventGroup(groupEvents, groupingID: groupingID)
        }
    }
    
    private func checkMeltEventGroup(_ events: [Event], groupingID: UUID?) async {
        var paidEvents: [(Event, CashuSwift.Bolt11.MeltQuote, [CashuSwift.Proof]?)] = []
        var pendingEvents: [Event] = []
        var unpaidEvents: [Event] = []
        
        print("Checking melt event group with \(events.count) events, groupingID: \(groupingID?.uuidString ?? "nil")")
        
        // Check status of each event
        for event in events {
            guard let quote = event.bolt11MeltQuote,
                  let mint = event.mints?.first else {
                print("Invalid pending event: missing quote or mint")
                continue
            }
            
            do {
                // Prepare blank outputs if available
                let blankOutputs: (outputs: [CashuSwift.Output], blindingFactors: [String], secrets: [String])?
                if let blankOutputSet = event.blankOutputs {
                    blankOutputs = (blankOutputSet.outputs, blankOutputSet.blindingFactors, blankOutputSet.secrets)
                } else {
                    blankOutputs = nil
                }
                
                // Check the payment status without blocking
                let result: (quote: CashuSwift.Bolt11.MeltQuote,
                             change: [CashuSwift.Proof]?,
                             dleqResult: CashuSwift.Crypto.DLEQVerificationResult) = try await CashuSwift.meltState(
                    for: quote.quote,
                    with: CashuSwift.Mint(mint),
                    blankOutputs: blankOutputs
                )
                
                switch result.quote.state {
                case .paid:
                    paidEvents.append((event, result.quote, result.change))
                case .pending:
                    pendingEvents.append(event)
                case .unpaid:
                    unpaidEvents.append(event)
                default:
                    print("Unknown quote state for event")
                }
            } catch {
                print("Error checking melt state: \(error)")
                // Treat as unpaid to allow retry
                unpaidEvents.append(event)
            }
        }
        
        // Handle the results
        await MainActor.run {
            handleMeltCheckResults(
                paidEvents: paidEvents,
                pendingEvents: pendingEvents,
                unpaidEvents: unpaidEvents,
                groupingID: groupingID
            )
        }
    }
    
    private func handleMeltCheckResults(
        paidEvents: [(Event, CashuSwift.Bolt11.MeltQuote, [CashuSwift.Proof]?)],
        pendingEvents: [Event],
        unpaidEvents: [Event],
        groupingID: UUID?
    ) {
        // If all events in a group are paid, handle success
        let totalEvents = paidEvents.count + pendingEvents.count + unpaidEvents.count
        
        if paidEvents.count == totalEvents && !paidEvents.isEmpty {
            // All paid - handle success
            handleRecoveredPaidEvents(paidEvents, groupingID: groupingID)
        } else if !pendingEvents.isEmpty {
            // Some are still pending - update action button
            actionButtonState = .idle("Payment Still Pending") {
                Task {
                    actionButtonState = .loading()
                    // Re-check the pending events
                    await checkPendingMeltEvents(pendingEvents)
                }
            }
        } else if !unpaidEvents.isEmpty && paidEvents.isEmpty {
            // All unpaid - allow retry
            prepareRetryForUnpaidEvents(unpaidEvents)
        } else {
            // Mixed results - this is complex, show status
            let paidCount = paidEvents.count
            let pendingCount = pendingEvents.count
            let unpaidCount = unpaidEvents.count
            
            displayAlert(alert: AlertDetail(
                title: "Mixed Payment Status",
                description: "Payment status: \(paidCount) paid, \(pendingCount) pending, \(unpaidCount) unpaid. Please handle manually."
            ))
            
            // Handle any paid events
            if !paidEvents.isEmpty {
                handleRecoveredPaidEvents(paidEvents, groupingID: groupingID)
            }
        }
    }
    
    private func handleRecoveredPaidEvents(
        _ paidEvents: [(Event, CashuSwift.Bolt11.MeltQuote, [CashuSwift.Proof]?)],
        groupingID: UUID?
    ) {
        guard let activeWallet else { return }
        
        do {
            // First, mark all proofs from pending events as spent
            // We need to find the actual proofs in the mint, not just the references in the event
            for (event, _, _) in paidEvents {
                if let eventProofs = event.proofs {
                    for eventProof in eventProofs {
                        // Find the actual proof in the mint by matching properties
                        if let mint = event.mints?.first,
                           let actualProof = mint.proofs?.first(where: { 
                               $0.C == eventProof.C && 
                               $0.secret == eventProof.secret &&
                               $0.keysetID == eventProof.keysetID
                           }) {
                            actualProof.state = .spent
                        }
                        // Also mark the event proof as spent
                        eventProof.state = .spent
                    }
                }
            }
            
            // Prepare data for success handler
            var mintsAndProofs: [(mint: Mint, quote: CashuSwift.Bolt11.MeltQuote, proofs: [Proof])] = []
            var meltResults: [(CashuSwift.Mint, CashuSwift.Bolt11.MeltQuote, [CashuSwift.Proof])] = []
            var pendingEventsToRemove: [Event] = []
            
            for (event, quote, change) in paidEvents {
                guard let mint = event.mints?.first,
                      let proofs = event.proofs else { continue }
                
                mintsAndProofs.append((mint, quote, proofs))
                meltResults.append((CashuSwift.Mint(mint), quote, change ?? []))
                pendingEventsToRemove.append(event)
            }
            
            // Use the existing success handler
            try handleSuccessfulMelt(
                mintsAndProofs: mintsAndProofs,
                meltResults: meltResults,
                activeWallet: activeWallet,
                shortDescription: "Payment",
                eventGroupingID: groupingID,
                pendingEvents: pendingEventsToRemove
            )
            
            // Don't show alert - success is indicated by action button
            // The handleSuccessfulMelt already sets success state and dismisses
        } catch {
            displayAlert(alert: AlertDetail(with: error))
        }
    }
    
    private func prepareRetryForUnpaidEvents(_ unpaidEvents: [Event]) {
        // Mark proofs as valid again for retry
        for event in unpaidEvents {
            event.proofs?.setState(.valid)
        }
        
        // Set action button to allow retry
        actionButtonState = .idle("Payment Failed - Retry") {
            // Allow user to retry the payment
            self.pendingMeltEvents = nil  // Clear pending events
            actionButtonState = .idle("Pay", action: initiateMelt)
        }
        
        // Hide the pending events instead of deleting to avoid view state inconsistencies
        for event in unpaidEvents {
            event.visible = false
        }
    }
    
    private func setupPendingEventsUI(_ events: [Event]) {
        // Extract invoice and mint selection from pending events
        if let firstEvent = events.first,
           let quote = firstEvent.bolt11MeltQuote {
            guard let invoiceString = quote.quoteRequest?.request else {
                fatalError()
            }
            
            self.invoiceString = invoiceString
            
            // Populate mint list with the invoice
            populateMintList(invoice: invoiceString)
            
            // Select the mints that were used in the pending events
            var mintsToSelect: Set<String> = []
            for event in events {
                if let mint = event.mints?.first {
                    if let mintInfo = mintRowInfoArray.first(where: { $0.mint.url == mint.url }) {
                        mintsToSelect.insert(mintInfo.id)
                    }
                }
            }
            selectedMintIds = mintsToSelect
            
            // Disable automatic selection and show static state
            automaticallySelected = false
            multiMintRequired = events.count > 1
            
            // Set action button to check payment status
            actionButtonState = .idle("Check Payment Status") {
                Task {
                    actionButtonState = .loading()
                    await checkPendingMeltEvents(events)
                }
            }
        }
    }
}

#Preview {
    MultiMeltView()
}
