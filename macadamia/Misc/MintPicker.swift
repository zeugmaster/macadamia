//
//  MintPicker.swift
//  macadamia
//
//  Created by zm on 01.11.24.
//

import SwiftUI
import SwiftData

struct MintPicker: View {
    @Query(sort: [SortDescriptor(\Mint.userIndex, order: .forward)]) private var mints: [Mint]
    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]
    
    var label: String
    @Binding var selectedMint:Mint?
    
    @State private var mintNamesAndIDs = [(name: String, id: UUID)]()
    @State private var selectedID = UUID()
    
    var activeWallet: Wallet? {
        wallets.first
    }
    
    var sortedMintsOfActiveWallet: [Mint] {
        mints.filter({ $0.wallet == activeWallet })
             .sorted(by: { $0.userIndex ?? 0 < $1.userIndex ?? 0})
    }
        
    var body: some View {
        Group {
            if mintNamesAndIDs.isEmpty {
                Text("No mints yet.")
            } else {
                Picker(label, selection: $selectedID) {
                    ForEach(mintNamesAndIDs, id: \.id) { entry in
                        Text(entry.name)
                    }
                }
            }
        }
        .onAppear {
            populate()
            if let selectedMint = selectedMint {
                selectedID = selectedMint.mintID
            } else if let first = mintNamesAndIDs.first {
                selectedID = first.id
                selectedMint = sortedMintsOfActiveWallet.first(where: { $0.mintID == selectedID })
            }
        }
        .onChange(of: selectedID) { oldValue, newValue in
            selectedMint = sortedMintsOfActiveWallet.first(where: { $0.mintID == newValue })
        }
        .onChange(of: selectedMint) { oldValue, newValue in
            if let newMint = newValue {
                selectedID = newMint.mintID
            }
        }
    }
    
    func populate() {
        mintNamesAndIDs = sortedMintsOfActiveWallet.map( { mint in
            (mint.displayName, mint.mintID)
        })
        if let first = mintNamesAndIDs.first {
            selectedID = first.id
        }
    }
}

//#Preview {
//    MintPicker()
//}
