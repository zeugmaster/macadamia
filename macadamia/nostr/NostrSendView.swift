////
////  NostrSendView.swift
////  macadamia
////
////  Created by zeugmaster on 05.01.24.
////
//
//import SwiftUI
//
//
//struct NostrSendView: View {
//    
//    @ObservedObject var vm:NostrSendViewModel
//    @State private var isCopied = false
//    
//    init(nsvm:NostrSendViewModel) {
//        self.vm = nsvm
//    }
//    
//    var body: some View {
//        Form {
//            Section {
//                HStack {
//                    TextField("enter amount", text: $vm.numberString)
//                        .keyboardType(.numberPad)
//                        .monospaced()
//                    Text("sats")
//                }
//                Picker("Mint", selection:$vm.selectedMintString) {
//                    ForEach(vm.mintList, id: \.self) {
//                        Text($0)
//                    }
//                }.onAppear(perform: {
//                    vm.fetchMintInfo()
//                })
//            }
//            Section {
//                TextField("enter note", text: $vm.tokenMemo)
//            } footer: {
//                Text("Tap to add a note to the recipient.")
//            }
//            
//            
//        }
//        .navigationTitle("Send")
//        .navigationBarTitleDisplayMode(.inline)
//        .alertView(isPresented: $vm.showAlert, currentAlert: vm.currentAlert)
//        
//        Spacer()
//        
//        Button(action: {
//            vm.initiateSend()
//        }, label: {
//            if vm.loading {
//                Text("Sending...")
//                    .frame(maxWidth: .infinity)
//                    .padding()
//            } else if vm.success {
//                Text("Done!")
//                    .frame(maxWidth: .infinity)
//                    .padding()
//                    .foregroundColor(.green)
//            } else {
//                Group {
//                    Text("Send to ")
//                    + Text(vm.recipientDisplayName).underline()
//                    + Text(" via Nostr")
//                }
//                .frame(maxWidth: .infinity)
//                .padding()
//            }
//        })
//        .foregroundColor(.white)
//        .buttonStyle(.bordered)
//        .padding()
//        .bold()
//        .toolbar(.hidden, for: .tabBar)
//        .disabled(vm.numberString.isEmpty || vm.amount == 0 || vm.loading || vm.success)
//    }
//    
//    func copyToClipboard() {
//        withAnimation {
//            isCopied = true
//        }
//
//        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
//            withAnimation {
//                isCopied = false
//            }
//        }
//    }
//}
//
//@MainActor
//class NostrSendViewModel: ObservableObject {
//    
//    @Published var recipientProfile:Profile
//    @Published var tokenMemo = ""
//    
//    @Published var numberString: String = ""
//    @Published var mintList:[String] = [""]
//    @Published var selectedMintString:String = ""
//    
//    @Published var loading = false
//    @Published var success = false
//    
//    @Published var showAlert:Bool = false
//    var currentAlert:AlertDetail?
//    
//    var wallet = Wallet.shared
//    var nostrService = NostrService.shared
//    
//    init(recipientProfile:Profile) {
//        self.recipientProfile = recipientProfile
//    }
//    
//    var recipientDisplayName:String {
//        get {
//            if let name = recipientProfile.name {
//                return name
//            } else {
//                return String(recipientProfile.pubkey.prefix(10))
//            }
//        }
//    }
//    
//    func fetchMintInfo() {
//        mintList = []
//        for mint in wallet.database.mints {
//            let readable = mint.url.absoluteString.dropFirst(8)
//            mintList.append(String(readable))
//        }
//        selectedMintString = mintList[0]
//    }
//    
//    var amount: Int {
//        return Int(numberString) ?? 0
//    }
//    
//    func initiateSend() {
//        print(selectedMintString)
//        guard let mint = wallet.database.mints.first(where: { $0.url.absoluteString.contains(selectedMintString) }) else {
//            displayAlert(alert: AlertDetail(title: "Invalid Mint"))
//            return
//        }
//        Task {
//            do {
//                self.loading = true
//                let token = try await wallet.sendTokens(from:mint, amount: amount, memo:tokenMemo)
//                let message = """
//Here is some eCash! You can redeem it using any cashu wallet.
//
//\(token)
//"""
//                try nostrService.sendMessage(to: recipientProfile, content: message)
//                self.loading = false
//                self.success = true
//                self.numberString = ""
//                self.tokenMemo = ""
//                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
//                    withAnimation {
//                        self.success = false
//                    }
//                }
//            } catch {
//                displayAlert(alert: AlertDetail(title: "Error", description: String(describing: error)))
//                self.loading = false
//                self.success = false
//            }
//        }
//    }
//    
//    private func displayAlert(alert:AlertDetail) {
//        currentAlert = alert
//        showAlert = true
//    }
//}
//
//
//#Preview {
//    NostrSendView(nsvm: NostrSendViewModel(recipientProfile: Profile(pubkey: "f0f0f0f0f0f0", npub: "npub1ß203w98ourtß23894ut", name: "nakamoto")))
//}
