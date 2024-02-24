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
                ForEach(vm.mintList, id: \.self) { mint in
                    Text(mint)
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
                Text("description")
            }
            Section {
                Button {
                    vm.createBackupToken()
                } label: {
                    Text("Create Backup Token")
                }
                Button(role: .destructive) {
                    vm.createBackupToken()
                    vm.resetWallet()
                } label: {
                    Text("Create Backup Token and Reset Wallet")
                }
            }
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
    
    @Published var mintList = [""]
    @Published var selectedMintList = []
    
    @Published var makeTokenMultiMint = false
    
    func loadMintList() {
        mintList = []
        for mint in wallet.database.mints {
            let readable = mint.url.absoluteString.dropFirst(8)
            mintList.append(String(readable))
        }
    }
    
    func createBackupToken() {
        
    }
    
    func resetWallet() {
        
    }
}
