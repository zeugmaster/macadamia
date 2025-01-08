import CashuSwift
import SwiftData
import SwiftUI

struct SendView: View {
    @Environment(\.modelContext) private var modelContext
    
    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]
    
    @Query private var allProofs:[Proof]
//    @Environment(\.dismiss) private var dismiss // not actually needed because this view does not self dismiss
    
    var activeWallet: Wallet? {
        wallets.first
    }

    @State private var token: CashuSwift.Token?

    @State private var tokenMemo = ""
    
    @State private var selectedMint:Mint?
    
    @State private var numberString = ""
    @State private var selectedMintBalance = 0

    @State private var loading = false

    @State private var showAlert: Bool = false
    @State private var currentAlert: AlertDetail?

    @FocusState var amountFieldInFocus: Bool

    init(token: CashuSwift.Token? = nil) {
        self.token = token
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
                MintPicker(label: "Send from", selectedMint: $selectedMint)
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
            .disabled(token != nil)
            Section {
                TextField("enter note", text: $tokenMemo)
            } footer: {
                Text("Tap to add a note to the recipient.")
            }
            .disabled(token != nil)

            if let token {
                TokenShareView(token: token)
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
        .disabled(numberString.isEmpty || amount <= 0 || token != nil)
        
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
        guard let selectedMint else {
            logger.error("""
                         unable to generate Token because one or more of the following variables are nil:
                         selectedMInt: \(selectedMint.debugDescription)
                         activeWallet: \(activeWallet.debugDescription)
                         """)
            return
        }

        Task { @MainActor in
            do {
                let selectedUnit: Unit = .sat
                                
                guard let preSelect = selectedMint.select(allProofs:allProofs,
                                                      amount: amount,
                                                      unit: selectedUnit) else {
                    displayAlert(alert: AlertDetail(title: "Could not select proofs to send."))
                    logger.warning("no proofs could be selected to generate a token with this amount.")
                    return
                }
                
                let (token, swappedProofs, event) = try await selectedMint.send(proofs: preSelect.selected,
                                                                            targetAmount: amount,
                                                                            memo: tokenMemo)
                
                self.token = token
                insert(swappedProofs + [event])
                                
            } catch {
                displayAlert(alert: AlertDetail(with: error))
            }
        }
    }

    @MainActor
    func insert(_ models: [any PersistentModel]) {
        models.forEach({ modelContext.insert($0) })
        do {
            try modelContext.save()
            logger.info("successfully added \(models.count) object\(models.count == 1 ? "" : "s") to the database.")
        } catch {
            logger.error("Saving SwiftData model context failed with error: \(error)")
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
