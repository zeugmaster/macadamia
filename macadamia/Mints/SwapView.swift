import SwiftUI
import SwiftData
import CashuSwift


struct SwapView: View {
    
    enum PaymentState {
        case none, ready, setup, melting, minting, success, fail
    }
    
    @State private var state: PaymentState = .none
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State var showAlert: Bool = false
    @State var currentAlert: AlertDetail?
    
    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]
    
    @Query private var mints: [Mint]
    @Query private var allProofs: [Proof]
    
    @State private var buttonState = ActionButtonState.idle("")
    @State private var fromMint: Mint?
    @State private var toMint: Mint?
    @State private var amountString = ""
    @FocusState var amountFieldInFocus: Bool

    var activeWallet: Wallet? {
        wallets.first
    }
    
    var amount: Int? {
        Int(amountString)
    }
    
    var body: some View {
        ZStack {
            List {
                Section {
                    VStack(alignment: .leading) {
                        MintPicker(label: "From: ", selectedMint: $fromMint, allowsNoneState: false, hide: $toMint)
                        HStack {
                            Text("Balance: ")
                            Spacer()
                            Text(String(fromMint?.balance(for: .sat) ?? 0))
                            Text("sat")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    
                    MintPicker(label: "To: ", selectedMint: $toMint, allowsNoneState: true, hide: $fromMint)
                }

                Section {
                    HStack {
                        TextField("enter amount", text: $amountString)
                            .keyboardType(.numberPad)
                            .monospaced()
                            .focused($amountFieldInFocus)
                            .onAppear(perform: {
                                amountFieldInFocus = true
                            })
                        Text("sats")
                            .monospaced()
                    }
                } footer: {
                    Text("""
                         The mint from which the ecash originates will charge fees for this operation. 
                         IMPORTANT: If a swap fails during the Lightning payment \
                         you can manually retry from the transaction history.
                         """)
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            if state == .setup {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else if state == .melting || state == .minting || state == .success {
                                Image(systemName: "checkmark.circle.fill")
                            }
                            Text("Getting mint quote...")
                                .opacity(state == .setup ? 1 : 0.5)
                        }
                        
                        HStack {
                            if state == .melting {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else if state == .minting || state == .success {
                                Image(systemName: "checkmark.circle.fill")
                            }
                            Text("Melting ecash...")
                                .opacity(state == .melting ? 1 : 0.5)
                        }
                        
                        HStack {
                            if state == .minting {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else if state == .success {
                                Image(systemName: "checkmark.circle.fill")
                            }
                            Text("Minting ecash...")
                                .opacity(state == .minting ? 1 : 0.5)
                        }
                    }
                    .opacity(state == .melting || state == .setup || state == .minting || state == .success ? 1.0 : 0)
                    .animation(.easeInOut(duration: 0.2), value: state)
                    .listRowBackground(Color.clear)
                }
            }
            VStack {
                Spacer()
                
                ActionButton(state: $buttonState)
                    .actionDisabled(toMint == nil ||
                                    amount == nil ||
                                    amount ?? 0 > fromMint?.balance(for: .sat) ?? 0 ||
                                    amount ?? 0 < 0)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    let temp = fromMint
                    fromMint = toMint
                    toMint = temp
                }) {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .disabled(toMint == nil)
            }
        }
        .onAppear {
            buttonState = .idle("Transfer", action: { swap() })
        }
        .navigationTitle("Transfer")
        .navigationBarTitleDisplayMode(.inline)
        .alertView(isPresented: $showAlert, currentAlert: currentAlert)
    }
    
    
    
    private func swap() {
        amountFieldInFocus = false
        
        guard let fromMint, let toMint, let amount, let activeWallet else {
            return
        }
        
        state = .ready
          
        let swapManager = InlineSwapManager(modelContext: modelContext) { swapState in
            switch swapState {
            case .ready:
                state = .ready
            case .loading:
                state = .setup
            case .melting:
                state = .melting
            case .minting:
                state = .minting
            case .success:
                state = .success
                buttonState = .success()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    dismiss()
                }
            case .fail(let error):
                state = .fail
                buttonState = .fail()
                if let error {
                    displayAlert(alert: AlertDetail(with: error))
                } else {
                    displayAlert(alert: AlertDetail(title: "Unknown Error", description: "The operation was not successful but no error was specified."))
                }
            }
        }
        
        swapManager.swap(fromMint: fromMint,
                         toMint: toMint,
                         amount: amount,
                         seed: activeWallet.seed)
        
    }
    
    private func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}
