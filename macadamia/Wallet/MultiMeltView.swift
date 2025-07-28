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
    
    @Query private var mints: [Mint]
    
    @State private var actionButtonState: ActionButtonState = .idle("No State")
    @State private var invoiceString: String?
    @State private var mintRowInfoArray: [MintRowInfo] = []
    
    @State private var selectedMintIds: Set<UUID> = []
    
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
                    }
                    
                    Section {
                        mintList
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
            }
        }
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
                    
                    Group {
                        if let quote = mintInfo.quote {
                            Text(quote.quote)
                        } else {
                            Text("No quote")
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
        mintRowInfoArray = mints.filter({ ($0.balance(for: .sat) > 0 && $0.supportsMPP) || $0.balance(for: .sat) > amount })
            .map({ mint in
                MintRowInfo(mint: mint)
            })
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
        if selectedMintIds.count == 0 { return }
        
        guard let invoiceString, let total = try? CashuSwift.Bolt11.satAmountFromInvoice(pr: invoiceString.lowercased()) else { return }
        
        var list: [(UUID, CashuSwift.Mint, Int)] = []
        
        let selected = mintRowInfoArray.filter({ selectedMintIds.contains($0.id) })
        let totalBalance = selected.map({ $0.mint.balance(for: .sat) }).reduce(0, +)
        for row in selected {
            let amountPerMint = row.mint.balance(for: .sat) / totalBalance * total
            list.append((row.id, CashuSwift.Mint(row.mint), amountPerMint))
        }
        Task {
            do {
                let quotes = try await loadInvoices(for: list, invoice: invoiceString)
                await MainActor.run {
                    for quote in quotes {
                        guard let i = mintRowInfoArray.firstIndex(where: { $0.id == quote.0 }) else { continue }
                        mintRowInfoArray[i].quote = quote.1
                    }
                }
            } catch {
                print("error fetching quotes: \(error)")
            }
        }
    }
    
    private func loadInvoices(for list: [(id: UUID, mint: CashuSwift.Mint, amount: Int)], invoice: String) async throws -> [(UUID, CashuSwift.Bolt11.MeltQuote, Int)] {
        var quotes: [(UUID, CashuSwift.Bolt11.MeltQuote, Int)] = []
        for entry in list {
            let options = CashuSwift.Bolt11.RequestMeltQuote.Options(mpp: CashuSwift.Bolt11.RequestMeltQuote.Options.MPP(amount: entry.amount))
            let request = CashuSwift.Bolt11.RequestMeltQuote(unit: "sat",
                                                             request: invoice,
                                                             options: list.count < 2 ? nil : options)
            guard let quote = try await CashuSwift.getQuote(mint: entry.mint,
                                                            quoteRequest: request) as? CashuSwift.Bolt11.MeltQuote else {
                fatalError("quote request returned unexpected type")
            }
            quotes.append((entry.id, quote, entry.amount))
        }
        return quotes
    }
    
    
    private func startMelt() {
//        let selectedMintData = selectedMints
//        // Process the selected mints
//        print("Starting melt for \(selectedMintData.count) selected mints")
    }
}

#Preview {
    MultiMeltView()
}
