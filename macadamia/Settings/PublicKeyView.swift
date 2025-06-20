//
//  PublicKeyView.swift
//  macadamia
//
//  Created by zm on 20.05.25.
//

import SwiftUI
import SwiftData
import secp256k1

struct PublicKeyView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]

    var activeWallet: Wallet? {
        wallets.first
    }
    
    @State private var hexString: String? = nil
    @State private var copied = false
    
    var body: some View {
        List {
            if let hexString {
                Section {
                    QRView(string: hexString)
                        .listRowBackground(EmptyView())
                }
                Section {
                    HStack {
                        Text(copied ? "Copied!" : hexString)
                            .lineLimit(1)
                            .monospaced()
                        Spacer()
                        Button {
                            if copied { return }
                            
                            UIPasteboard.general.string = hexString
                            
                            withAnimation {
                                copied = true
                            }
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation {
                                    copied = false
                                }
                            }
                        } label: {
                            Image(systemName: "clipboard")
                        }
                    }
                }
            } else {
                Text("No data.")
                    .monospaced()
            }
        }
        .onAppear {
            if let wallet = activeWallet {
                if let privateKeyData = wallet.privateKeyData,
                   let key = try? secp256k1.Signing.PrivateKey(dataRepresentation: privateKeyData) {
                    hexString = String(bytes: key.publicKey.dataRepresentation)
                } else {
                    logger.info("No Schnorr P2PK key set for wallet, creating new...")
                    if let key = try? secp256k1.Signing.PrivateKey() {
                        wallet.privateKeyData = key.dataRepresentation
                        try? modelContext.save()
                        hexString = String(bytes: key.publicKey.dataRepresentation)
                        logger.debug("...key created and saved.")
                    }
                }
            }
        }
    }
}

