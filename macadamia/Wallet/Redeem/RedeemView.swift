import SwiftUI
import SwiftData
import CashuSwift
import OSLog

fileprivate var redeemLogger = Logger(subsystem: "macadamia", category: "redeem")

struct RedeemView<AdditionalControls: View>: View {
        
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(filter: #Predicate<AppSchemaV1.Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [AppSchemaV1.Wallet]
    var activeWallet: AppSchemaV1.Wallet? {
        wallets.first
    }
    
    private let tokenString: String
    private let additionalControls: AdditionalControls?
    private let onSuccess: (() -> Void)?
    
    private let token: CashuSwift.Token?
    
    @State private var buttonState: ActionButtonState = .idle("")
    
    private enum Selection { case add, swap }
    @State private var selection: Selection?
    @State private var swapTargetMint: Mint?
    
    @State private var didAddLockedToken = false
    
    @State private var showAlert: Bool = false
    @State private var currentAlert: AlertDetail?
    
    var hideButtonShadow: Bool {
    #if APP_EXTENSION
        true
    #else
        false
    #endif
    }

    
    init(tokenString: String, @ViewBuilder
         additionalControls: () -> AdditionalControls? = { EmptyView() },
         onSuccess: (() -> Void)? = nil) {
        self.tokenString = tokenString
        self.token = try? tokenString.deserializeToken()
        self.additionalControls = additionalControls()
        self.onSuccess = onSuccess
    }
    
    var body: some View {
        ZStack {
            List {
                Section {
                    if let token {
                        TokenText(text: tokenString)
                            .frame(idealHeight: 60)
                        HStack {
                            Text("Total Amount: ")
                            Spacer()
                            Text(amountDisplayString(token.sum(), unit: Unit(token.unit) ?? .sat))
                        }
                        .foregroundStyle(.secondary)
                        if let tokenMemo = token.memo, !tokenMemo.isEmpty {
                            Text("Memo: \(tokenMemo)")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Unable to decode token.")
                    }
                } header: {
                    Text("cashu Token")
                }
                if let additionalControls {
                    Section {
                        additionalControls
                    }
                }
                
                if let tokenLockState {
                    if let knownMintFromToken {
                        Section {
                            Text(knownMintFromToken.displayName)
                                .onAppear {
                                    buttonState = .idle(String(localized: "Redeem"), action: { redeem() })
                                }
                                .foregroundStyle(.secondary)
                        } header: {
                            Text("Mint")
                        }
                        switch tokenLockState {
                        case .match, .mismatch, .noKey, .partial:
                            LockedTokenBanner(dleqState: dleqResult, lockState: tokenLockState) {
                                Button {
                                    redeemLater()
                                } label: {
                                    Spacer()
                                    if didAddLockedToken {
                                        Image(systemName: "checkmark")
                                        Text(String(localized: "Added"))
                                    } else {
                                        Image(systemName: "hourglass")
                                        Text(String(localized: "Redeem Later"))
                                    }
                                    Spacer()
                                }
                                .padding(2)
                            }
                            .listRowBackground(EmptyView())
                        case .notLocked:
                            EmptyView()
                        }
                    } else {
                        switch tokenLockState {
                        case .match, .mismatch, .noKey, .partial:
                            selector(hideSwapOption: true)
                            LockedTokenBanner(dleqState: dleqResult, lockState: tokenLockState) {
                                EmptyView()
                            }
                            .listRowBackground(EmptyView())
                        case .notLocked:
                            #if APP_EXTENSION
                            selector(hideSwapOption: true)
                                .onAppear {
                                    buttonState = .idle(String(localized: "Select"))
                                }
                            #else
                            selector(hideSwapOption: false)
                                .onAppear {
                                    buttonState = .idle(String(localized: "Select"))
                                }
                            #endif
                        }
                    }
                } else {
                    Text("Error while determining token lock state.")
                }
                Spacer(minLength: 50)
                    .listRowBackground(Color.clear)
            }
            .alertView(isPresented: $showAlert, currentAlert: currentAlert)
            VStack {
                Spacer()
                ActionButton(state: $buttonState, hideShadow: hideButtonShadow)
                    .actionDisabled(knownMintFromToken == nil && selection == nil)
            }
        }
    }
    
    private func selector(hideSwapOption: Bool = false) -> some View {
        Group {
            if let token {
                Section {
                    HStack {
                        Image(systemName: selection == .add ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(selection == .add ? .accentColor : .secondary)
                        Text("Add Mint ")
                        Spacer()
                        if let mintURLString = token.proofsByMint.first?.key {
                            Text(mintURLString.strippingHTTPPrefix())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selection = .add
                        
                        if let mintURLString = token.proofsByMint.first?.key {
                            buttonState = .idle(String(localized: "Add & Redeem"), action: {
                                addAndRedeem(mintURLstring: mintURLString)
                            })
                        }
                    }
                    .onAppear {
                        if hideSwapOption {
                            selection = .add
                            
                            if let mintURLString = token.proofsByMint.first?.key {
                                buttonState = .idle(String(localized: "Add & Redeem"), action: {
                                    addAndRedeem(mintURLstring: mintURLString)
                                })
                            }
                        }
                    }
                } header: {
                    Text("Unknown Mint")
                } footer: {
                    Text("If you trust this mint selecting this option will add it to the list of known mints and redeem the token.")
                }

                if !hideSwapOption {
                    Section {
                        HStack {
                            Image(systemName: selection == .swap ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(selection == .swap ? .accentColor : .secondary)
                            Text("Swap to")
//                            Text("BETA")
//                                .font(.caption)
//                                .padding(2)
//                                .foregroundStyle(.black)
//                                .background(RoundedRectangle(cornerRadius: 5).foregroundStyle(.white.opacity(0.7)))
                            Spacer()
                            MintPicker(label: "", selectedMint: $swapTargetMint, allowsNoneState: false)
                            .pickerStyle(MenuPickerStyle())
                            .labelsHidden()
                            .tint(.secondary)
                            .fixedSize(horizontal: true, vertical: false)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selection = .swap
                            
                            if let swapTargetMint {
                                buttonState = .idle(String(localized: "Swap"), action: { swap(to: swapTargetMint) })
                            }
                        }
                    } footer: {
                        Text("If you do not trust the mint of this token, you can swap its value to one of your trusted mints via Lightning (will incur fees).")
                    }
                }
            } else {
                EmptyView()
            }
        }
        .listStyle(InsetGroupedListStyle())
        .disabled(buttonState.type == .loading)
    }
    
    // MARK: - ADD
    
    private func addAndRedeem(mintURLstring: String) {
        guard let _ = activeWallet, let url = URL(string: mintURLstring) else {
            return
        }
        
        buttonState = .loading()
        
        Task {
            do {
                let sendableMint = try await CashuSwift.loadMint(url: url)
                
                try await MainActor.run {
                    _ = try AppSchemaV1.addMint(sendableMint, to: modelContext)
                    try modelContext.save()
                    redeemLogger.info("adding mint \(sendableMint.url.absoluteString) while trying to redeem a token")
                    redeem()
                }
                
            } catch {
                buttonState = .fail()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    buttonState = .idle(String(localized: "Add and Redeem"), action: redeem)
                }
                redeemLogger.error("could not add mint \(mintURLstring) due to error \(error)")
                displayAlert(alert: AlertDetail(with: error))
            }
        }
    }
    
    // MARK: - REDEEM
    
    @MainActor
    private func redeem() {
        
        guard let activeWallet, let token else {
            redeemLogger.error("""
                         "could not redeem, one or more of the following variables are nil:
                         activeWallet: \(activeWallet.debugDescription)
                         """)
            return
        }
        
        // make sure token is only sat for now
        if token.unit != "sat" {
            displayAlert(alert: AlertDetail(with: macadamiaError.unsupportedUnit))
            return
        }
        
        // make sure the mint is known AND NOT HIDDEN
        guard let mint = activeWallet.mints.first(where: {
                $0.url.absoluteString == token.proofsByMint.keys.first &&
                $0.hidden == false}) else {
            redeemLogger.error("unable to determinw mint to redeem from.")
            return
        }
        
        buttonState = .loading()
        
        let keyString = activeWallet.privateKeyData.map { String(bytes: $0) }
        
        Task {
            do {
                let receiveResult = try await CashuSwift.receive(token: token,
                                                                 of: CashuSwift.Mint(mint),
                                                                 seed: activeWallet.seed,
                                                                 privateKey: keyString) // if the token is not locked the key is ignored
                redeemLogger.info("""
                                  DLEQ verification for input: \(String(describing: receiveResult.inputDLEQ)), 
                                  output: \(String(describing: receiveResult.outputDLEQ))
                                  """)
                
                let proofs = try mint.addProofs(receiveResult.proofs, to: modelContext)
                
                let event = Event.receiveEvent(unit: .sat,
                                               shortDescription: "Receive",
                                               wallet: activeWallet,
                                               amount: proofs.sum,
                                               longDescription: "",
                                               proofs: proofs,
                                               memo: token.memo ?? "",
                                               mint: mint,
                                               redeemed: true)
                
                modelContext.insert(event)
                try modelContext.save()
                
                buttonState = .success()
                
                if let onSuccess {
                    onSuccess()
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    dismiss()
                }
            } catch {
                redeemLogger.error("error during redeeming of token \(error)")
                displayAlert(alert: AlertDetail(with: error))
                buttonState = .fail()
            }
        }
    }
    
    // MARK: - SWAP
    
    private func swap(to mint: Mint) {
        guard let token else {
            return
        }
        
        buttonState = .loading()
        
        let swapManager = InlineSwapManager(modelContext: modelContext) { state in
            switch state {
            case .ready:
                break
            case .loading:
                buttonState = .loading(String(localized: "Preparing..."))
            case .melting:
                buttonState = .loading(String(localized: "Paying..."))
            case .minting:
                buttonState = .loading(String(localized: "Issuing..."))
            case .success:
                buttonState = .success()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    dismiss()
                }
                if let onSuccess {
                    onSuccess()
                }
            case .fail(let error):
                buttonState = .fail()
                redeemLogger.error("could not swap token to mint due to error \(error)")
                if let error {
                    displayAlert(alert: AlertDetail(with: error))
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    buttonState = .idle(String(localized: "Swap"), action: { swap(to: mint) })
                }
            }
        }
        
        if let seed = activeWallet?.seed {
            swapManager.swap(token: token, toMint: mint, seed: seed)
        } else {
            displayAlert(alert: AlertDetail(title: String(localized: "This wallet does not appear to have a seed.")))
        }
    }
    
    // MARK: - REDEEM LATER
    
    private func redeemLater() {
        guard let activeWallet, let knownMintFromToken, let token else {
            return
        }
        
        guard tokenLockState == .match else {
            return
            // show error
        }
        
        let event = Event.pendingReceiveEvent(unit: Unit(token.unit) ?? .sat,
                                              shortDescription: "Pending Receive",
                                              wallet: activeWallet,
                                              amount: token.sum(),
                                              token: token,
                                              memo: token.memo,
                                              mint: knownMintFromToken)
        
        modelContext.insert(event)
        try? modelContext.save()
        
        withAnimation {
            didAddLockedToken = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            dismiss()
        }
        
        if let onSuccess {
            onSuccess()
        }
    }
    
    // MARK: - MISC
    
    private var knownMintFromToken: Mint? {
        let mintURLString = token?.proofsByMint.first?.key
        if let activeWallet {
            return activeWallet.mints.first(where: { $0.url.absoluteString == mintURLString &&
                                                     $0.hidden == false })
        } else {
            return nil
        }
    }
    
    private var dleqResult: CashuSwift.Crypto.DLEQVerificationResult {
        if let knownMintFromToken, let token, let proofs = token.proofsByMint.first?.value {
            return (try? CashuSwift.Crypto.checkDLEQ(for: proofs, with: knownMintFromToken)) ?? .noData
        } else {
            return .noData
        }
    }
    
    private var tokenLockState: CashuSwift.Token.LockVerificationResult? {
        try? token?.checkAllInputsLocked(to: activeWallet?.publicKeyString)
    }
    
    private func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}

extension String {
    func strippingHTTPPrefix() -> String {
        let lower = self.lowercased()
        if lower.hasPrefix("https://") {
            return String(self.dropFirst(8))
        } else if lower.hasPrefix("http://") {
            return String(self.dropFirst(7))
        }
        return self
    }
}

extension Optional where Wrapped == String {
    func strippingHTTPPrefix() -> String? {
        guard let url = self else { return nil }
        return url.strippingHTTPPrefix()
    }
}
