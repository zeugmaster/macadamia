//
//  MnemonicView.swift
//  macadamia
//
//  Created by zeugmaster on 04.01.24.
//

import SwiftUI

struct MnemonicView: View {
    @ObservedObject var vm = MnemonicViewModel()
    
    @State private var isCopied = false
    
    var body: some View {
        List {
            Section {
                ForEach(vm.mnemonic, id: \.self) { word in
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
                ForEach(vm.mintList, id: \.self) { mintURL in
                    Text(mintURL)
                }
                .disabled(true)
                .foregroundStyle(.secondary)
            } footer: {
                Text("macadamia can only restore eCash from the mints it knows about. It would be wise to include their URLs in the backup of your seed phrase.")
            }
        }
        .onAppear(perform: vm.loadData)
    }
    
    func copyToClipboard() {
        // Perform the actual copy operation here
        vm.copyMnemonic()

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

class MnemonicViewModel: ObservableObject {
    
    var wallet = Wallet.shared
    
    @Published var mnemonic = [String]()
    @Published var mintList = [String]()
    
    init(wallet: Wallet = Wallet.shared, 
         mnemonic: [String] = [String](),
         mintList: [String] = [String]()) {
        self.wallet = wallet
        self.mnemonic = mnemonic
        self.mintList = mintList
    }
    
    func loadData() {
        if let mnemo = wallet.database.mnemonic {
            mnemonic = mnemo.components(separatedBy: " ")
        }
        mintList = wallet.database.mints.map( { $0.url.absoluteString } )
    }
    
    func copyMnemonic() {
        UIPasteboard.general.string = wallet.database.mnemonic
    }
    
}

#Preview {
    MnemonicView()
}
