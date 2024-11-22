import CashuSwift
import SwiftData
import SwiftUI

struct SendView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]
    @Query private var allProofs:[Proof]

    var activeWallet: Wallet? {
        wallets.first
    }

    @State var tokenString: String?
    var navigationPath: Binding<NavigationPath>?

    @State var tokenMemo = ""
    
    @State private var selectedMint:Mint?
    
    @State private var numberString = ""
    @State private var selectedMintBalance = 0

    @State private var loading = false

    @State private var showAlert: Bool = false
    @State private var currentAlert: AlertDetail?

    @FocusState var amountFieldInFocus: Bool

    init(token: String? = nil,
         navigationPath: Binding<NavigationPath>? = nil) {
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
                MintPicker(selectedMint: $selectedMint)
                    .onChange(of: selectedMint) { _, _ in
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
                TokenShareView(tokenString: tokenString)
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
        
    }

    // MARK: - LOGIC

    var proofsOfSelectedMint:[Proof] {
        allProofs.filter { $0.mint == selectedMint }
    }

    

    func updateBalance() {
        guard !proofsOfSelectedMint.isEmpty else {
            logger.warning("could not update balances because proofs of selectedMint is empty.")
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
            logger.error("""
                         unable to generate Token because one or more of the following variables are nil:
                         selectedMInt: \(selectedMint.debugDescription)
                         activeWallet: \(activeWallet.debugDescription)
                         """)
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
                    logger.warning("no proofs could be selected to generate a token with this amount.")
                    return
                }
                
                // make input proofs .pending
                preSelect.selected.forEach({ $0.state = .pending })
                
                if amount == preSelect.selected.sum {
                    logger.debug("Token amount and selected proof sum are an exact match, no swap necessary...")
                    
                    // construct token
                    
                    let proofContainer = CashuSwift.ProofContainer(mint: selectedMint.url.absoluteString,
                                                                   proofs: preSelect.selected.map({ CashuSwift.Proof($0) }))
                    let token = CashuSwift.Token(token: [proofContainer], memo: tokenMemo, unit: selectedUnit.rawValue)
                    try await MainActor.run {
                        try tokenString = token.serialize(version)
                        let event = Event.sendEvent(unit: selectedUnit,
                                                    shortDescription: "Send Event",
                                                    wallet: activeWallet,
                                                    amount: (amount),
                                                    longDescription: "",
                                                    proofs: preSelect.selected,
                                                    memo: tokenMemo,
                                                    tokenString: tokenString ?? "") // TODO: handle more explicitly / robust
                        modelContext.insert(event)
                        try modelContext.save()
                    }
                    
                } else if preSelect.selected.sum > amount {
                    logger.debug("Token amount and selected proof are not a match, swapping...")
                    
                    // swap to amount specified by user
                    let (sendProofs, changeProofs) = try await CashuSwift.swap(mint: selectedMint,
                                                                               proofs: preSelect.selected,
                                                                               amount: amount,
                                                                               seed: activeWallet.seed)
                    
                    // add return tokens to db, sendProofs: pending, changeProofs valid
                    let usedKeyset = selectedMint.keysets.first(where: { $0.keysetID == sendProofs.first?.keysetID })
                    
                    // if the swap succeeds the input proofs need to be marked as spent
                    preSelect.selected.forEach({ $0.state = .spent })
                    
                    let feeRate = usedKeyset?.inputFeePPK ?? 0
                    
                    try await MainActor.run {
                        let internalSendProofs = sendProofs.map({ Proof($0,
                                                                        unit: selectedUnit,
                                                                        inputFeePPK: feeRate,
                                                                        state: .pending,
                                                                        mint: selectedMint,
                                                                        wallet: activeWallet) })
                        
                        internalSendProofs.forEach({ modelContext.insert($0) })
                        
                        let internalChangeProofs = changeProofs.map({ Proof($0,
                                                                            unit: selectedUnit,
                                                                            inputFeePPK: feeRate,
                                                                            state: .valid,
                                                                            mint: selectedMint,
                                                                            wallet: activeWallet) })
                        
                        internalChangeProofs.forEach({ modelContext.insert($0) })
                        
                        selectedMint.proofs?.append(contentsOf: internalSendProofs + internalChangeProofs)
                        
                        if let usedKeyset {
                            selectedMint.increaseDerivationCounterForKeysetWithID(usedKeyset.keysetID,
                                                                                  by: internalSendProofs.count + internalChangeProofs.count)
                        } else {
                            logger.error("Could not determine applied keyset! This will lead to issues with det sec counter and fee rates.")
                        }
                        
                        try modelContext.save()
                        // construct token with sendProofs
                        let proofContainer = CashuSwift.ProofContainer(mint: selectedMint.url.absoluteString, proofs: sendProofs.map({ CashuSwift.Proof($0) }))
                        let token = CashuSwift.Token(token: [proofContainer], memo: tokenMemo, unit: selectedUnit.rawValue)
                        tokenString = try token.serialize(version)
                        // log event
                        let event = Event.sendEvent(unit: selectedUnit,
                                                    shortDescription: "Send Event",
                                                    wallet: activeWallet,
                                                    amount: (amount),
                                                    longDescription: "",
                                                    proofs: internalSendProofs,
                                                    memo: tokenMemo,
                                                    tokenString: tokenString ?? "") // TODO: handle more explicitly / robust
                        modelContext.insert(event)
                        try modelContext.save()
                        logger.info("successfully created sendable token and saved change to db.")
                    }
                } else {
                    logger.critical("amount must not exceed preselected proof sum. .pick() should have returned nil.")
                }
            } catch {
                displayAlert(alert: AlertDetail(error))
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
