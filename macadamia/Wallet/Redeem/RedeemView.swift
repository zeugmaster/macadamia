import SwiftUI
import SwiftData
import CashuSwift

struct RedeemView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]

    var activeWallet: Wallet? {
        wallets.first
    }
    
    let tokenString: String
    let token: CashuSwift.Token
    
    @State private var buttonState: ActionButtonState = .idle("")
    
    private enum Selection { case add, swap }
    @State private var selection: Selection?
    @State private var swapTargetMint: Mint?
    
    @State private var didAddLockedToken = false
    
    @State private var showAlert: Bool = false
    @State private var currentAlert: AlertDetail?
    
    var body: some View {
        List {
            Section {
                TokenText(text: tokenString)
                    .frame(idealHeight: 70)
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
            } header: {
                Text("cashu Token")
            }
            
            if let tokenLockState {
                if let knownMintFromToken {
                    Section {
                        Text(knownMintFromToken.displayName)
                            .onAppear {
                                buttonState = .idle("Redeem", action: { redeem() })
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
                                Text(didAddLockedToken ? "\(Image(systemName: "checkmark")) Added" : "\(Image(systemName: "hourglass")) Redeem Later")
                                    .padding(2)
                                Spacer()
                            }
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
                        selector()
                            .onAppear {
                                buttonState = .idle("Select")
                            }
                    }
                }
            } else {
                Text("Error while determining token lock state.")
            }
        }
        .alertView(isPresented: $showAlert, currentAlert: currentAlert)
        ActionButton(state: $buttonState)
            .actionDisabled(knownMintFromToken == nil && selection == nil)
    }
    
    private func selector(hideSwapOption: Bool = false) -> some View {
        Group {
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
                        buttonState = .idle("Add & Redeem", action: {
                            addAndRedeem(mintURLstring: mintURLString)
                        })
                    }
                }
                .onAppear {
                    if hideSwapOption {
                        selection = .add
                        
                        if let mintURLString = token.proofsByMint.first?.key {
                            buttonState = .idle("Add & Redeem", action: {
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
                        Text("BETA")
                            .font(.caption)
                            .padding(2)
                            .foregroundStyle(.black)
                            .background(RoundedRectangle(cornerRadius: 5).foregroundStyle(.white.opacity(0.7)))
                        Spacer()
                        MintPicker(label: "", selectedMint: $swapTargetMint, allowsNoneState: false)
                        .pickerStyle(MenuPickerStyle())
                        .labelsHidden()
                        .tint(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selection = .swap
                        
                        if let swapTargetMint {
                            buttonState = .idle("Swap", action: { swap(to: swapTargetMint) })
                        }
                    }
                } footer: {
                    Text("If you do not trust the mint of this token, you can swap its value to one of your trusted mints via Lightning (will incur fees).")
                }
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
                    logger.info("adding mint \(sendableMint.url.absoluteString) while trying to redeem a token")
                    redeem()
                }
                
            } catch {
                buttonState = .fail()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    buttonState = .idle("Add and Redeem", action: redeem)
                }
                logger.error("could not add mint \(mintURLstring) due to error \(error)")
                displayAlert(alert: AlertDetail(with: error))
            }
        }
    }
    
    // MARK: - REDEEM
    
    private func redeem() {
        
        guard let activeWallet else {
            logger.error("""
                         "could not redeem, one or more of the following variables are nil:
                         activeWallet: \(activeWallet.debugDescription)
                         """)
            return
        }
        
        // make sure the token is not P2PK locked
        guard let proofsInToken = token.proofsByMint.values.first,
              !proofsInToken.contains(where: { p in
                  p.secret.contains("P2PK")
              }) else {
            displayAlert(alert: AlertDetail(with: macadamiaError.lockedToken))
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
            logger.error("unable to determinw mint to redeem from.")
            return
        }
        
        mint.redeem(token: token) { result in
            switch result {
            case .success(let (proofs, event)):
                AppSchemaV1.insert(proofs + [event], into: modelContext)
                
                buttonState = .success()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    dismiss()
                }
                
            case .failure(let error):
                buttonState = .fail()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    buttonState = .idle("Receive", action: redeem)
                }
                
                logger.error("could not receive token due to error \(error)")
                displayAlert(alert: AlertDetail(with: error))
            }
        }
    }
    
    // MARK: - SWAP
    
    private func swap(to mint: Mint) {
        let swapManager = SwapManager(modelContext: modelContext) { state in
            switch state {
            case .ready:
                break
            case .loading:
                buttonState = .loading("Preparing...")
            case .melting:
                buttonState = .loading("Melting...")
            case .minting:
                buttonState = .loading("Minting...")
            case .success:
                buttonState = .success()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    dismiss()
                }
            case .fail(let error):
                buttonState = .fail()
                logger.error("could not swap token to mint due to error \(error)")
                if let error {
                    displayAlert(alert: AlertDetail(with: error))
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    buttonState = .idle("Swap", action: { swap(to: mint) })
                }
            }
        }
        
        if let seed = activeWallet?.seed {
            swapManager.swap(token: token, toMint: mint, seed: seed)
        } else {
            displayAlert(alert: AlertDetail(title: "This wallet does not appear to have a seed."))
        }
    }
    
    // MARK: - REDEEM LATER
    
    private func redeemLater() {
        print("add locked token to queue \(tokenString)")
        
        withAnimation {
            didAddLockedToken = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            dismiss()
        }
    }
    
    // MARK: - MISC
    
    private var knownMintFromToken: Mint? {
        let mintURLString = token.proofsByMint.first?.key
        if let activeWallet {
            return activeWallet.mints.first(where: { $0.url.absoluteString == mintURLString &&
                                                     $0.hidden == false })
        } else {
            return nil
        }
    }
    
    private var dleqResult: CashuSwift.Crypto.DLEQVerificationResult {
        if let knownMintFromToken, let proofs = token.proofsByMint.first?.value {
            return (try? CashuSwift.Crypto.checkDLEQ(for: proofs, with: knownMintFromToken)) ?? .noData
        } else {
            return .noData
        }
    }
    
    private var tokenLockState: CashuSwift.Token.LockVerificationResult? {
        try? token.checkAllInputsLocked(to: activeWallet?.publicKeyString)
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
