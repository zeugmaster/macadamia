//
//  WalletView.swift
//  macadamia
//
//  Created by Dario Lass on 13.12.23.
//

import SwiftUI

struct WalletView: View {
    @StateObject var viewModel = WalletViewModel()
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
                    Text(String(viewModel.balance))
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
                    viewModel.update()
                })
                Spacer()
                List {
                    Label("210 sats ecash", systemImage: "arrow.down.right")
                    Label("69 sats lightning", systemImage: "arrow.up.left")
                    Label("420 sats lightning", systemImage: "arrow.down.right")
                    Label("21 sats ecash", systemImage: "arrow.down.right")
                }.padding(50)
                    .listStyle(.plain)
                    
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
               
                //Spacer()
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

#Preview {
    WalletView()
}

class WalletViewModel:ObservableObject {
    //@Published var totalBalanceString = "2101"
    var wallet = Wallet.shared
    
    @Published var balance = 0
    @Published var pendingBalance = 0
    
    init(wallet: Wallet = Wallet.shared) {
        self.wallet = wallet
        Task {
            try await wallet.updateMints()
        }
    }
    
    func update() {
        balance = wallet.balance()
    }
    
}
