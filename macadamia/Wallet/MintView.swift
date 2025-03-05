import CashuSwift
import SwiftData
import SwiftUI

struct MintView: View {
    
    @State private var buttonState: ActionButtonState = .idle("Request Invoice")
        
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
        .alertView(isPresented: $showAlert, currentAlert: currentAlert)

        ActionButton(state: $buttonState)
            .actionDisabled(amount < 1 || selectedMint == nil)
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
        
        let quoteRequest = CashuSwift.Bolt11.RequestMintQuote(unit: "sat",
                                                              amount: self.amount)
        
        selectedMint.getQuote(for: quoteRequest) { result in
            print("completion handler exec on main thread: \(Thread.isMainThread)")
            switch result {
            case .success(let (quote, event)):
                self.quote = quote as? CashuSwift.Bolt11.MintQuote
//                loadingInvoice = false
                pendingMintEvent = event
                AppSchemaV1.insert([event], into: modelContext)
                
            case .failure(let error):
                displayAlert(alert: AlertDetail(with: error))
                logger.error("""
                             could not get quote from mint \(selectedMint.url.absoluteString) \
                             because of error \(error)
                             """)
//                loadingInvoice = false
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
        
//        minting = true
                
        selectedMint.issue(for: quote) { result in
            switch result {
            case .success(let (proofs, event)):
                pendingMintEvent?.visible = false
//                minting = false
//                mintSuccess = true
                
                AppSchemaV1.insert(proofs + [event], into: modelContext)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    dismiss()
                }
                
            case .failure(let error):
                displayAlert(alert: AlertDetail(with: error))
                logger.error("Minting was not successful with mint \(selectedMint.url.absoluteString) due to error \(error)")
//                minting = false
            }
        }
    }

    func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }

    func reset() {
        quote = nil
        amountString = ""
    }
}

#Preview {
    MintView()
}
