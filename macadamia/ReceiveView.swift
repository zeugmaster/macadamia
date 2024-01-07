//
//  ReceiveView.swift
//  macadamia
//
//  Created by Dario Lass on 05.01.24.
//

import SwiftUI

struct ReceiveView: View {
    @ObservedObject var vm = ReceiveViewModel()
    
    var body: some View {
        VStack {
            List {
                Section {
                    if vm.token != nil {
                        Text(vm.token!)
                            .lineLimit(5, reservesSpace: true)
                            .monospaced()
                            .foregroundStyle(.secondary)
                            .disableAutocorrection(true)
                        HStack {
                            Text("Amount: ")
                            Spacer()
                            Text(String(vm.tokenAmount ?? 0) + " sats")
                        }
                        .foregroundStyle(.secondary)
                        if vm.tokenMemo != nil {
                            if !vm.tokenMemo!.isEmpty {
                                Text("Memo: \(vm.tokenMemo!)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text("Mint: \(vm.mintURL ?? "")")
                            .foregroundStyle(.secondary)
                        if vm.unknownMint {
                            Button {
                                vm.addUnkownMint()
                            } label: {
                                HStack {
                                    Text("Unknown mint. Add it?")
                                    Spacer()
                                    Image(systemName: "plus")
                                }
                            }
                        }
                        Button {
                            vm.reset()
                        } label: {
                            HStack {
                                Text("Reset")
                                Spacer()
                                Image(systemName: "trash")
                            }
                        }
                    } else {
                        Button {
                            vm.paste()
                        } label: {
                            HStack {
                                Text("Paste from clipboard")
                                Spacer()
                                Image(systemName: "list.clipboard")
                            }
                        }
                    }
                    
                } header: {
                     Text("cashu Token")
                }
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
            .navigationTitle("Receive")
            .toolbar(.hidden, for: .tabBar)
            
            Button(action: {
                vm.redeem()
            }, label: {
                if vm.loading {
                    Text("Sending...")
                        .frame(maxWidth: .infinity)
                        .padding()
                } else if vm.success {
                    Text("Done!")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .foregroundColor(.green)
                } else {
                    Text("Redeem")
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            })
            .foregroundColor(.white)
            .buttonStyle(.bordered)
            .padding()
            .bold()
            .toolbar(.hidden, for: .tabBar)
            .disabled(vm.token == nil || vm.loading || vm.success)
        }
    }
}

#Preview {
    ReceiveView()
}

@MainActor
class ReceiveViewModel: ObservableObject {
    
    @Published var token:String?
    @Published var tokenMemo:String?
    @Published var mintURL:String?
    @Published var loading = false
    @Published var success = false
    @Published var tokenAmount:Int?
    @Published var unknownMint = false
    
    @Published var showAlert:Bool = false
    var currentAlert:AlertDetail?
    var wallet = Wallet.shared
    
    func paste() {
        let pasteString = UIPasteboard.general.string ?? ""
        guard let deserialized = try? wallet.deserializeToken(token: pasteString) else {
            displayAlert(alert: AlertDetail(title: "Invalid token",
                                            description: "This token could not be read. Input: \(pasteString.prefix(20))..."))
            return
        }
        token = pasteString
        tokenMemo = deserialized.memo
        mintURL = deserialized.token.first?.mint
        tokenAmount = amountForToken(token: deserialized)
        
        unknownMint = !wallet.database.mints.contains(where: { $0.url.absoluteString.contains(mintURL ?? "unknown") })
    }
    
    func amountForToken(token:Token_Container) -> Int {
        var total = 0
        for proof in token.token.first!.proofs {
            total += proof.amount
        }
        return total
    }
    
    func addUnkownMint() {
        Task {
            guard let mintURL = mintURL, let url = URL(string: mintURL) else {
                return
            }
            try await wallet.addMint(with:url)
            unknownMint = false
        }
    }
    
    func redeem() {
        loading = true
        Task {
            do {
                try await wallet.receiveToken(tokenString: token!)
                self.loading = false
                self.success = true
            } catch {
                displayAlert(alert: AlertDetail(title: "Redeem failed",
                                               description: String(describing: error)))
                self.loading = false
                self.success = false
            }
        }
    }
    
    func reset() {
        token = nil
        tokenMemo = nil
        mintURL = nil
        tokenMemo = nil
        success = false
    }
    
    private func displayAlert(alert:AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}
