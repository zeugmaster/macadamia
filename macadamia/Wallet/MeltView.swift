import CashuSwift
import CodeScanner
import SwiftData
import SwiftUI

struct MeltView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]
    
    @Query private var mints: [Mint]
    @Query private var allProofs: [Proof]

    var activeWallet: Wallet? {
        wallets.first
    }
    
    var proofsOfSelectedMint:[Proof] {
        allProofs.filter { $0.mint == selectedMint }
    }

    var quote: CashuSwift.Bolt11.MeltQuote? {
        pendingMeltEvent?.bolt11MeltQuote
    }
    
    @State var pendingMeltEvent: Event?

    @State var invoiceString: String = ""
    @State var loading = false
    @State var success = false
    
    @State private var selectedMint:Mint?
    
    @State private var selectedMintBalance = 0

    @State private var showAlert: Bool = false
    @State private var currentAlert: AlertDetail?

    init(pendingMeltEvent: Event? = nil) {
        _pendingMeltEvent = State(initialValue: pendingMeltEvent)
        _invoiceString = State(initialValue: quote?.quoteRequest?.request ?? "")
        
        if let mint = pendingMeltEvent?.mints?.first {
            _selectedMint = State(initialValue: mint)
        }
    }

    var body: some View {
        VStack {
            List {
                Section {
                    MintPicker(label: "Pay from", selectedMint: $selectedMint)
                        .onChange(of: selectedMint) { _, _ in
                            updateBalance()
                        }.disabled(pendingMeltEvent != nil)
                    HStack {
                        Text("Balance: ")
                        Spacer()
                        Text(String(selectedMintBalance))
                            .monospaced()
                        Text("sats")
                    }
                    .onAppear {
                        updateBalance()
                    }
                    .foregroundStyle(.secondary)
                }
                .onAppear {
                    if let mint =  pendingMeltEvent?.mints?.first {
                        print("mint for pending event: \(mint.displayName)")
                        selectedMint = mint
                    }
                }
                
                if let pendingMeltEvent {
                    Section {
                        HStack {
                            Text("Quote created at: ")
                            Spacer()
                            Text(pendingMeltEvent.date.formatted())
                        }
                        Text(pendingMeltEvent.bolt11MeltQuote?.quoteRequest?.request ?? "No request")
                            .foregroundStyle(.gray)
                            .monospaced()
                            .lineLimit(3)
                        if let mint = pendingMeltEvent.mints?.first {
                            Text(mint.nickName ?? mint.url.host() ?? mint.url.absoluteString)
                        }
                        if let quote = pendingMeltEvent.bolt11MeltQuote {
                            HStack {
                                Text("Lightning Fee: ")
                                Spacer()
                                Text(String(quote.feeReserve) + " sats") // FIXME: remove unit hard code
                            }
                            .foregroundStyle(.secondary)
                        }
                        if !invoiceString.isEmpty {
                            HStack {
                                Text("Amount: ")
                                Spacer()
                                Text(String(invoiceAmount ?? 0) + " sats") // FIXME: remove unit hard code
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Section {
                        InputView { string in
                            processInputViewResult(string)
                        }
                    }
                }
            }
            
            // MARK: - BUTTON
            Button(action: {
                melt()
            }, label: {
                if loading {
                    Text("Melting...")
                        .frame(maxWidth: .infinity)
                        .padding()
                } else if success {
                    Text("Done!")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .foregroundColor(.green)
                } else {
                    Text("Melt ecash")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            })
            .foregroundColor(.white)
            .buttonStyle(.bordered)
            .padding()
            .bold()
            .toolbar(.hidden, for: .tabBar)
            .disabled(invoiceString.isEmpty || loading || success)
            .navigationTitle("Melt")
            .navigationBarTitleDisplayMode(.inline)
            .alertView(isPresented: $showAlert, currentAlert: currentAlert)
        }
    }

    func processInputViewResult(_ string: String) {
        var input = string
        if input.hasPrefix("lightning:") {
            input.removeFirst("lightning:".count)
        }
        guard input.hasPrefix("lnbc") else {
            displayAlert(alert: AlertDetail(title: "Invalid QR",
                                            description: """
                                                         This input does not seem to be of \
                                                         a valid Lighning Network invoice. Please try again.
                                                         """))
            logger.warning("Invalid invoice input. the given string does not seem to be a LN invoice. Input: \(input)")
            return
        }
        invoiceString = input
        getQuote()
    }

    func updateBalance() {
        guard !proofsOfSelectedMint.isEmpty else {
            logger.warning("could not update balance, no proofs available")
            return
        }
        
        selectedMintBalance = proofsOfSelectedMint.filter({ $0.state == .valid }).sum
    }

    var invoiceAmount: Int? {
        try? CashuSwift.Bolt11.satAmountFromInvoice(pr: invoiceString)
    }
    
    // getQuote can only be called when UI is not populated
    func getQuote() {
        
        guard let activeWallet, let selectedMint else {
            logger.warning("unable to get quote, activeWallet or selectedMint is nil")
            return
        }
        
        // needs UI for loading quote, analogous to mint UI
        
        Task {
            do {
                let quoteRequest = CashuSwift.Bolt11.RequestMeltQuote(unit: "sat", // TODO: REMOVE HARD CODED UNIT
                                                                      request: invoiceString,
                                                                      options: nil)
               
                guard let meltQuote = try await CashuSwift.getQuote(mint: selectedMint,
                                                                    quoteRequest: quoteRequest) as? CashuSwift.Bolt11.MeltQuote else {
                    logger.warning("could not parse melt quote as bolt11 quote object")
                    return
                }
                                
                let event = Event.pendingMeltEvent(unit: .sat,
                                                   shortDescription: "Melt Quote",
                                                   wallet: activeWallet,
                                                   quote: meltQuote,
                                                   amount: (meltQuote.amount),
                                                   expiration: Date(timeIntervalSince1970: TimeInterval(meltQuote.expiry)),
                                                   mints: [selectedMint])
                // -- main thread
                await MainActor.run {
                    self.pendingMeltEvent = event
                    modelContext.insert(event)
                    do {
                        try modelContext.save()
                    } catch {
                        print(error)
                    }
                }
            } catch {
                logger.warning("Unable to get melt quote. error \(error)")
                displayAlert(alert: AlertDetail(error))
            }
        }
    }

    func melt() {
        guard let selectedMint,
              let activeWallet,
              let quote
        else {
            logger.warning("""
                            could not melt, one or more of the following required variables is nil.
                            selectedWallet: \(selectedMint.debugDescription)
                            activeWallet: \(activeWallet.debugDescription)
                            quote: \(quote.debugDescription)
                            """)
            return
        }
        
        let selectedUnit:Unit = .sat
        
        // TODO: ADD FEE AMOUNT UI AND INFO

        guard let selection = selectedMint.select(allProofs: proofsOfSelectedMint,
                                                  amount: quote.amount + quote.feeReserve,
                                                  unit: .sat) else {
            displayAlert(alert: AlertDetail(title: "Insufficient funds.",
                                            description: """
                                                         The wallet could not collect enough \
                                                         ecash to settle this payment.
                                                         """))
            logger.info("""
                        insufficient funds, mint.select() could not \
                        collect proofs for the required amount.
                        """)
            return
        }
        
        // this works and is reflected in the database
        selection.selected.forEach { $0.state = .pending }
        
        loading = true

        // TODO: refactor this monstrosity
        
        Task {
            do {
                
                logger.debug("Attempting to melt...")
                
                let meltResult = try await CashuSwift.melt(mint: selectedMint,
                                                           quote: quote,
                                                           proofs: selection.selected,
                                                           seed: activeWallet.seed)
                
                // TODO: temp disable back button (?)

                if meltResult.paid {
                    
                    logger.debug("Melt function returned a quote with state PAID")
                    
                    try await MainActor.run {
                        
                        loading = false
                        success = true
                        
                        print(meltResult)
                        selectedMint.keysets.forEach({ print($0.keysetID) })
                        
                        if !meltResult.change.isEmpty,
                           let changeKeyset = selectedMint.keysets.first(where: { $0.keysetID == meltResult.change.first?.keysetID }) {
                            
                            logger.debug("Melt quote includes change, attempting saving to db.")
                            
                            let unit = Unit(changeKeyset.unit) ?? .other
                            let inputFee = changeKeyset.inputFeePPK
                            
                            let internalChangeProofs = meltResult.change.map({ Proof($0,
                                                                                     unit: unit,
                                                                                     inputFeePPK: inputFee,
                                                                                     state: .valid,
                                                                                     mint: selectedMint,
                                                                                     wallet: activeWallet) })
                            
                            selectedMint.proofs?.append(contentsOf: internalChangeProofs)
                            activeWallet.proofs.append(contentsOf: internalChangeProofs)
                            internalChangeProofs.forEach({ modelContext.insert($0) })
                            
                            selectedMint.increaseDerivationCounterForKeysetWithID(changeKeyset.keysetID,
                                                                                  by: internalChangeProofs.count)
                        }
                        
                        // this does not seem to work because it is not reflected in the database
                        selection.selected.forEach { $0.state = .spent }

                        // make pending melt event non visible and create melt event for history
                        let meltEvent = Event.meltEvent(unit: selectedUnit,
                                                        shortDescription: "Melt",
                                                        wallet: activeWallet,
                                                        amount: (quote.amount),
                                                        longDescription: "",
                                                        mints: [selectedMint])
                        
                        pendingMeltEvent?.visible = false
                        modelContext.insert(meltEvent)
                        try modelContext.save()
                        print(meltResult)
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        dismiss()
                    }
                    
                } else {
                    await MainActor.run {
                        logger.info("""
                                    Melt function returned a quote with state NOT PAID, \
                                    probably because the lightning payment failed
                                    """)
                        
                        selection.selected.forEach { $0.state = .valid }
                        loading = false
                        success = false
                        try? modelContext.save()
                        displayAlert(alert: AlertDetail(title: "Unsuccessful",
                                                        description: """
                                                                     The Lighning invoice could not be \
                                                                     payed by the mint. Please try again later.
                                                                     """))
                        
                    }
                }
            } catch {
                // TODO: UI for when quote expires etc.
                
                await MainActor.run {
                    selection.selected.forEach { $0.state = .valid }
                    try? modelContext.save()
                }
                
                logger.error("Melt operation falied with error: \(error)")
                loading = false
                success = false
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
    MeltView()
}
