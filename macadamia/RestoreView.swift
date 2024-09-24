////
////  RestoreView.swift
////  macadamia
////
////  Created by zeugmaster on 06.01.24.
////
//
//import SwiftUI
//import SwiftData
//import CashuSwift
//
//struct RestoreView: View {
//    @State var mnemonic = ""
//    @State var loading = false
//    @State var success = false
//    
//    @State var showAlert:Bool = false
//    @State var currentAlert:AlertDetail?
//    
//    @Environment(\.modelContext) private var modelContext
//    @Query private var wallets: [Wallet]
//    
//    var activeWallet:Wallet? {
//        get {
//            wallets.first
//        }
//    }
//    
//    func attemptRestore() {
//        guard let activeWallet else {
//            displayAlert(alert: AlertDetail(title: "No Wallet",
//                                           description: "."))
//            return
//        }
//        guard let seed = activeWallet.seed else {
//            displayAlert(alert: AlertDetail(title: "No Seed",
//                                           description: "This wallet does not have a seed."))
//            return
//        }
//        Task {
//            do {
//                loading = true
//                
//                for mint in activeWallet.mints {
//                    
//                }
//                
//                success = true
//                loading = false
//            } catch {
//                displayAlert(alert: AlertDetail(title: "Error", description: "There was an error when attempting to restore. Detail: \(String(describing: error))"))
//                loading = false
//            }
//        }
//    }
//    
//    private func displayAlert(alert:AlertDetail) {
//        currentAlert = alert
//        showAlert = true
//    }
//    
//    var body: some View {
//        List {
//            Section {
//                TextField("Enter seed phrase", text: $mnemonic, axis: .vertical)
//                    .lineLimit(4, reservesSpace: true)
//            } footer: {
//                Text("Enter your 12 word seed phrase, separated by spaces or line breaks. Please also make sure that your mint list contains all the mints you want to try restoring from.")
//            }
//        }
//        Button(action: {
//            attemptRestore()
//        }, label: {
//            HStack(spacing:0) {
//                Spacer()
//                if loading {
//                    ProgressView()
//                    Text("Restoring...")
//                        .padding()
//                } else if success {
//                    Text("Done!")
//                        .padding()
//                        .foregroundColor(.green)
//                } else {
//                    Text("Restore")
//                    .padding()
//                }
//                Spacer()
//            }
//        })
//        .frame(maxWidth: .infinity)
//        .foregroundColor(.white)
//        .buttonStyle(.bordered)
//        .padding()
//        .bold()
//        .toolbar(.hidden, for: .tabBar)
//        .disabled(mnemonic.isEmpty || loading || success)
//        .navigationTitle("Restore")
//        .navigationBarTitleDisplayMode(.inline)
//        .toolbar(.hidden, for: .tabBar)
//        .navigationBarBackButtonHidden(loading)
//        .alertView(isPresented: $showAlert, currentAlert: currentAlert)
//    }
//}
//
//#Preview {
//    RestoreView()
//}
