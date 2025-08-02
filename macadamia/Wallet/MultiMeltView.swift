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
    
    @State private var actionButtonState: ActionButtonState = .idle("No State")
    @State private var invoiceString: String?
    @State private var mintRowInfoArray: [MintRowInfo] = []
    
    @State private var mintListEditing = false
    @State private var multiMintRequired: Bool = false
    @State private var automaticallySelected: Bool = false
    
    @State private var selectedMintIds: Set<UUID> = []
    
    @State private var showAlert: Bool = false
    @State private var currentAlert: AlertDetail?
    
    init(pendingMeltEvent: Event? = nil, invoice: String? = nil) {
        // Initialization logic here
    }
    
    var body: some View {
        ZStack {
            List {
                if let invoiceString {
                    Section {
                        Text(invoiceString)
                            .foregroundStyle(.gray)
                            .monospaced()
                            .lineLimit(1)
                    } header: {
                        Text("Invoice")
                    }
                    .onAppear {
                        populateMintList(invoice: invoiceString)
                        autoSelectMintsAndFetchQuotes()
                        actionButtonState = .idle("Pay", action: startMelt)
                    }
                    
                    Section {
                        mintList
                            .disabled(multiMintRequired && !mintListEditing)
                    } header: {
                        HStack {
                            Text("Pay from")
                            Spacer()
                            if multiMintRequired {
                                Button {
                                    mintListEditing.toggle()
                                } label: {
                                    Text(mintListEditing ? "Done" : "Edit")
                                        .font(.footnote)
                                }
                            }
                        }
                    }
                } else {
                    InputView(supportedTypes: [.bolt11Invoice]) { result in
                        guard result.type == .bolt11Invoice else { return }
                        invoiceString = result.payload
                    }
                    .listRowBackground(Color.clear)
                }
                
                Spacer(minLength: 50)
                    .listRowBackground(Color.clear)
            }
            
            VStack {
                Spacer()
                ActionButton(state: $actionButtonState)
                    .actionDisabled(false)
            }
        }
        .alertView(isPresented: $showAlert, currentAlert: currentAlert)
    }
    
    private var mintList: some View {
        ForEach(mintRowInfoArray) { mintInfo in
            HStack {
                Button {
                    // GENERAL PATTERN: Toggle selection using Set operations
                    toggleSelection(for: mintInfo.id)
                } label: {
                    Image(systemName: selectedMintIds.contains(mintInfo.id) ? "checkmark.circle.fill" : "circle")
                }
                
                VStack(alignment: .leading) {
                    HStack {
                        Text(mintInfo.mint.displayName)
                        Spacer()
                        Text(String(mintInfo.balance))
                            .monospaced()
                    }
                    
                    HStack {
                        if let quote = mintInfo.quote {
                            Text(quote.quote.prefix(10) + "...")
                        } else {
                            Text("No quote")
                        }
                        Spacer()
                        if let fee = mintInfo.fee {
                            Text("Fee: \(fee)")
                            Text("Amount: \(mintInfo.partialAmount)")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    private func populateMintList(invoice: String) {
        let amount = (try? CashuSwift.Bolt11.satAmountFromInvoice(pr: invoice.lowercased())) ?? 0
        mintRowInfoArray = activeWallet?.mints.filter({ ($0.balance(for: .sat) > 0 && $0.supportsMPP) || $0.balance(for: .sat) > amount })
            .map({ mint in
//                print("mint list entry: \(mint.url.absoluteString), of wallet: \(String(describing: mint.wallet?.walletID))")
                return MintRowInfo(mint: mint)
            }) ?? []
    }
    
    // GENERAL SELECTION METHODS:
    
    private func toggleSelection(for id: UUID) {
        if selectedMintIds.contains(id) {
            selectedMintIds.remove(id)
        } else {
            selectedMintIds.insert(id)
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
        print("starting mint...")
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
                            print("created change: \(change)")
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
                    }
                }
            } catch {
                await MainActor.run {
                    print("failed due to error \(error)")
                    
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
        
        // Check if any single mint can pay the full amount
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
                displayAlert(alert: AlertDetail(
                    title: "Insufficient Funds",
                    description: "Not enough balance across MPP-supporting mints to pay this invoice."
                ))
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
