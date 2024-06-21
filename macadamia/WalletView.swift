//
//  WalletView.swift
//  macadamia
//
//  Created by zeugmaster on 13.12.23.
//

import SwiftUI
import Popovers

let betaDisclaimerURL = URL(string: "https://macadamia.cash/beta.html")!

struct WalletView: View {
    @ObservedObject var vm = WalletViewModel()
    @State var navigationPath = NavigationPath()
    @State var navigationTag: String?
    @State var urlState: String?
    
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
                    Text(vm.balance != nil ? String(vm.balance!) : "...")
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
                .padding(EdgeInsets(top: 60, leading: 20, bottom: 20, trailing: 20))
                .listStyle(.plain)
                .refreshable {
                    vm.checkPending()
                }
                Spacer()
                HStack {
                    //MARK: - BUTTON "RECEIVE"
                    Templates.Menu(
                        configuration: {
                            $0.popoverAnchor = .bottom
                            $0.originAnchor = .top
                            $0.backgroundColor = Color.black.opacity(0.5)
                        }
                    ) {
                        Templates.MenuItem {
                            navigationPath.append("Receive")
                        } label: { fade in
                            Color.clear.overlay(
                                HStack {
                                    Text("Scan or Paste Token")
                                    Spacer()
                                    Image(systemName: "qrcode")
                                }
                                .foregroundStyle(.white)
                                .dynamicTypeSize(.large)
                            )
                            .padding(20)
                            .opacity(fade ? 0.5 : 1)
                        }
                        .background(Color.black)
                        Templates.MenuItem {
                            navigationPath.append("Mint")
                        } label: { fade in
                            Color.clear.overlay(
                                HStack {
                                    Text("Create Invoice")
                                    Spacer()
                                    Image(systemName: "bolt.fill")
                                }
                                .foregroundStyle(.white)
                                .dynamicTypeSize(.large)
                            )
                            .padding(20)
                            .opacity(fade ? 0.5 : 1)
                        }
                        .background(Color.black)
                    } label: { fade in
                        Text("\(Image(systemName: "arrow.down"))  Receive")
                           .opacity(fade ? 0.5 : 1) // Apply fading effect based on a condition
                           .dynamicTypeSize(.xLarge) // Apply dynamic type size for accessibility
                           .fontWeight(.semibold) // Apply bold font weight
                           .padding(EdgeInsets(top: 20, leading: 0, bottom: 20, trailing: 0)) // Add padding around the text
                           .frame(maxWidth: .infinity) // Ensure it takes up the maximum width
                           .background(Color.secondary.opacity(0.3)) // Apply a semi-transparent background
                           .cornerRadius(10) // Apply rounded corners to the background
                    }
                    //MARK: - BUTTON "SEND"
                    Templates.Menu(
                        configuration: {
                            $0.popoverAnchor = .bottom
                            $0.originAnchor = .top
                            $0.backgroundColor = Color.black.opacity(0.5)
                        }
                    ) {
                        Templates.MenuItem {
                            navigationPath.append("Send")
                        } label: { fade in
                            Color.clear.overlay(
                                HStack {
                                    Text("Create Cashu Token")
                                    Spacer()
                                    Image(systemName: "banknote")
                                }
                                .foregroundStyle(.white)
                                .dynamicTypeSize(.large)
                            )
                            .padding(20)
                            .opacity(fade ? 0.5 : 1)
                        }
                        .background(Color.black)
                        Templates.MenuItem {
                            navigationPath.append("Melt")
                        } label: { fade in
                            Color.clear.overlay(
                                HStack {
                                    Text("Pay Lightning Invoice")
                                    Spacer()
                                    Image(systemName: "bolt.fill")
                                }
                                .foregroundStyle(.white)
                                .dynamicTypeSize(.large)
                            )
                            .padding(20)
                            .opacity(fade ? 0.5 : 1)
                        }
                        .background(Color.black)
                    } label: { fade in
                        Text("\(Image(systemName: "arrow.up"))  Send")
                           .opacity(fade ? 0.5 : 1) // Apply fading effect based on a condition
                           .dynamicTypeSize(.xLarge) // Apply dynamic type size for accessibility
                           .fontWeight(.semibold) // Apply bold font weight
                           .padding(EdgeInsets(top: 20, leading: 0, bottom: 20, trailing: 0))
                           .frame(maxWidth: .infinity) // Ensure it takes up the maximum width
                           .background(Color.secondary.opacity(0.3)) // Apply a semi-transparent background
                           .cornerRadius(10) // Apply rounded corners to the background
                    }
                }
                .padding(EdgeInsets(top: 20, leading: 20, bottom: 50, trailing: 20))
            }
            .navigationDestination(for: String.self) { tag in
                switch tag {
                case "Send":
                    SendView(vm: SendViewModel(navPath: navigationPath))
                case "Receive":
                    ReceiveView(vm: ReceiveViewModel(navPath: $navigationPath, initialState: urlState))
                case "Melt":
                    MeltView(vm: MeltViewModel(navPath: $navigationPath))
                case "Mint":
                    MintView(vm: MintViewModel(navPath: $navigationPath))
                default:
                    EmptyView()
                }
            }
            .onAppear {
                if navigationTag == "Receive" {
                  navigationPath.append("Receive")       
                }
            }
            .alertView(isPresented: $vm.showAlert, currentAlert: vm.currentAlert)
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
    
    @Published var balance:Int?
    
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
