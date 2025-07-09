import CashuSwift
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
    
    @State private var buttonState: ActionButtonState = .idle("")
    
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
            if pendingMeltEvent == nil {
                InputView { string in
                    processInputViewResult(string)
                }
                .padding()
            }
            ZStack {
                List {
                    Section {
                        if let pendingMeltEvent {
                            HStack {
                                Text("Mint: ")
                                Spacer()
                                Text(pendingMeltEvent.mints?.first?.displayName ?? "") //FIXME: horrible
                            }
                            .foregroundStyle(.gray)
                        } else {
                            MintPicker(label: "Pay from", selectedMint: $selectedMint)
                                .onChange(of: selectedMint) { _, _ in
                                    updateBalance()
                                }
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
                    .onAppear {
                        if let mint =  pendingMeltEvent?.mints?.first {
                            print("mint for pending event: \(mint.displayName)")
                            selectedMint = mint
                        }
                        buttonState = .idle("Melt", action: initiateMelt)
                        updateBalance()
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
                        
                        Section {
                            Button(role: .destructive) {
                                removeQuote()
                            } label: {
                                HStack {
                                    Text("Remove Quote")
                                    Spacer()
                                    Image(systemName: "trash")
                                }
                            }
                            .disabled(buttonState.type == .fail)
                        } footer: {
                            Text("""
                                 An attempted payment reserves ecash. When a payment fails \
                                 you can reclaim this ecash by removing the melt quote.
                                 """)
                        }
                    }
                    Spacer(minLength: 50)
                        .listRowBackground(Color.clear)
                }
                VStack {
                    Spacer()
                    // MARK: - BUTTON
                    ActionButton(state: $buttonState)
                        .actionDisabled(invoiceString.isEmpty)
                    .navigationTitle("Melt")
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationBarBackButtonHidden(buttonState.type == .loading)
                    .alertView(isPresented: $showAlert, currentAlert: currentAlert)
                }
            }
        }
    }

    private func processInputViewResult(_ string: String) {
        var input = string.lowercased()
        
        if input.hasPrefix("lightning:") {
            input.removeFirst("lightning:".count)
        }
        
        guard input.hasPrefix("lnbc") || // TODO: replace this check with proper invoice decoding
              input.hasPrefix("lntbs") ||
              input.hasPrefix("lntb") ||
              input.hasPrefix("lnbcrt") else {
            displayAlert(alert: AlertDetail(title: "Invalid Input",
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

    private func updateBalance() {
        selectedMintBalance = proofsOfSelectedMint.filter({ $0.state == .valid }).sum
    }

    private var invoiceAmount: Int? {
        try? CashuSwift.Bolt11.satAmountFromInvoice(pr: invoiceString)
    }
    
    private func getQuote() {
        
        guard let selectedMint else {
            logger.warning("unable to get quote, activeWallet or selectedMint is nil")
            return
        }
        
        let quoteRequest = CashuSwift.Bolt11.RequestMeltQuote(unit: "sat",
                                                              request: invoiceString,
                                                              options: nil)
        buttonState = .loading()
        selectedMint.getQuote(for: quoteRequest) { result in
            switch result {
            case .success(let (_, event)):
                self.pendingMeltEvent = event
                AppSchemaV1.insert([event], into: modelContext)
            case .failure(let error):
                logger.warning("Unable to get melt quote. error \(error)")
                displayAlert(alert: AlertDetail(with: error))
            }
            buttonState = .idle("Melt", action: initiateMelt)
        }
    }
    
    private func initiateMelt() {
        guard let selectedMint,
              let quote,
              let pendingMeltEvent,
              let wallet = selectedMint.wallet
        else {
            logger.warning("""
                            could not melt, one or more of the following required variables is nil.
                            selectedWallet: \(selectedMint.debugDescription)
                            activeWallet: \(activeWallet.debugDescription)
                            quote: \(quote.debugDescription)
                            """)
            return
        }
        
        logger.debug("starting melt attempt for quote \(quote.quote)")
        
        buttonState = .loading()
        
        if let proofs = pendingMeltEvent.proofs, !proofs.isEmpty {
            // check melt state
            checkState(mint: selectedMint,
                       quote: quote,
                       proofs: proofs,
                       pendingMeltEvent: pendingMeltEvent,
                       seed: wallet.seed)
        } else {
            // select proofs, assign proofs, mark .pending, persist
            // use .melt
            logger.debug("quote does not have proofs assigned, selecting and melting via .melt()...")
            
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
            
            selection.selected.setState(.pending)
            pendingMeltEvent.proofs = selection.selected
            try? modelContext.save()
            
            melt(mint: selectedMint, quote: quote, proofs: selection.selected, pendingMeltEvent: pendingMeltEvent, seed: wallet.seed)
        }
    }
    
    private func checkState(mint: Mint, quote: CashuSwift.Bolt11.MeltQuote, proofs: [Proof], pendingMeltEvent: Event, seed: String) {
        logger.debug("quote already has proofs assigned, melting via .checkMelt()...")
        
        mint.checkMelt(for: quote,
                               blankOutputSet: pendingMeltEvent.blankOutputs) { result in
            switch result {
            case .error(let error):
                paymentDidFail()
                logger.error("attempt to check and melt failed due to error: \(error)")
                displayAlert(alert: AlertDetail(with: error))
                proofs.setState(.pending)
            case .failure:
                logger.info("payment on mint \(mint.url.absoluteString) failed, trying again...")
                melt(mint: mint, quote: quote, proofs: proofs, pendingMeltEvent: pendingMeltEvent, seed: seed)
                proofs.setState(.pending)
            case .success(let (change, event)):
                logger.debug("melt operation was successful.")
                paymentDidSucceed(with: change, event: event)
                proofs.setState(.spent)
            }
        }
    }

    func melt(mint: Mint, quote: CashuSwift.Bolt11.MeltQuote, proofs: [Proof], pendingMeltEvent: Event, seed: String) {
        // generate blankOutputs, increase counter, assign to event and persist (insert)
        if pendingMeltEvent.blankOutputs == nil,
            let outputs = try? CashuSwift.generateBlankOutputs(quote: quote,
                                                               proofs: proofs,
                                                               mint: mint,
                                                               unit: quote.quoteRequest?.unit ?? "sat",
                                                               seed: seed) {
            logger.debug("no blank outputs were assigned, creating new")
            let blankOutputSet = BlankOutputSet(tuple: outputs)
            pendingMeltEvent.blankOutputs = blankOutputSet
            if let keysetID = outputs.outputs.first?.id {
                mint.increaseDerivationCounterForKeysetWithID(keysetID, by: outputs.outputs.count)
            } else {
                logger.error("unable to determine correct keyset to increase det sec counter.")
            }
            try? modelContext.save()
        }
        
        mint.melt(for: quote,
                  with: proofs,
                  blankOutputSet: pendingMeltEvent.blankOutputs) { result in
            switch result {
            case .error(let error):
                // remove assoc proofs, mark valid, display error
                pendingMeltEvent.proofs = nil
                proofs.setState(.valid)
                logger.error("melt operation failed with error: \(error)")
                displayAlert(alert: AlertDetail(with: error))
                paymentDidFail()
            case .failure:
                proofs.setState(.pending)
                logger.info("payment on mint \(mint.url.absoluteString) failed")
                displayAlert(alert: AlertDetail(title: "Payment unsussessful 🚫", description: "Please try again."))
                paymentDidFail()
            case .success(let (change, event)):
                proofs.setState(.spent)
                logger.debug("melt operation was successful.")
                paymentDidSucceed(with: change, event: event)
            }
        }
    }
    
    private func paymentDidSucceed(with change: [Proof], event: Event) {
        logger.info("change from payment: \(change.count), sum \(change.sum)")
        buttonState = .success()
        self.pendingMeltEvent?.visible = false
        AppSchemaV1.insert(change + [event], into: modelContext)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            dismiss()
        }
    }
    
    private func paymentDidFail() {
        buttonState = .fail()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            buttonState = .idle("Melt", action: initiateMelt)
        }
    }
    
    private func removeQuote() {
        displayAlert(alert: AlertDetail(title: "Are you sure?",
                                        description: "Removing this melt quote will also free up any associated pending ecash.",
                                        primaryButton: AlertButton(title: "Remove", role: .destructive, action: {
            guard let pendingMeltEvent else {
                return
            }
            if let proofs = pendingMeltEvent.proofs {
                proofs.setState(.valid)
                pendingMeltEvent.proofs = nil
            }
            pendingMeltEvent.visible = false
            dismiss()
        }),                             secondaryButton: AlertButton(title: "Cancel", role: .cancel, action: {
            
        })))
    }
    
    private func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}

#Preview {
    MeltView()
}
