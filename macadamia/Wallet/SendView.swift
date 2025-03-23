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

    @State private var token: CashuSwift.Token?

    @State private var tokenMemo = ""
    
    @State private var selectedMint:Mint?
    
    @State private var numberString = ""
    @State private var selectedMintBalance = 0

    @State private var buttonState: ActionButtonState = .idle("")

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
                .foregroundStyle(amount > selectedMintBalance ? .failureRed : .secondary)
                .animation(.linear(duration: 0.2), value: amount > selectedMintBalance)
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
            buttonState = .idle("Generate Token", action: generateToken)
        })

        ActionButton(state: $buttonState)
            .actionDisabled(numberString.isEmpty || amount <= 0)
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
            tokenGenerationFailed()
            return
        }
        
        let selectedUnit: Unit = .sat
        
        guard let preSelect = selectedMint.select(allProofs:allProofs,
                                              amount: amount,
                                              unit: selectedUnit) else {
            displayAlert(alert: AlertDetail(with: CashuError.insufficientInputs("")))
            logger.warning("no proofs could be selected to generate a token with this amount.")
            tokenGenerationFailed()
            return
        }
        
        buttonState = .loading()
        
        selectedMint.send(proofs: preSelect.selected,
                          targetAmount: amount,
                          memo: tokenMemo) { result in
            switch result {
            case .success(let (token, swappedProofs, event)):
                self.token = token
                AppSchemaV1.insert(swappedProofs + [event], into: modelContext)
                buttonState = .success()
            case .failure(let error):
                logger.error("unable to generate token due to error: \(error)")
                displayAlert(alert: AlertDetail(with: error))
                tokenGenerationFailed()
            }
        }
    }
                                          
    private func tokenGenerationFailed() {
        buttonState = .fail()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: {
            buttonState = .idle("Generate Token", action: generateToken)
        })
    }

    private func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}

#Preview {
    SendView()
}
