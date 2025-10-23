//
//  PendingTransferView.swift
//  macadamia
//
//  Created by zm on 21.10.25.
//

import SwiftUI
import SwiftData

struct TransferView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]
    
    @State private var showAlert = false
    @State private var currentAlert: AlertDetail?
    
    private var activeWallet: Wallet? {
        wallets.first
    }
    
    private var mints: [Mint] {
        activeWallet?.mints.filter({ $0.hidden == false })
            .sorted { ($0.userIndex ?? Int.max) < ($1.userIndex ?? Int.max) } ?? []
    }
    
    var body: some View {
        
    }
}

struct SectionOverlayTest: View {
    var body: some View {
        List {
            Section {
                TransferMintLabel(from: "mint.coinos.io", to: "mint.macadamia.cash")
                    .listRowBackground(EmptyView())
                    .listRowInsets(EdgeInsets())
            } header: {
                Text("MInts")
            }
            Section {
                Text("this")
            } header: {
                Text("header")
            }
        }
    }
}

struct TransferMintLabel: View {
    let from:   String
    let to:     String
    
    var body: some View {
        Group {
            VStack(alignment: .leading) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("From")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text(from)
                    }
                    Spacer()
                }
                LinearGradient(colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.3), Color.clear],
                               startPoint: .leading,
                               endPoint: .trailing)
                .frame(height: 0.5)
                .padding(.vertical, 4)
                HStack {
                    VStack(alignment: .leading) {
                        Text("To")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text(to)
                    }
                }
            }
        }
        .padding(EdgeInsets(top: 12, leading: 18, bottom: 12, trailing: 18))
        .overlay(alignment: .trailing) {
            Image(systemName: "arrow.down")
                .font(.title)
                .foregroundStyle(.secondary)
                .shadow(color: .secondary, radius: 10)
//                .bold()
                .padding()
        }
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(Color(uiColor: .secondarySystemGroupedBackground)))
    }
}

#Preview {
    SectionOverlayTest()
}
