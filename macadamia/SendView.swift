//
//  SendView.swift
//  macadamia
//
//  Created by zeugmaster on 04.01.24.
//

import SwiftUI

struct SendView: View {
    
    @ObservedObject var vm = SendViewModel()
    @State private var isCopied = false
    
    @FocusState var amountFieldInFocus:Bool
    
    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("enter amount", text: $vm.numberString)
                        .keyboardType(.numberPad)
                        .monospaced()
                        .focused($amountFieldInFocus)
                    Text("sats")
                }
                Picker("Mint", selection:$vm.selectedMintString) {
                    ForEach(vm.mintList, id: \.self) {
                        Text($0)
                    }
                }
                .onAppear(perform: {
                    vm.fetchMintInfo()
                })
                .onChange(of: vm.selectedMintString) { oldValue, newValue in
                    vm.updateBalance()
                }
                HStack {
                    Text("Balance: ")
                    Spacer()
                    Text(String(vm.selectedMintBalance))
                        .monospaced()
                    Text("sats")
                }
                .foregroundStyle(.secondary)
            }
            .disabled(vm.token != nil)
            Section {
                TextField("enter note", text: $vm.tokenMemo)
            } footer: {
                Text("Tap to add a note to the recipient.")
            }
            .disabled(vm.token != nil)
            
            if vm.token != nil {
                Section {
                    TokenText(text: vm.token!)
                        .frame(idealHeight: 70)
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
                    
                    Button {
                        vm.showingShareSheet = true
                    } label: {
                        HStack {
                            Text("Share")
                            Spacer()
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
                Section {
                    QRView(string: vm.token!)
                } header: {
                    Text("Share via QR code")
                }
            }
        }
        .navigationTitle("Send")
        .navigationBarTitleDisplayMode(.inline)
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
        .onAppear(perform: {
            amountFieldInFocus = true
        })
        
        Spacer()
        
        Button(action: {
            vm.generateToken()
        }, label: {
            Text("Generate Token")
                .frame(maxWidth: .infinity)
                .padding()
                .bold()
                .foregroundColor(.white)
        })
        .buttonStyle(.bordered)
        .padding()
        .toolbar(.hidden, for: .tabBar)
        .disabled(vm.numberString.isEmpty || vm.amount == 0 || vm.token != nil)
        .sheet(isPresented: $vm.showingShareSheet, content: {
            ShareSheet(items: [vm.token ?? "No token provided"])
        })

    }
    
    func copyToClipboard() {
        vm.copyToClipboard()
        withAnimation {
            isCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isCopied = false
            }
        }
    }
    
}

#Preview {
    SendView()
}

@MainActor
class SendViewModel: ObservableObject {
    
    @Published var recipientProfile:Profile?
    
    @Published var showingShareSheet = false
    @Published var tokenMemo = ""
    
    @Published var numberString: String = ""
    @Published var mintList:[String] = [""]
    @Published var selectedMintString:String = ""
    @Published var selectedMintBalance = 0
    
    @Published var loading = false
    @Published var succes = false
    
    @Published var showAlert:Bool = false
    var currentAlert:AlertDetail?
    var wallet = Wallet.shared
    
    @Published var token:String?
    
    func fetchMintInfo() {
        mintList = []
        for mint in wallet.database.mints {
            let readable = mint.url.absoluteString.dropFirst(8)
            mintList.append(String(readable))
        }
        selectedMintString = mintList[0]
    }
    
    func updateBalance() {
        if let mint = wallet.database.mints.first(where: { $0.url.absoluteString.contains(selectedMintString) }) {
            selectedMintBalance = wallet.balance(mint: mint)
        }
    }
    
    var amount: Int {
        return Int(numberString) ?? 0
    }
    
    func generateToken() {
        print(selectedMintString)
        guard let mint = wallet.database.mints.first(where: { $0.url.absoluteString.contains(selectedMintString) }) else {
            displayAlert(alert: AlertDetail(title: "Invalid Mint"))
            return
        }
        Task {
            do {
                self.token = try await wallet.sendTokens(from:mint, amount: amount, memo:tokenMemo)
            } catch {
                displayAlert(alert: AlertDetail(title: "Error", description: String(describing: error)))
            }
        }
    }
    
    func copyToClipboard() {
        UIPasteboard.general.string = token
    }
    
    private func displayAlert(alert:AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}
