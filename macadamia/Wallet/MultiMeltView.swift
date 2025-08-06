//
//  MultiMeltView.swift
//  macadamia
//
//  Created by zm on 28.07.25.
//

import SwiftUI
import SwiftData
import CashuSwift

struct MintRowInfo: Identifiable {
    let id = UUID()
    let mint: Mint
    var partialAmount: Int = 0
    var fee: Int?
    var quote: CashuSwift.Bolt11.MeltQuote?
    
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
    
//    @Query private var mints: [Mint]
    
    @State private var actionButtonState: ActionButtonState = .idle("Scan or paste invoice")
    @State private var invoiceString: String?
    @State private var mintRowInfoArray: [MintRowInfo] = []
    
    @State private var mintListEditing = false
    @State private var multiMintRequired: Bool = false
    @State private var automaticallySelected: Bool = false
    
    @State private var selectedMintIds: Set<UUID> = []
    
    @State private var showAlert: Bool = false
    @State private var currentAlert: AlertDetail?
    @State private var showMintSelector: Bool = false
    @State private var insufficientFundsError: String? = nil
    @State private var scannerResetID = UUID() // Used to force InputView recreation on reset
    
    init(pendingMeltEvent: Event? = nil, invoice: String? = nil) {
        // Initialization logic here
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
                            autoSelectMintsAndFetchQuotes()
                            actionButtonState = .idle("Pay", action: startMelt)
                        }
                        .onChange(of: insufficientFundsError) { _, newValue in
                            if newValue != nil {
                                actionButtonState = .idle("Insufficient Funds")
                            } else if !selectedMintIds.isEmpty {
                                actionButtonState = .idle("Pay", action: startMelt)
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
                                        if !selectedMintIds.isEmpty {
                                            Text(mintSelectionDetails)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
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
                            .disabled(insufficientFundsError != nil)
                            
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
                    .actionDisabled(insufficientFundsError != nil || invoiceString == nil)
            }
        }
        .alertView(isPresented: $showAlert, currentAlert: currentAlert)
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
        let selectedMints = mintRowInfoArray.filter { selectedMintIds.contains($0.id) }
        let totalBalance = selectedMints.map { $0.balance }.reduce(0, +)
        let totalFees = selectedMints.compactMap { $0.fee }.reduce(0, +)
        
        if totalFees > 0 {
            return "Balance: \(totalBalance) sats • Total fees: \(totalFees) sats"
        } else {
            return "Balance: \(totalBalance) sats"
        }
    }
    
    @ViewBuilder
    private func mintRowView(for mintInfo: MintRowInfo, invoiceAmount: Int) -> some View {
        let canPayFull = mintInfo.balance >= invoiceAmount
        let supportsMPP = mintInfo.mint.supportsMPP
        let isDisabled = !canPayFull && !supportsMPP
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
        let filteredMints = activeWallet?.mints.filter({ ($0.balance(for: .sat) > 0 && $0.supportsMPP) || $0.balance(for: .sat) > amount })
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
    
    private func toggleSelection(for id: UUID) {
        // Mark that user has manually changed selection
        automaticallySelected = false
        // Clear any error when user takes control
        insufficientFundsError = nil
        
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
        if selectedMintIds.isEmpty { return }
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

        var list: [(UUID, CashuSwift.Mint, Int)] = []
        for (index, info) in shares.enumerated() {
            let extraSat = sorted.prefix(remainder).map(\.offset).contains(index) ? 1 : 0
            let sats = info.floorPart + extraSat
            let msats = sats * 1_000
            list.append((info.row.id, CashuSwift.Mint(info.row.mint), msats))
        }

        Task {
            do {
                let quotes = try await loadQuotes(for: list, invoice: invoiceString)
                await MainActor.run {
                    for quote in quotes {
                        guard let i = mintRowInfoArray.firstIndex(where: { $0.id == quote.0 }) else { continue }
                        mintRowInfoArray[i].quote = quote.1
                        mintRowInfoArray[i].partialAmount = Int(quote.2 / 1000)
                        mintRowInfoArray[i].fee = quote.1.feeReserve
                    }
                }
            } catch {
                print("error fetching quotes: \(error)")
            }
        }
    }

    
    private func loadQuotes(for list: [(id: UUID, mint: CashuSwift.Mint, amount: Int)],
                              invoice: String) async throws -> [(UUID, CashuSwift.Bolt11.MeltQuote, Int)] {
        var quotes: [(UUID, CashuSwift.Bolt11.MeltQuote, Int)] = []
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
            }
        }
        return quotes
    }
    
    
    private func startMelt() {
        // skip pending mint events for now
        guard let activeWallet else {
            return
        }
        
        let selectedMintsInfo = mintRowInfoArray.filter({ selectedMintIds.contains($0.id) })
        guard !selectedMintsInfo.isEmpty else { return }
        
        actionButtonState = .loading()
        
        // select mints and store proofs for potential rollback
        let mintsAndProofs = selectedMintsInfo.map { row in
            guard let selected = row.mint.select(amount: row.partialAmount + (row.fee ?? 0), unit: .sat) else {
                fatalError()
            }
            selected.selected.setState(.pending)
            guard let quote = row.quote else {
                fatalError()
            }
            return (mint: row.mint, quote: quote, proofs: selected.selected)
        }
        
        
        let taskGroupInputs = mintsAndProofs.map { entry in
            (CashuSwift.Mint(entry.mint), entry.quote, entry.proofs.sendable())
        }
        
        Task {
            do {
                try await withThrowingTaskGroup(of: (CashuSwift.Mint, [CashuSwift.Proof]).self) { group in
                    for input in taskGroupInputs {
                        group.addTask {
                            let change = try await melt(with: input.1, on: input.0, proofs: input.2)
                            return (input.0, change)
                        }
                    }
                    var results: [(CashuSwift.Mint, [CashuSwift.Proof])] = []
                    for try await result in group {
                        results.append(result)
                    }
                    
                    // return to main thread with change and save, mark inputs as spent
                    try await MainActor.run {
                        // Mark all used proofs as spent
                        for entry in mintsAndProofs {
                            entry.proofs.setState(.spent)
                        }
                        
                        // Add change proofs
                        for result in results {
                            if let internalMint = activeWallet.mints.first(where: { $0.url == result.0.url }) { // FIXME: DO NOT MATCH MINTS BY URL
                                try internalMint.addProofs(result.1,
                                                           to: modelContext,
                                                           unit: .sat) // TODO: remove hard coded unit
                            }
                        }
                        actionButtonState = .success()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            dismiss()
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    // Revert all selected proofs back to valid state
                    for entry in mintsAndProofs {
                        entry.proofs.setState(.valid)
                    }
                    
                    displayAlert(alert: AlertDetail(with: error))
                    actionButtonState = .fail()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        actionButtonState = .idle("Pay", action: startMelt)
                    }
                }
            }
        }
    }
    
    // as simple as possible, non-det change outputs
    private func melt(with quote: CashuSwift.Bolt11.MeltQuote,
                      on mint: CashuSwift.Mint,
                      proofs: [CashuSwift.Proof]) async throws -> [CashuSwift.Proof] {
        let blankOutputs = try CashuSwift.generateBlankOutputs(quote: quote, proofs: proofs, mint: mint, unit: "sat", seed: activeWallet?.seed)
        return try await CashuSwift.melt(with: quote, mint: mint, proofs: proofs, blankOutputs: blankOutputs).change ?? []
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
}

#Preview {
    MultiMeltView()
}
