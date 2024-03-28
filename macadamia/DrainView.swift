//
//  DrainView.swift
//  macadamia
//
//  Created by Dario Lass on 24.02.24.
//

import SwiftUI

struct DrainView: View {
    @ObservedObject var vm = DrainViewModel()
    
    var body: some View {
        List {
            Section {
                ForEach(vm.mintList, id: \.self) { mintURL in
                    Button(action: {
                        if !vm.selectedMints.contains(mintURL) {
                            vm.selectedMints.insert(mintURL)
                        } else {
                            vm.selectedMints.remove(mintURL)
                        }
                    }, label: {
                        HStack {
                            Text(mintURL)
                            Spacer()
                            if vm.selectedMints.contains(mintURL) {
                                Image(systemName: "checkmark")
                            } else {
                                Spacer(minLength: 30)
                            }
                        }
                    })
                }
            } header: {
                Text("Mints")
            } footer: {
                Text("Select all mints you would like to drain funds from.")
            }
            Section {
                Toggle("Multi mint token", isOn: $vm.makeTokenMultiMint)
                    .padding(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
            } footer: {
                Text("Some wallets may not be able to accept V3 tokens containing proofs from multiple mints.")
            }
            Section {
                Button {
                    vm.createBackupToken()
                } label: {
                    Text("Create Backup Token")
                }
//                Button(role: .destructive) {
//                    vm.createBackupToken()
//                    vm.resetWallet()
//                } label: {
//                    Text("Create Backup Token and Reset Wallet")
//                }
            }
            .disabled(vm.selectedMints.isEmpty)
            
        }
        .onAppear() {
            vm.loadMintList()
        }
    }
}

#Preview {
    DrainView()
}

@MainActor
class DrainViewModel: ObservableObject {
    
    var wallet = Wallet.shared
    
    @Published var mintList = [String]()
    @Published var selectedMints:Set<String> = []
    
    @Published var makeTokenMultiMint = false
    
    func loadMintList() {
        mintList = []
        for mint in wallet.database.mints {
            mintList.append(mint.url.absoluteString)
        }
        selectedMints = Set(mintList)
    }
    
    func createBackupToken() {
        
    }
    
}
