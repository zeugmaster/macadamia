import CashuSwift
import SwiftData
import SwiftUI

struct MintView: View {
    
    @State private var buttonState: ActionButtonState
    @EnvironmentObject private var appState: AppState
        
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
    
    @State private var amount: Int = 0
    @State private var selectedMint:Mint?
    @State private var showDetails = false

    @State private var showAlert: Bool = false
    @State private var currentAlert: AlertDetail?

    @State private var isCopied = false
    
    @State private var pollingTimer: Timer?
    @State private var isCheckingInvoiceState = false
    @State private var hasLoggedPollingStart = false

    init(pendingMintEvent: Event? = nil) {
        
        _quote = State(initialValue: pendingMintEvent?.bolt11MintQuote)
        _pendingMintEvent = State(initialValue: pendingMintEvent)
        _buttonState = State(initialValue: .idle("No Action"))
        
        if let mint = pendingMintEvent?.mints?.first {
            _selectedMint = State(initialValue: mint)
        }
        
        // TODO: robust unit handling
        if let quote = pendingMintEvent?.bolt11MintQuote, let detail = quote.requestDetail {
            _amount = State(initialValue: detail.amount)
        }
    }

    var body: some View {
        ZStack {
            Form {
                Section {
                    NumericalInputView(output: $amount,
                                       baseUnit: .sat,
                                       exchangeRates: appState.exchangeRates,
                                       onReturn: {
                        getQuote()
                    })
                    MintPicker(label: "Mint", selectedMint: $selectedMint)
                }
                .disabled(pendingMintEvent != nil)
                if let quote {
                    Section {
                        if let expiry = quote.expiry {
                            HStack {
                                Text("Expires at: ")
                                Spacer()
                                Text(Date(timeIntervalSince1970: TimeInterval(expiry)).formatted())
                            }
                            .foregroundStyle(.secondary)
                        }
                        QRView(string: quote.request)
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
                    }
                    .onAppear { // start the polling timer only when a quote is shown
                        pollingTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true, block: { _ in
                            checkInvoiceState()
                        })
                    }
                    
                    Section {
                        Button {
                            withAnimation {
                                showDetails.toggle()
                            }
                        } label: {
                            HStack {
                                Text("\(showDetails ? "Hide" : "Show") details")
                                    .opacity(0.8)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                                    .font(.footnote)
                                    .rotationEffect(.degrees(showDetails ? 90 : 0))
                            }
                        }
                        
                        if showDetails {
                            CopyableRow(label: "Quote ID", value: quote.quote)
                        }
                    }
                }
                Spacer(minLength: 50)
                    .listRowBackground(Color.clear)
            }
            .navigationTitle("Issue Ecash")
            .alertView(isPresented: $showAlert, currentAlert: currentAlert)
            .onAppear {
                if quote != nil {
                    buttonState = .idle("Issue", action: requestMint)
                } else {
                    buttonState = .idle("Get Invoice", action: getQuote)
                }
            }
            .onDisappear {
                pollingTimer?.invalidate()
            }
            VStack {
                Spacer()
                ActionButton(state: $buttonState)
                    .actionDisabled(amount < 1 || selectedMint == nil)
            }
        }
    }

    // MARK: - LOGIC
    
    private func copyToClipboard() {
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
    
    // getQuote can only be called when UI is not populated
    private func getQuote() { // TODO: check continually whether the quote was paid
        
        guard let selectedMint else {
            logger.error("""
                         unable to request quote because one or more of the following variables are nil:
                         selectedMInt: \(selectedMint.debugDescription)
                         """)
            return
        }
        
        guard amount > 0 else {
            return
        }
        
        let quoteRequest = CashuSwift.Bolt11.RequestMintQuote(unit: "sat",
                                                              amount: self.amount)
        
        buttonState = .loading()
        selectedMint.getQuote(for: quoteRequest) { result in
            print("completion handler exec on main thread: \(Thread.isMainThread)")
            switch result {
            case .success(let (quote, event)):
                self.quote = quote as? CashuSwift.Bolt11.MintQuote
                pendingMintEvent = event
                AppSchemaV1.insert([event], into: modelContext)
                
                buttonState = .idle("Issue Ecash", action: {
                    requestMint()
                })
            case .failure(let error):
                displayAlert(alert: AlertDetail(with: error))
                logger.error("""
                             could not get quote from mint \(selectedMint.url.absoluteString) \
                             because of error \(error)
                             """)
                buttonState = .fail()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    buttonState = .idle("Get Invoice", action: getQuote)
                }
            }
        }
    }
    
    private func checkInvoiceState() {
        guard let quote, let selectedMint else {
            return
        }
        
        if isCheckingInvoiceState { return }
        
        Task {
            do {
                buttonState = .loading()
                if !hasLoggedPollingStart {
                    print("auto polling for quote state with mint \(selectedMint.url.absoluteString) and id \(quote.quote)", terminator: "")
                    fflush(stdout)
                    hasLoggedPollingStart = true
                } else {
                    print(".", terminator: "")
                    fflush(stdout)
                }
                isCheckingInvoiceState = true
                let mintQuote = try await CashuSwift.mintQuoteState(for: quote.quote, mint: CashuSwift.Mint(selectedMint))
                
                if mintQuote.state == .paid || mintQuote.paid == true {
                    print("")  // New line after polling completes
                    isCheckingInvoiceState = false
                    await MainActor.run {
                        requestMint()
                    }
                } else {
                    buttonState = .idle("Issue Ecash", action: { requestMint() })
                    isCheckingInvoiceState = false
                }
            } catch {
                print("")  // New line after error
                buttonState = .idle("Issue Ecash", action: { requestMint() })
                // stop trying automatically if the operation fails
                pollingTimer?.invalidate()
                isCheckingInvoiceState = false
            }
        }
    }
    
    @MainActor
    private func requestMint() {
        
        guard let quote,        // TODO: improve handling
              let selectedMint,
              let activeWallet else {
            logger.error("""
                         unable to request melt because one or more of the following variables are nil:
                         quote: \(quote.debugDescription)
                         selectedMInt: \(selectedMint.debugDescription)
                         """)
            return
        }
        
        pollingTimer?.invalidate()
        
        buttonState = .loading()
        
        Task {
            do {
                let issueResult = try await CashuSwift.issue(for: quote,
                                                             mint: CashuSwift.Mint(selectedMint),
                                                             seed: activeWallet.seed,
                                                             preferredDistribution: nil)
                
                logger.info("DLEQ check on issuance \(String(describing: issueResult.dleqResult))")
                
                try selectedMint.addProofs(issueResult.proofs, to: modelContext)
                
                let event = Event.mintEvent(unit: Unit(quote.requestDetail?.unit) ?? .sat,
                                            shortDescription: "Ecash created",
                                            wallet: activeWallet,
                                            quote: quote,
                                            mint: selectedMint,
                                            amount: quote.requestDetail?.amount ?? issueResult.proofs.sum)
                
                modelContext.insert(event)
                try modelContext.save()
                buttonState = .success()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    dismiss()
                }
            } catch {
                logger.error("an error occurred during issuance \(error)")
                displayAlert(alert: AlertDetail(with: error))
                buttonState = .fail()
            }
        }
    }

    private func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}

#Preview {
    MintView()
}
