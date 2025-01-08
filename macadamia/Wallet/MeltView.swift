import CashuSwift
import SwiftData
import SwiftUI

enum PaymentState {
    case ready
    case loading
    case success
    case failed
}

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
    @State var paymenState: PaymentState = .ready
    
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
                switch paymenState {
                case .ready, .failed:
                    Text("Melt ecash")
                        .frame(maxWidth: .infinity)
                        .padding()
                case .loading:
                    Text("Melting...")
                        .frame(maxWidth: .infinity)
                        .padding()
                case .success:
                    Text("Done!")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .foregroundColor(.green)
                }
            })
            .foregroundColor(.white)
            .buttonStyle(.bordered)
            .padding()
            .bold()
            .toolbar(.hidden, for: .tabBar)
            .disabled(invoiceString.isEmpty || paymenState == .loading || paymenState == .success)
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
        selectedMintBalance = proofsOfSelectedMint.filter({ $0.state == .valid }).sum
    }

    var invoiceAmount: Int? {
        try? CashuSwift.Bolt11.satAmountFromInvoice(pr: invoiceString)
    }
    
    func getQuote() {
        
        guard let selectedMint else {
            logger.warning("unable to get quote, activeWallet or selectedMint is nil")
            return
        }
        
        Task {
            do {
                let quoteRequest = CashuSwift.Bolt11.RequestMeltQuote(unit: "sat", // TODO: REMOVE HARD CODED UNIT
                                                                      request: invoiceString,
                                                                      options: nil)
                
                let (_, event) = try await selectedMint.getQuote(for: quoteRequest)
                
                self.pendingMeltEvent = event
                insert([event])
                
            } catch {
                logger.warning("Unable to get melt quote. error \(error)")
                displayAlert(alert: AlertDetail(with: error))
            }
        }
    }

    func melt() {
        guard let selectedMint,
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
        
//        let selectedUnit:Unit = .sat
        
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
        
        selection.selected.forEach { $0.state = .pending }
        
        paymenState = .loading
        
        Task {
            do {
                
                if let (changeProofs, event) = try await selectedMint.melt(for: quote,
                                                                           with: selection.selected) {
                    // melt was successful
                    paymenState = .success
                    pendingMeltEvent?.visible = false
                    insert(changeProofs + [event])
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        dismiss()
                    }
                } else {
                    // melt was NOT successful
                    paymenState = .failed
                    displayAlert(alert: AlertDetail(title: "Unsuccessful",
                                                    description: """
                                                                 The Lighning invoice could not be \
                                                                 payed by the mint. Please try again later.
                                                                 """))
                }

            } catch {
                // TODO: UI for when quote expires etc.
                
                await MainActor.run {
                    selection.selected.forEach { $0.state = .valid }
                    try? modelContext.save()
                }
                
                logger.error("Melt operation falied with error: \(error)")
                paymenState = .ready
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
    MeltView()
}
