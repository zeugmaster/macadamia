//
//  WalletView.swift
//  macadamia
//
//  Created by zeugmaster on 13.12.23.
//

import SwiftUI

let betaDisclaimerURL = URL(string: "https://macadamia.cash/beta.html")!

struct WalletView: View {
    @ObservedObject var vm = WalletViewModel()
    @State var navigationPath = NavigationPath()
    
    static let buttonPadding:CGFloat = 1
        
    var body: some View {
        NavigationStack(path:$navigationPath) {
            VStack {
                HStack {
                    Button {
                        if UIApplication.shared.canOpenURL(betaDisclaimerURL) {
                            UIApplication.shared.open(betaDisclaimerURL)
                        }
                    } label: {
                        Text("BETA")
                            .padding(6)
                            .overlay(
                            RoundedRectangle(cornerRadius: 4) // Rounded rectangle shape
                                .stroke(lineWidth: 1) // Thin outline with specified line width
                        )
                    }
                    Spacer()
                }
                .padding(EdgeInsets(top: 20, leading: 40, bottom: 0, trailing: 0))
                Spacer(minLength: 60)
                HStack(alignment:.bottom) {
                    Spacer()
                    Spacer()
                    Text(String(vm.balance))
                        .monospaced()
                        .bold()
                        .dynamicTypeSize(.accessibility5)
                    Text("sats")
                        .monospaced()
                        .bold()
                        .dynamicTypeSize(.accessibility1)
                        .padding(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
                        .foregroundStyle(.secondary)
                        Spacer()
                }
                .onAppear(perform: {
                    vm.update()
                })
                Spacer()
                List {
                    if vm.transactions.isEmpty {
                        HStack {
                            Spacer()
                            Text("No transactions yet")
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    } else {
                        ForEach(vm.transactions) { transaction in
                            TransactionListRowView(transaction: transaction)
                        }
                    }
                }
                .id(vm.transactionListRefreshCounter)
                .padding(EdgeInsets(top: 60, leading: 20, bottom: 40, trailing: 20))
                .listStyle(.plain)
                .refreshable {
                    vm.checkPending()
                }
                Spacer()
                HStack {
                   // First button
                   Button(action: {
                       navigationPath.append("Receive")
                   }) {
                       Text("Receive")
                           .frame(maxWidth: .infinity)
                           .padding()
                           .bold()
                           .foregroundColor(.white)
                           .cornerRadius(10)
                   }
                   .buttonStyle(.bordered)
                   .padding(WalletView.buttonPadding)
                   
                   // Second button
                   Button(action: {
                       navigationPath.append("Send")
                   }) {
                       Text("Send")
                           .frame(maxWidth: .infinity)
                           .padding()
                           .bold()
                           .foregroundColor(.white)
                           .cornerRadius(10)
                   }.buttonStyle(.bordered)
                        .padding(WalletView.buttonPadding)
               }
               .padding(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                HStack {
                   // First button
                    NavigationLink(destination: MintView()) {
                        Text("Mint")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .bold()
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .buttonStyle(.bordered)
                    .padding(WalletView.buttonPadding)
                   
                   // Second button
                   Button(action: {
                       navigationPath.append("Melt")
                   }) {
                       Text("Melt")
                           .frame(maxWidth: .infinity)
                           .padding()
                           .bold()
                           .foregroundColor(.white)
                           .cornerRadius(10)
                   }.buttonStyle(.bordered)
                        .padding(WalletView.buttonPadding)
               }
               .padding(EdgeInsets(top: 0, leading: 20, bottom: 40, trailing: 20))
            }
            .navigationDestination(for: String.self) { tag in
                switch tag {
                case "Send":
                    SendView()
                case "Receive":
                    ReceiveView()
                case "Melt":
                    MeltView()
                default:
                    EmptyView()
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
        }
    }
}

struct TransactionListRowView: View {
    var transaction:Transaction
    
    init(transaction: Transaction) {
        self.transaction = transaction
    }
    
    var body: some View {
        NavigationLink(destination: TransactionDetailView(transaction: transaction)) {
            HStack {
                if transaction.type == .cashu {
                    Image(systemName: "banknote")
                    Text(transaction.token ?? "no token")
                } else if transaction.type == .lightning {
                    Image(systemName: "bolt.fill")
                    // hey, it's monospaced. might as well
                    Text(" " + transaction.invoice!)
                } else if transaction.type == .drain {
                    Image(systemName: "arrow.turn.down.right")
                    Text(transaction.token ?? "Token")
                }
                Spacer(minLength: 10)
                if transaction.pending {
                    Image(systemName: "hourglass")
                }
                Text(String(transaction.amount))
            }
            .lineLimit(1)
            .monospaced()
            .fontWeight(.light)
            .font(.callout)
        }
        
    }
}

#Preview {
    WalletView()
}

@MainActor
class WalletViewModel:ObservableObject {
    //@Published var totalBalanceString = "2101"
    
    var wallet = Wallet.shared
    
    @Published var balance = 0
    
    @Published var transactions = [Transaction]()
    @Published var transactionListRefreshCounter = 0
    
    @Published var showAlert:Bool = false
    var currentAlert:AlertDetail?
    
    func update() {
        Task {
            try await wallet.updateMints()
        }
        balance = wallet.balance()
        transactions = wallet.database.transactions
    }
    
    func checkPending() {
        Task {
            do {
                for transaction in self.transactions {
                    if transaction.pending && transaction.type == .cashu && transaction.token != nil {
                        transaction.pending = try await wallet.checkTokenStatePending(token: transaction.token!)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            self.transactionListRefreshCounter += 1
                        }
                   }
                }
            } catch {
                let detail = String(String(describing: error).prefix(100)) + "..." //ooof
                displayAlert(alert: AlertDetail(title: "Unable to update",
                                                description: detail))
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    self.transactionListRefreshCounter += 1
                }
            }
        }
    }
    
    private func displayAlert(alert:AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
    
}
