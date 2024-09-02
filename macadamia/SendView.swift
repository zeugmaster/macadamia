//
//  SendView.swift
//  macadamia
//
//  Created by zeugmaster on 04.01.24.
//

import SwiftUI
import SwiftData

struct SendView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var wallets: [Wallet]
    
    var activeWallet:Wallet? {
        get {
            wallets.first
        }
    }
    
    @State var tokenString:String?
    var navigationPath:Binding<NavigationPath>?

    @State var showingShareSheet = false
    @State var tokenMemo = ""

    @State var numberString = ""
    @State var mintList = [String]()
    @State var selectedMintString = ""
    @State var selectedMintBalance = 0

    @State var loading = false
    @State var succes = false

    @State var showAlert:Bool = false
    @State var currentAlert:AlertDetail? // not sure if the property wrapper is necessary

    @State private var isCopied = false
    @FocusState var amountFieldInFocus:Bool
    
    init(token:String? = nil, navigationPath:Binding<NavigationPath>? = nil) {
        self.tokenString = token
        self.navigationPath = navigationPath
    }
    
    var body: some View {
        Form {
            Section {
                HStack {
                    TextField("enter amount", text: $numberString)
                        .keyboardType(.numberPad)
                        .monospaced()
                        .focused($amountFieldInFocus)
                    Text("sats")
                }
                // TODO: CHECK FOR EMPTY MINT LIST
                Picker("Mint", selection:$selectedMintString) {
                    ForEach(mintList, id: \.self) {
                        Text($0)
                    }
                }
                .onAppear(perform: {
                    fetchMintInfo()
                })
                .onChange(of: selectedMintString) { oldValue, newValue in
                    updateBalance()
                }
                HStack {
                    Text("Balance: ")
                    Spacer()
                    Text(String(selectedMintBalance))
                        .monospaced()
                    Text("sats")
                }
                .foregroundStyle(.secondary)
            }
            .disabled(tokenString != nil)
            Section {
                TextField("enter note", text: $tokenMemo)
            } footer: {
                Text("Tap to add a note to the recipient.")
            }
            .disabled(tokenString != nil)
            
            if tokenString != nil {
                Section {
                    TokenText(text: tokenString!)
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
                        showingShareSheet = true
                    } label: {
                        HStack {
                            Text("Share")
                            Spacer()
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
                Section {
                    QRView(string: tokenString!)
                } header: {
                    Text("Share via QR code")
                }
            }
        }
        .navigationTitle("Send")
        .navigationBarTitleDisplayMode(.inline)
        .alertView(isPresented: $showAlert, currentAlert: currentAlert)
        .onAppear(perform: {
            amountFieldInFocus = true
        })
        
        Spacer()
        
        Button(action: {
            generateToken()
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
        .disabled(numberString.isEmpty || amount == 0 || tokenString != nil)
        .sheet(isPresented: $showingShareSheet, content: {
            ShareSheet(items: [tokenString ?? "No token provided"])
        })

    }
    
    // MARK: - LOGIC
    
    func copyToClipboard() {
        UIPasteboard.general.string = tokenString
        withAnimation {
            isCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isCopied = false
            }
        }
    }
    
    func fetchMintInfo() {
        guard let activeWallet else {
            return
        }
        
        for mint in activeWallet.mints {
            let readable = mint.url.absoluteString.dropFirst(8)
            mintList.append(String(readable))
        }
        selectedMintString = mintList[0]
    }
    
    func updateBalance() {
        guard let activeWallet else {
            return
        }
        if let mint = activeWallet.mints.first(where: { $0.url.absoluteString.contains(selectedMintString) }) {
            selectedMintBalance = activeWallet.validProofs.sum
        }
    }
    
    var amount: Int {
        return Int(numberString) ?? 0
    }
    
    func generateToken() {
        guard let activeWallet else {
            return
        }
        guard let mint = activeWallet.mints.first(where: { $0.url.absoluteString.contains(selectedMintString) }) else {
            displayAlert(alert: AlertDetail(title: "Invalid Mint"))
            return
        }
        Task {
            do {
                let (token, change) = try await mint.send(proofs: activeWallet.validProofs, amount: amount, memo: tokenMemo)
                self.tokenString = try token.serialize(.V3)
            } catch {
                displayAlert(alert: AlertDetail(title: "Error", description: String(describing: error)))
            }
        }
    }
    
    private func displayAlert(alert:AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}

#Preview {
    SendView()
}
