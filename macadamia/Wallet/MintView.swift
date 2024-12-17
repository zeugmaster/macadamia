import CashuSwift
import SwiftData
import SwiftUI

struct MintView: View {
        
    @State var quote: CashuSwift.Bolt11.MintQuote?
    @State var pendingMintEvent: Event?

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]

    @Environment(\.dismiss) private var dismiss
    
    var activeWallet: Wallet? {
        wallets.first
    }

    @State var amountString = ""

    @State var selectedMint:Mint?

    @State var loadingInvoice = false

    @State var minting = false
    @State var mintSuccess = false

    @State var showAlert: Bool = false
    @State var currentAlert: AlertDetail?

    @State private var isCopied = false
    @FocusState var amountFieldInFocus: Bool

    init(quote: CashuSwift.Bolt11.MintQuote? = nil,
         pendingMintEvent: Event? = nil) {
        _quote = State(initialValue: quote)
        _pendingMintEvent = State(initialValue: pendingMintEvent)
        
        if let mint = pendingMintEvent?.mints?.first {
            _selectedMint = State(initialValue: mint)
        }
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    if let quote, let requestDetail = quote.requestDetail {
                        Text(String(requestDetail.amount))
                            .monospaced()
                        Text("sats")
                            .monospaced()
                    } else {
                        TextField("enter amount", text: $amountString)
                            .keyboardType(.numberPad)
                            .monospaced()
                            .focused($amountFieldInFocus)
                            .onSubmit {
                                amountFieldInFocus = false
                            }
                            .onAppear(perform: {
                                amountFieldInFocus = true
                            })
                            .disabled(quote != nil)
                        Text("sats")
                            .monospaced()
                    }
                }
                if let mint = pendingMintEvent?.mints?.first {
                    Text(mint.nickName ?? mint.url.host() ?? mint.url.absoluteString)
                } else {
                    MintPicker(label: "Mint", selectedMint: $selectedMint)
                }
            }
            if let quote {
                Section {
                    HStack {
                        Text("Expires at: ")
                        Spacer()
                        Text(Date(timeIntervalSince1970: TimeInterval(quote.expiry)).formatted())
                    }
                    .foregroundStyle(.secondary)
                    StaticQR(qrCode: generateQRCode(from: quote.request))
                        .padding(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
                    Button {
                        copyToClipboard()
                    } label: {
                        HStack {
                            if isCopied {
                                Text("Copied!")
                                    .transition(.opacity)
                            } else {
                                Text("Copy to clipboard")
                                    .transition(.opacity)
                            }
                            Spacer()
                            Image(systemName: "list.clipboard")
                        }
                    }
                    Button {
                        reset()
                    } label: {
                        HStack {
                            Text("Reset")
                            Spacer()
                            Image(systemName: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("Mint")
        .toolbar(.hidden, for: .tabBar)
        .alertView(isPresented: $showAlert, currentAlert: currentAlert)

        if quote == nil {
            Button(action: {
                getQuote()
                amountFieldInFocus = false
            }, label: {
                HStack {
                    if !loadingInvoice {
                        Text("Request Invoice")
                    } else {
                        ProgressView()
                        Spacer()
                            .frame(width: 10)
                        Text("Loading Invoice...")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .bold()
                .foregroundColor(.white)
            })
            .buttonStyle(.bordered)
            .padding()
            .disabled(amountString.isEmpty || amount <= 0 || loadingInvoice)
        } else {
            Button(action: {
                requestMint()
            }, label: {
                HStack {
                    if minting {
                        ProgressView()
                        Spacer()
                            .frame(width: 10)
                        Text("Minting Tokens...")
                    } else if mintSuccess {
                        Text("Success!")
                            .foregroundStyle(.green)
                    } else {
                        Text("I have paid the \(Image(systemName: "bolt.fill")) Invoice")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .bold()
                .foregroundColor(.white)
            })
            .buttonStyle(.bordered)
            .padding()
            .disabled(minting || mintSuccess)
        }
    }

    // MARK: - LOGIC
    
    func copyToClipboard() {
        UIPasteboard.general.string = quote?.request
        withAnimation {
            isCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                isCopied = false
            }
        }
    }

    var amount: Int {
        return Int(amountString) ?? 0
    }
    
    // getQuote can only be called when UI is not populated
    func getQuote() { // TODO: check continually whether the quote was paid
        
        guard let selectedMint else {
            logger.error("""
                         unable to request quote because one or more of the following variables are nil:
                         selectedMInt: \(selectedMint.debugDescription)
                         """)
            return
        }
        
        loadingInvoice = true
        
        Task {
            do {
                let quoteRequest = CashuSwift.Bolt11.RequestMintQuote(unit: "sat",
                                                                      amount: self.amount)
                
                let (quote, event) = try await selectedMint.getQuote(for: quoteRequest)
                self.quote = quote as? CashuSwift.Bolt11.MintQuote
                loadingInvoice = false
                pendingMintEvent = event
                insert([event])
                
            } catch {
                displayAlert(alert: AlertDetail(error))
                logger.error("""
                             could not get quote from mint \(selectedMint.url.absoluteString) \
                             because of error \(error)
                             """)
                loadingInvoice = false
            }
        }
    }

    func requestMint() {
        
        guard let quote,        // TODO: improve handling
              let selectedMint else {
            logger.error("""
                         unable to request melt because one or more of the following variables are nil:
                         quote: \(quote.debugDescription)
                         selectedMInt: \(selectedMint.debugDescription)
                         """)
            return
        }
        
        minting = true
        
        Task {
            do {
                logger.debug("requesting mint for quote with id \(quote.quote)...")
                                
                let (proofs, event) = try await selectedMint.issue(for: quote)
                
                pendingMintEvent?.visible = false
                minting = false
                mintSuccess = true
                
                insert(proofs + [event])
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    dismiss()
                }
                
            } catch {
                
                displayAlert(alert: AlertDetail(error))
                logger.error("Minting was not successful with mint \(selectedMint.url.absoluteString) due to error \(error)")
                minting = false
            }
        }
    }
    
    @MainActor
    func insert(_ models: [any PersistentModel]) {
        models.forEach({ modelContext.insert($0) })
        do {
            try modelContext.save()
        } catch {
            logger.error("Saving SwiftData model context failed with error: \(error)")
        }
    }

    func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }

    func reset() {
        quote = nil
        amountString = ""
        minting = false
        mintSuccess = false
    }
}

#Preview {
    MintView()
}
