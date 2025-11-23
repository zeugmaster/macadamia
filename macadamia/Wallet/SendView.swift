import CashuSwift
import SwiftData
import SwiftUI

struct SendView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    
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
    
    @State private var amount = 0
    @State private var selectedMintBalance = 0
    
    @State private var lockingKey: String = ""

    @State private var buttonState: ActionButtonState = .idle("")

    @State private var showAlert: Bool = false
    @State private var currentAlert: AlertDetail?

    init(token: CashuSwift.Token? = nil) {
        self.token = token
    }

    var body: some View {
        ZStack {
            Form {
                Section {
                    NumericalInputView(output: $amount,
                                       baseUnit: .sat,
                                       exchangeRates: appState.exchangeRates,
                                       onReturn: {})
                    
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
                if token == nil || !tokenMemo.isEmpty {
                    Section {
                        TextField("Add a note to the recipient...", text: $tokenMemo)
                            .disabled(token != nil)
                    } header: {
                        Text("Memo")
                    }
                }
                
                if token == nil || !lockingKey.isEmpty {
                    Section {
                        HStack {
                            TextField("", text: $lockingKey, prompt: Text("Type, paste or scan..."))
                                .autocorrectionDisabled(true)
                                .textInputAutocapitalization(.never)
                            InputViewModalButton(inputTypes: [.publicKey]) {
                                Image(systemName: "qrcode.viewfinder")
                            } onResult: { result in
                                switch result.type {
                                case .publicKey:
                                    self.lockingKey = result.payload
                                default:
                                    logger.error("")
                                }
                            }
                        }
                        .disabled(token != nil)
                    } header: {
                        Text("Lock to Public Key")
                    }
                }
                
                if let token {
                    TokenShareView(token: token)
                }
                Spacer(minLength: 50)
                    .listRowBackground(Color.clear)
            }
            .navigationTitle("Send")
            .navigationBarTitleDisplayMode(.inline)
            .alertView(isPresented: $showAlert, currentAlert: currentAlert)
            .onAppear(perform: {
                buttonState = .idle("Generate Token", action: generateToken)
            })

            VStack {
                Spacer()
                ActionButton(state: $buttonState)
                    .actionDisabled(amount <= 0 || amount > selectedMintBalance)
            }
        }
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
        
        buttonState = .loading()
        
        selectedMint.send(amount: amount,
                          memo: tokenMemo,
                          modelContext: modelContext,
                          lockingKey: lockingKey.isEmpty ? nil : lockingKey) { result in
            switch result {
            case .success(let token):
                buttonState = .success()
                self.token = token
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
