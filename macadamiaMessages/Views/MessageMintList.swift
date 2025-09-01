//
//  MessageMintList.swift
//  macadamiaMessages
//
//  Created by zm on 01.09.25.
//

import SwiftUI
import SwiftData

struct MessageMintList: View {
    weak var delegate: MessagesViewController?
    var mint: Mint?
    
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]
    
    private var activeWallet: Wallet? {
        wallets.first
    }
    
    private var mints: [Mint] {
        activeWallet?.mints.filter({ $0.hidden == false })
            .sorted { ($0.userIndex ?? Int.max) < ($1.userIndex ?? Int.max) } ?? []
    }

    var body: some View {
        List {
            Section {
                ForEach(mints) { mint in
                    NavigationLink(destination: MessageSendView(mint: mint)) {
                        MintRow(mint: mint)
                    }
                }
            } header: {
                Text("Pay from")
            }
        }
    }
}

struct MintRow: View {
    let mint: Mint
    
    var body: some View {
        HStack {
            Text(mint.displayName)
            Spacer()
            Text(amountDisplayString(mint.balance(for: .sat), unit: .sat))
                .monospaced()
        }
        .bold()
    }
}

struct MessageSendView: View {
    let mint: Mint
    
    var body: some View {
        Text("Send from \(mint.displayName)")
    }
}

