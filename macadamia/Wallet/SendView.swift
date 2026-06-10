import CashuSwift
import SwiftData
import SwiftUI
import secp256k1

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
    @State private var selectedUnit: Currency.Unit = .sat

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
                                       baseUnit: selectedUnit,
                                       exchangeRates: appState.exchangeRates,
                                       onReturn: {})

                    // TODO: CHECK FOR EMPTY MINT LIST
                    MintPicker(label: "Send from", selectedMint: $selectedMint)
                        .onChange(of: selectedMint) { _, newValue in
                            // Snap to the new mint's first supported unit;
                            // the unit-change handler below will refresh the
                            // balance and the input view clears its amount.
                            selectedUnit = newValue?.supportedUnits.first ?? .sat
                            updateBalance()
                        }
                    if (selectedMint?.supportedUnits.count ?? 1) > 1 {
                        Picker(selection: $selectedUnit) {
                            if let units = selectedMint?.supportedUnits {
                                ForEach(units, id: \.self) { unit in
                                    Text(unit.displayName)
                                }
                            } else {
                                Text("No units available.")
                            }
                        } label: {
                            Text("Unit: ")
                        }
                    }
                    HStack {
                        Text("Balance: ")
                        Spacer()
                        AmountView(amount: selectedMintBalance, unit: selectedUnit)
                            .monospaced()
                    }
                    .foregroundStyle(amount > selectedMintBalance ? .failureRed : .secondary)
                    .animation(.linear(duration: 0.2), value: amount > selectedMintBalance)
                }
                .disabled(token != nil)
                .onChange(of: selectedUnit) { _, _ in
                    updateBalance()
                }
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
                                    .font(.title2)
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
        // Only count proofs that match the unit the user is currently
        // sending in — otherwise a USD-denominated mint balance would leak
        // into the sat input's "you have X" line (or vice versa).
        selectedMintBalance = proofsOfSelectedMint
            .filter { $0.state == .valid && $0.currencyUnit == selectedUnit }
            .sum
    }
    
    @MainActor
    func generateToken() {
        guard let selectedMint, let activeWallet else {
            logger.error("""
                         unable to generate Token because one or more of the following variables are nil:
                         selectedMInt: \(selectedMint.debugDescription)
                         activeWallet: \(activeWallet.debugDescription)
                         """)
            buttonState = .fail()
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                buttonState = .idle("Generate Token", action: {
                    generateToken()
                })
            }
            return
        }
        
        let pubkey = lockingKey.isEmpty ? nil : lockingKey
        
        if let pubkey {
            guard let bytes = try? pubkey.bytes,
                  let _ = try? secp256k1.Signing.PublicKey(dataRepresentation: bytes,
                                                               format: .compressed) else {
                displayAlert(alert: AlertDetail(title: String(localized: "Invalid public key 🔑"), description: String(localized: "The public key you entered does not seem to be valid.")))
                return
            }
        }
        
        
        buttonState = .loading()
        
        Task {
            do {
                token = try await AppSchemaV1.createToken(mint: selectedMint,
                                                          activeWallet: activeWallet,
                                                          amount: amount,
                                                          unit: selectedUnit,
                                                          memo: tokenMemo,
                                                          modelContext: modelContext,
                                                          lockingKey: pubkey)
                buttonState = .success()
            } catch {
                logger.error("error when preparing send \(error)")
                displayAlert(alert: AlertDetail(with: error))
                buttonState = .fail()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    buttonState = .idle("Generate Token", action: {
                        generateToken()
                    })
                }
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
