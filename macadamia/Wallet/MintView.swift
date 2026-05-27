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
    @State private var selectedOption: PaymentOption?
    @State private var selectedUnit: Currency.Unit = .sat
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
        _buttonState = State(initialValue: .idle(String(localized: "No Action")))

        if let mint = pendingMintEvent?.mints?.first {
            _selectedMint = State(initialValue: mint)
            if let quote = pendingMintEvent?.bolt11MintQuote {
                _selectedOption = State(initialValue: PaymentOption(mintID: mint.mintID,
                                                                    direction: .mint,
                                                                    unit: Unit(code: quote.unit),
                                                                    method: .bolt11))
            }
        }

        if let quote = pendingMintEvent?.bolt11MintQuote {
            _amount = State(initialValue: quote.amount ?? 0)
            _selectedUnit = State(initialValue: Unit(code: quote.unit))
        }
    }

    var body: some View {
        ZStack {
            Form {
                Section {
                    NumericalInputView(output: $amount,
                                       baseUnit: selectedUnit,
                                       exchangeRates: appState.exchangeRates,
                                       onReturn: {
                        getQuote()
                    })
                    MintPicker(label: String(localized: "Mint"), selectedMint: $selectedMint)
                    PaymentOptionPicker(direction: .mint,
                                        label: String(localized: "Unit"),
                                        selectedMint: $selectedMint,
                                        selectedOption: $selectedOption,
                                        allowedMethods: [.bolt11])
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
                            Task { @MainActor in
                                checkInvoiceState()
                            }
                        })
                    }

                    Section {
                        Button {
                            withAnimation {
                                showDetails.toggle()
                            }
                        } label: {
                            HStack {
                                if showDetails {
                                    Text("Hide details")
                                } else {
                                    Text("Show details")
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                                    .font(.footnote)
                                    .rotationEffect(.degrees(showDetails ? 90 : 0))
                            }
                            .opacity(0.8)
                        }

                        if showDetails {
                            CopyableRow(label: String(localized: "Quote ID"), value: quote.quote)
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
                    buttonState = .idle(String(localized: "Issue"), action: requestMint)
                } else {
                    buttonState = .idle(String(localized: "Get Invoice"), action: getQuote)
                }
            }
            .onChange(of: selectedMint, { oldValue, newValue in
                if let firstUnit = newValue?.supportedUnits.first {
                    selectedUnit = firstUnit
                }
            })
            .onChange(of: selectedOption) { _, newValue in
                if let unit = newValue?.unit {
                    selectedUnit = unit
                }
            }
            .onDisappear {
                pollingTimer?.invalidate()
            }
            VStack {
                Spacer()
                ActionButton(state: $buttonState)
                    .actionDisabled(actionButtonDisabled)
            }
        }
    }

    // MARK: - LOGIC

    private var actionButtonDisabled: Bool {
        if quote == nil {
            return amount < 1 || selectedMint == nil || selectedOption == nil
        }
        return selectedMint == nil
    }

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

        guard let selectedMint, let selectedOption else {
            logger.error("""
                         unable to request quote because one or more of the following variables are nil:
                         selectedMInt: \(selectedMint.debugDescription)
                         selectedOption: \(selectedOption.debugDescription)
                         """)
            return
        }

        guard amount > 0 else {
            return
        }

        let quoteRequest = CashuSwift.Bolt11.MintQuoteRequest(unit: selectedOption.unit.currencyCode.lowercased(),
                                                              amount: self.amount)

        buttonState = .loading()
        selectedMint.getQuote(for: quoteRequest) { result in
            switch result {
            case .success(let (quote, event)):
                self.quote = quote
                pendingMintEvent = event
                AppSchemaV1.insert([event], into: modelContext)

                buttonState = .idle(String(localized: "Issue Ecash"), action: {
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
                    buttonState = .idle(String(localized: "Get Invoice"), action: getQuote)
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
                let mintQuote = try await CashuSwift.Bolt11.mintQuoteState(quote.quote, from: CashuSwift.Mint(selectedMint))

                if mintQuote.state == .paid {
                    print("")  // New line after polling completes
                    isCheckingInvoiceState = false
                    await MainActor.run {
                        requestMint()
                    }
                } else {
                    buttonState = .idle(String(localized: "Issue Ecash"), action: { requestMint() })
                    isCheckingInvoiceState = false
                }
            } catch {
                print("")  // New line after error
                buttonState = .idle(String(localized: "Issue Ecash"), action: { requestMint() })
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
                let issueResult = try await CashuSwift.Bolt11.mint(quote: quote,
                                                                   from: CashuSwift.Mint(selectedMint),
                                                                   seed: activeWallet.seed,
                                                                   preferredDistribution: nil)

                logger.info("DLEQ check on issuance \(String(describing: issueResult.dleqResult))")

                try selectedMint.addProofs(issueResult.proofs, to: modelContext)

                let event = Event.mintEvent(unit: Unit(code: quote.unit),
                                            shortDescription: "Ecash created",
                                            wallet: activeWallet,
                                            quote: quote,
                                            mint: selectedMint,
                                            amount: quote.amount ?? issueResult.proofs.sum)

                modelContext.insert(event)
                try modelContext.save()
                buttonState = .success()

                pendingMintEvent?.visible = false

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
