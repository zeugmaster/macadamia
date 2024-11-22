//
//  WalletInfoListView.swift
//  macadamia
//
//  Created by zm on 22.11.24.
//

import SwiftUI
import SwiftData

struct WalletInfoListView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Query private var wallets: [Wallet]
    
    var body: some View {
        List {
            ForEach(wallets) { wallet in
                Section {
                    HStack {
                        Text("Created at: ")
                        Spacer()
                        Text(wallet.dateCreated.formatted())
                    }
                    Text("Mnemonic: \(wallet.mnemonic)")
                    if let seed = wallet.seed {
                        Text("Seed hex: ...\(seed.dropFirst(seed.count - 16))")
                    }
                    Text("Name: \(wallet.name ?? "nil")")
                    Text("ID: \(wallet.walletID)")
                    Text("Mints: \(wallet.mints.count), Proofs: \(wallet.proofs?.count ?? 0)")
                }
            }
        }
    }
}

