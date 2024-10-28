import CashuSwift
import SwiftData
import SwiftUI

struct SendView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var wallets: [Wallet]
    @Query private var allProofs:[Proof]

    var activeWallet: Wallet? {
        wallets.first
    }

    @State var tokenString: String?
    var navigationPath: Binding<NavigationPath>?

    @State var showingShareSheet = false
    @State var tokenMemo = ""

    @State var numberString = ""
    @State var mintList = [String]()
    @State var selectedMintString = ""
    @State var selectedMintBalance = 0

    @State var loading = false
    @State var succes = false

    @State var showAlert: Bool = false
    @State var currentAlert: AlertDetail? // not sure if the property wrapper is necessary

    @State private var isCopied = false
    @FocusState var amountFieldInFocus: Bool

    init(token: String? = nil, navigationPath: Binding<NavigationPath>? = nil) {
        tokenString = token
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
                Picker("Mint", selection: $selectedMintString) {
                    ForEach(mintList, id: \.self) {
                        Text($0)
                    }
                }
                .onAppear(perform: {
                    fetchMintInfo()
                })
                .onChange(of: selectedMintString) { _, _ in
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

            if let tokenString {
                Section {
                    TokenText(text: tokenString)
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
                    QRView(string: tokenString)
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

    var selectedMint: Mint? {
        activeWallet?.mints.first(where: { $0.url.absoluteString.contains(selectedMintString) })
    }
    
    var proofsOfSelectedMint:[Proof] {
        allProofs.filter { $0.mint == selectedMint }
    }

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
        guard let _ = activeWallet,
              let selectedMint
        else {
            return
        }
        selectedMintBalance = proofsOfSelectedMint.filter({ $0.state == .valid }).sum
    }

    var amount: Int {
        return Int(numberString) ?? 0
    }

    func generateToken() {
        guard let activeWallet,
              let selectedMint
        else {
            return
        }

        Task {
            do {
                let version: CashuSwift.TokenVersion = .V3
                
                // using the .pick function to preselect from all proofs of this mint
                // TODO: check for correct unit
                let selectedUnit: Unit = .sat
                
                // let recipientSwapFee =
                
                guard let preSelect = selectedMint.select(allProofs:allProofs, amount: amount, unit: selectedUnit) else {
                    displayAlert(alert: AlertDetail(title: "Could not select proofs to send."))
                    return
                }
                
                if amount == preSelect.selected.sum {
                    // construct token
                    preSelect.selected.forEach({ $0.state = .pending })
                    let proofContainer = CashuSwift.ProofContainer(mint: selectedMint.url.absoluteString,
                                                                   proofs: preSelect.selected.map({ CashuSwift.Proof($0) }))
                    let token = CashuSwift.Token(token: [proofContainer], memo: tokenMemo, unit: selectedUnit.rawValue)
                    try await MainActor.run {
                        try tokenString = token.serialize(version)
                        let event = Event.sendEvent(unit: selectedUnit,
                                                    shortDescription: "Send Event",
                                                    wallet: activeWallet,
                                                    amount: Double(amount),
                                                    longDescription: "",
                                                    proofs: preSelect.selected,
                                                    memo: tokenMemo,
                                                    tokenString: tokenString ?? "") // TODO: handle more explicitly / robust
                        modelContext.insert(event)
                        try modelContext.save()
                    }
                    
                } else if preSelect.selected.sum > amount {
                    // swap to amount specified by user
                    preSelect.selected.forEach({ $0.state = .spent })
                    #warning("need to set proofs back to state valid of operation fails")
                    #warning("det sec")
                    let (sendProofs, changeProofs) = try await CashuSwift.swap(mint: selectedMint, proofs: preSelect.selected, amount: amount)
                    // add return tokens to db, sendProofs: pending, changeProofs valid
                    let feeRate = selectedMint.keysets.first(where: { $0.keysetID == sendProofs.first?.keysetID })?.inputFeePPK ?? 0
                    try await MainActor.run {
                        let internalSendProofs = sendProofs.map({ Proof($0, unit: selectedUnit, inputFeePPK: feeRate, state: .pending, mint: selectedMint, wallet: activeWallet) })
                        internalSendProofs.forEach({ modelContext.insert($0) })
                        changeProofs.forEach({ modelContext.insert(Proof($0, unit: selectedUnit, inputFeePPK: feeRate, state: .valid, mint: selectedMint, wallet: activeWallet)) })
                        try modelContext.save()
                        // construct token with sendProofs
                        let proofContainer = CashuSwift.ProofContainer(mint: selectedMint.url.absoluteString, proofs: sendProofs.map({ CashuSwift.Proof($0) }))
                        let token = CashuSwift.Token(token: [proofContainer], memo: tokenMemo, unit: selectedUnit.rawValue)
                        tokenString = try token.serialize(version)
                        // log event
                        let event = Event.sendEvent(unit: selectedUnit,
                                                    shortDescription: "Send Event",
                                                    wallet: activeWallet,
                                                    amount: Double(amount),
                                                    longDescription: "",
                                                    proofs: internalSendProofs,
                                                    memo: tokenMemo,
                                                    tokenString: tokenString ?? "") // TODO: handle more explicitly / robust
                        modelContext.insert(event)
                        try modelContext.save()
                    }
                } else {
                    fatalError("amount must not exceed preselected proof sum. .pick() should have returned nil.")
                }
            } catch {
                displayAlert(alert: AlertDetail(title: "Error", description: String(describing: error)))
            }
        }
    }

    private func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}

#Preview {
    SendView()
}
