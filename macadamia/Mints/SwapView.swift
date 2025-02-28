import SwiftUI
import SwiftData
import CashuSwift

struct SwapView: View {
    
    enum PaymentState {
        case none, ready, mintQuote, melting, minting, success, fail
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
        VStack(spacing: 0) { // Main container with no spacing between List and indicators
            // List with form controls
            List {
                Section {
                    MintPicker(label: "From: ", selectedMint: $fromMint, allowsNoneState: false, hide: $toMint)
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
                    Text("The mint from which the ecash originates will charge fees for this operation")
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            if state == .mintQuote {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else if state == .melting || state == .minting || state == .success {
                                Image(systemName: "checkmark.circle.fill")
                            }
                            Text("Getting mint quote...")
                                .opacity(state == .mintQuote ? 1 : 0.5)
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
                    .opacity(state == .melting || state == .mintQuote || state == .minting || state == .success ? 1.0 : 0)
                    .animation(.easeInOut(duration: 0.2), value: state)
                    .listRowBackground(Color.clear)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        let temp = fromMint
                        fromMint = toMint
                        toMint = temp
                        updateState()
                    }) {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .disabled(toMint == nil)
                }
            }
            
            Spacer()
            
            Button(action: {
                initiateSwap()
            }, label: {
                HStack {
                    switch state {
                    case .ready, .fail, .none:
                        Text("Swap")
                    case .mintQuote, .melting, .minting:
                        ProgressView()
                        Spacer()
                            .frame(width: 10)
                        Text("Loading...")
                    case .success:
                        Text("Success!")
                            .foregroundStyle(.green)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .bold()
                .foregroundColor(.white)
            })
            .buttonStyle(.bordered)
            .padding()
            .disabled(state != .ready)
            .opacity(state != .ready ? 0.5 : 1)
        }
        .onChange(of: fromMint, { oldValue, newValue in
            updateState()
        })
        .onChange(of: toMint, { oldValue, newValue in
            updateState()
        })
        .onChange(of: amountString, { oldValue, newValue in
            updateState()
        })
        .navigationTitle("Mint Swap")
        .navigationBarTitleDisplayMode(.inline)
        .alertView(isPresented: $showAlert, currentAlert: currentAlert)
    }
    
    private func updateState() {
        if let toMint,
           let fromMint,
           toMint != fromMint,
           let amount,
           amount > 0 {
            state = .ready
        } else {
            state = .none
        }
    }
    
    ///Get mint and melt quotes from toMint and fromMint and select proofs
    private func initiateSwap() {
        amountFieldInFocus = false
        
        guard let fromMint, let toMint, let amount else {
            return
            // TODO: LOG ERROR
        }
        
        guard let selection = fromMint.select(allProofs: allProofs, amount: amount, unit: .sat) else {
            displayAlert(alert: AlertDetail(title: "Insufficient funds 💸", description: "The wallet was unable to collect enough ecash from \(fromMint.displayName) to complete this transaction."))
            return
        }
        
        let mintQuoteRequest = CashuSwift.Bolt11.RequestMintQuote(unit: "sat", amount: amount)
        
        // errors up to this point should not lead to anything being persisted
    }
    
    ///Mint and melt quotes were loaded successully
    private func setupDidSucceed(mintAttemptEvent: Event,
                                 meltAttemptEvent: Event,
                                 selectedProofs: [Proof]) {
        // save attempt events
        // update UI
        // start melt
        
    }
    
    ///Melt operation did succeed
    private func meltingDidSucceed(mintAttemptEvent: Event,
                                   meltAttemptEvent: Event) {
        // save melt event
        // update UI
        // start minting
        
    }
    
    ///Minting proofs on the new mint succeeded as well, finishes swap operation
    private func mintingDidSucceed() {
        // save mint event and new proofs
        // update UI
        
    }
    
    private func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}

#Preview {
    SwapView()
}
