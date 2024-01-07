//
//  WalletView.swift
//  macadamia
//
//  Created by Dario Lass on 13.12.23.
//

import SwiftUI



struct WalletView: View {
    @ObservedObject var vm = WalletViewModel()
    @StateObject var mintRequestViewModel = MintRequestViewModel()
    @State var navigationPath = NavigationPath()
    
    static let buttonPadding:CGFloat = 1
        
    var body: some View {
        NavigationStack(path:$navigationPath) {
            VStack {
                Spacer(minLength: 100)
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
                    Button(action: {
                        navigationPath.append("First")
                    }) {
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
                case "First":
                    MintRequestView(viewmodel: mintRequestViewModel, 
                                    navigationPath: $navigationPath)
                case "Second":
                    MintRequestInvoiceView(viewmodel: mintRequestViewModel, 
                                           navigationPath: $navigationPath)
                case "Third":
                    MintRequestCompletionView(viewModel:mintRequestViewModel, 
                                              navigationPath: $navigationPath)
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
                } else {
                    Image(systemName: "bolt.fill")
                    // hey, it's monospaced. might aswell
                    Text(" " + transaction.invoice!)
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
    
    func update() {
        Task {
            try await wallet.updateMints()
        }
        balance = wallet.balance()
//        pendingBalance = wallet.database.pendingProofs.reduce(0) { $0 + $1.amount }
        transactions = wallet.database.transactions
//        transactions = demoTransactions
    }
    
    func checkPending() {
        Task {
            for transaction in self.transactions {
                if transaction.pending && transaction.type == .cashu && transaction.token != nil {
                    print("checking")
                    transaction.pending = try await wallet.checkTokenStatePending(token: transaction.token!)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        self.transactionListRefreshCounter += 1
                    }
                }
            }
        }
    }
    
}


let demoTransactions = [Transaction(timeStamp: "25 utc", unixTimestamp: 100000000, amount: 21, type: .cashu, pending: true, token: "cashuAoihfpi3qhü483r312p847ß9834urüoq3ußr9t8"), Transaction(timeStamp: "", unixTimestamp: 1000000001, amount: 420, type: .lightning, invoice: "lnbc1oiwhjfp9qhfpohpqoiwjeürofiqwpofgihqpwvnalkn")]
