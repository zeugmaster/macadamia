//
//  DrainView.swift
//  macadamia
//
//  Created by zeugmaster on 24.02.24.
//

import SwiftUI

struct DrainView: View {
    @ObservedObject var vm = DrainViewModel()
    
    var body: some View {
        List {
            if vm.tokens.isEmpty {
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
                                Text(mintURL.dropFirst(8))
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
                    Button(role:.destructive) {
                        vm.createBackupToken()
                    } label: {
                        Text("Create Drain Token")
                    }
                } footer: {
                    Text("Create a token that contains all proofs of the selected mints. WARNING: This will remove the proofs from the wallet database.")
                }
                .disabled(vm.selectedMints.isEmpty)
            } else {
                ForEach(vm.tokens) { token in
                    Section {
                        TokenView(token: token)
                    }
                }
                Section {
                    Button(action: {
                        vm.reset()
                    }, label: {
                        HStack {
                            Text("Reset")
                            Spacer()
                            Image(systemName: "arrow.circlepath")
                        }
                    })
                }
            }
        }
        .onAppear() {
            vm.loadMintList()
        }
        .alert(vm.currentAlert?.title ?? "Error", isPresented: $vm.showAlert) {
            Button(role: .cancel) {
                
            } label: {
                Text(vm.currentAlert?.primaryButtonText ?? "OK")
            }
            if vm.currentAlert?.onAffirm != nil &&
                vm.currentAlert?.affirmText != nil {
                Button(role: .destructive) {
                    vm.currentAlert!.onAffirm!()
                } label: {
                    Text(vm.currentAlert!.affirmText!)
                }
            }
        } message: {
            Text(vm.currentAlert?.alertDescription ?? "")
        }
    }
}

struct TokenView:View {
    var token:TokenInfo
    @State private var didCopy = false
    
    init(token: TokenInfo) {
        self.token = token
    }
    
    var body: some View {
        Group {
            Text(token.token)
                .fontDesign(.monospaced)
                .lineLimit(1)
            HStack {
                Text("Amount: ")
                Spacer()
                Text("\(token.amount) sat")
            }
            HStack {
                Text("Mint: ")
                Spacer()
                Text(token.mint)
            }
        }
        .foregroundStyle(.secondary)
        Button {
            copyToClipboard(token: token.token)
        } label: {
            HStack {
                if didCopy {
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
    
    func copyToClipboard(token:String) {
        UIPasteboard.general.string = token
        withAnimation {
            didCopy = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                didCopy = false
            }
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
    @Published var tokens = [TokenInfo]()
    @Published var makeTokenMultiMint = false
    
    @Published var showAlert:Bool = false
    var currentAlert:AlertDetail?
    
    func loadMintList() {
        print("Drain View: loaded mint list")
        mintList = []
        for mint in wallet.database.mints {
            mintList.append(mint.url.absoluteString)
        }
        selectedMints = Set(mintList)
    }
    
    init() {
        print("Drain View: initialized view model")
    }
    
    func createBackupToken() {
        do {
            guard !wallet.database.proofs.isEmpty else {
                displayAlert(alert: AlertDetail(title: "Empty Wallet", 
                                                description: "No drain token can be created from an empty wallet."))
                return
            }
            let tokens = try wallet.drainWallet(multiMint: makeTokenMultiMint)
            self.tokens = tokens.map({ (token: String, mintID: String, sum: Int) in
                let t = Transaction(timeStamp: ISO8601DateFormatter().string(from: Date()),
                                    unixTimestamp: Date().timeIntervalSince1970,
                                    amount: sum,
                                    type: .drain,
                                    token: token)
                wallet.database.transactions.insert(t, at: 0)
                return TokenInfo(token: token, mint: mintID, amount: sum)
            })
        } catch {
            displayAlert(alert: AlertDetail(title: "Draining Wallet unsuccessful", 
                                            description: String(describing: error)))
        }
    }
    
    func reset() {
        tokens = []
    }
    
    private func displayAlert(alert:AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}

struct TokenInfo:Identifiable, Hashable {
    let token:String
    let mint:String
    let amount:Int
    
    var id: String { token }
}
