//
//  MnemonicView.swift
//  macadamia
//
//  Created by zeugmaster on 04.01.24.
//

import BIP39
import SwiftData
import SwiftUI

struct MnemonicView: View {
    @State var mnemonic = [String]()
    @State var mintList = [String]()

    @Environment(\.modelContext) private var modelContext
    @Query private var wallets: [Wallet]

    var activeWallet: Wallet? {
        wallets.first
    }

    func loadData() {
        guard let activeWallet else {
            return
        }
        if let seed = activeWallet.seed,
           let mnemo = try? Mnemonic(entropy: seed.bytes).phrase
        {
            mnemonic = mnemo
        }
        mintList = activeWallet.mints.map { $0.url.absoluteString }
    }

    func copyMnemonic() {
        UIPasteboard.general.string = mnemonic.joined(separator: " ")
    }

    @State private var isCopied = false

    var body: some View {
        List {
            Section {
                ForEach(mnemonic, id: \.self) { word in
                    Text(word)
                }
                .disabled(true)
                .foregroundStyle(.secondary)
            } header: {
                Text("12 Word backup seed phrase")
            }
            Section {
                Button {
                    copyToClipboard()
                } label: {
                    HStack {
                        if isCopied {
                            Text("Copied!")
                                .transition(.opacity)
                        } else {
                            Text("Copy to clipboard")
                                .transition(.opacity)
                        }
                        Spacer()
                        Image(systemName: "list.clipboard")
                    }
                }
            }
            Section {
                ForEach(mintList, id: \.self) { mintURL in
                    Text(mintURL)
                }
                .disabled(true)
                .foregroundStyle(.secondary)
            } footer: {
                Text("macadamia can only restore eCash from the mints it knows about. It would be wise to include their URLs in the backup of your seed phrase.")
            }
        }
        .onAppear(perform: loadData)
    }

    func copyToClipboard() {
        // Perform the actual copy operation here
        copyMnemonic()

        // Change button text with animation
        withAnimation {
            isCopied = true
        }

        // Revert button text after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isCopied = false
            }
        }
    }
}

#Preview {
    MnemonicView()
}
