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
                    case .ready, .none:
                        Text("Swap")
                    case .setup, .melting, .minting:
                        ProgressView()
                        Spacer()
                            .frame(width: 10)
                        Text("Loading...")
                    case .success:
                        Text("Success!")
                            .foregroundStyle(.green)
                    case .fail:
                        Text("Swap Failed")
                            .foregroundStyle(.red)
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
        
        state = .setup
        
        let mintQuoteRequest = CashuSwift.Bolt11.RequestMintQuote(unit: "sat", amount: amount)
        toMint.getQuote(for: mintQuoteRequest) { result in
            switch result {
            case .success((let quote, let mintAttemptEvent)):
                guard let mintQuote = quote as? CashuSwift.Bolt11.MintQuote else {
                    logger.error("returned quote was not a bolt11 mint quote. aborting swap.")
                    return
                }
                
                let meltQuoteRequest = CashuSwift.Bolt11.RequestMeltQuote(unit: "sat",
                                                                          request: mintQuote.request,
                                                                          options: nil)
                fromMint.getQuote(for: meltQuoteRequest) { result in
                    switch result {
                    case .success((let quote, let meltAttemptEvent)):
                        guard let meltQuote = quote as? CashuSwift.Bolt11.MeltQuote else {
                            logger.error("returned quote was not a bolt11 mint quote. aborting swap.")
                            return
                        }
                        
                        guard let selection = fromMint.select(allProofs: allProofs,
                                                              amount: amount + meltQuote.feeReserve,
                                                              unit: .sat) else {
                            displayAlert(alert: AlertDetail(title: "Insufficient funds 💸",
                                                            description: "The wallet was unable to collect enough ecash from \(fromMint.displayName) to complete this transaction."))
                            state = .ready
                            return
                        }
                        
                        selection.selected.setState(.pending)
                        
                        setupDidSucceed(mintAttemptEvent: mintAttemptEvent,
                                        meltAttemptEvent: meltAttemptEvent,
                                        selectedProofs: selection.selected)
                        
                    case .failure(let error):
                        displayAlert(alert: AlertDetail(with: error))
                        state = .ready
                    }
                }
            case .failure(let error):
                displayAlert(alert: AlertDetail(with: error))
                state = .ready
            }
        }
    }
    
    ///Mint and melt quotes were loaded successully
    private func setupDidSucceed(mintAttemptEvent: Event,
                                 meltAttemptEvent: Event,
                                 selectedProofs: [Proof]) {
        // save attempt events
        // update UI
        // start melt
        AppSchemaV1.insert([mintAttemptEvent, meltAttemptEvent], into: modelContext)
        
        guard let meltQuote = meltAttemptEvent.bolt11MeltQuote,
              let fromMint,
              let seed = activeWallet?.seed else {
            return
        }
        
        state = .melting
        
        if meltAttemptEvent.blankOutputs == nil,
           let outputs = try? CashuSwift.generateBlankOutputs(quote: meltQuote,
                                                              proofs: selectedProofs,
                                                              mint: fromMint,
                                                              unit: meltQuote.quoteRequest?.unit ?? "sat",
                                                              seed: seed) {
            logger.debug("no blank outputs were assigned, creating new")
            let blankOutputSet = BlankOutputSet(tuple: outputs)
            meltAttemptEvent.blankOutputs = blankOutputSet
            if let keysetID = outputs.outputs.first?.id {
                fromMint.increaseDerivationCounterForKeysetWithID(keysetID,
                                                                  by: outputs.outputs.count)
            } else {
                logger.error("unable to determine correct keyset to increase det sec counter.")
            }
            try? modelContext.save()
        }
        
        fromMint.melt(for: meltQuote,
                      with: selectedProofs,
                      blankOutputSet: meltAttemptEvent.blankOutputs) { result in
            switch result {
            case .error(let error):
                meltAttemptEvent.proofs = nil
                selectedProofs.setState(.valid)
                logger.error("melt operation failed with error: \(error)")
                displayAlert(alert: AlertDetail(with: error))
                state = .fail
            case .failure:
                selectedProofs.setState(.pending)
                logger.info("payment on mint \(fromMint.url.absoluteString) failed")
                displayAlert(alert: AlertDetail(title: "Swap unsussessful 🚫",
                                                description: """
                                                             The swap operation failed during the Lightning payment, \
                                                             but you can manually retry from the transaction history \
                                                             (first the melt and then the associated mint operation.
                                                             """))
                state = .fail
            case .success(let (change, event)):
                logger.debug("melt operation was successful.")
                selectedProofs.setState(.spent)
                meltingDidSucceed(mintAttemptEvent: mintAttemptEvent,
                                  meltAttemptEvent: meltAttemptEvent,
                                  meltEvent: event,
                                  change: change)
            }
        }
        
    }
    
    ///Melt operation did succeed
    private func meltingDidSucceed(mintAttemptEvent: Event,
                                   meltAttemptEvent: Event,
                                   meltEvent: Event,
                                   change: [Proof]) {
        // hide meltAttemptEvent
        // save melt event
        // update UI
        // start minting
        // save new proofs
        // save mint event
        meltAttemptEvent.visible = false
        AppSchemaV1.insert([meltEvent] + change, into: modelContext)
        state = .minting
        
        guard let toMint, let mintQuote = mintAttemptEvent.bolt11MintQuote else {
            state = .fail
            logger.error("toMint was nil, could not complete minting")
            return
        }
        
        toMint.issue(for: mintQuote) { result in
            switch result {
            case .success((let proofs, let mintEvent)):
                mintingDidSucceed(mintAttemptEvent: mintAttemptEvent,
                                  mintEvent: mintEvent,
                                  proofs: proofs)
            case .failure(let error):
                logger.warning("minting for mint swap failed due to error: \(error)")
                displayAlert(alert: AlertDetail(with: error))
                state = .fail
            }
        }
    }
    
    ///Minting proofs on the new mint succeeded as well, finishes swap operation
    private func mintingDidSucceed(mintAttemptEvent: Event,
                                   mintEvent: Event,
                                   proofs: [Proof]) {
        // hide mintAttemptEvent
        // save mint event and new proofs
        // update UI
        
        mintAttemptEvent.visible = false
        AppSchemaV1.insert(proofs + [mintEvent], into: modelContext)
        state = .success
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            dismiss()
        }
    }
    
    private func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}

#Preview {
    SwapView()
}
