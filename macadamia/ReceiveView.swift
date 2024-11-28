import CashuSwift
import SwiftData
import SwiftUI

struct ReceiveView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]

    var activeWallet: Wallet? {
        wallets.first
    }

//    @ObservedObject var qrsVM = QRScannerViewModel()

    @State var tokenString: String?
    @State var token: CashuSwift.Token?
    @State var tokenMemo: String?
    @State var unit: Unit = .other
    @State var loading = false
    @State var success = false
    @State var totalAmount: Int = 0
    @State var addingMint = false

    @State var showAlert: Bool = false
    @State var currentAlert: AlertDetail?

    init(tokenString: String? = nil) {
        self._tokenString = State(initialValue: tokenString)
//        qrsVM.onResult = scannerDidDecodeString(_:)
    }

    var body: some View {
        VStack {
            List {
                if tokenString != nil {
                    Section {
                        TokenText(text: tokenString!)
                            .frame(idealHeight: 70)
                        // TOTAL AMOUNT
                        HStack {
                            Text("Total Amount: ")
                            Spacer()
                            Text(String(totalAmount) + " sats")
                        }
                        .foregroundStyle(.secondary)
                        // TOKEN MEMO
                        if let tokenMemo, !tokenMemo.isEmpty {
                            Text("Memo: \(tokenMemo)")
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("cashu Token")
                    }
                    if let token, let activeWallet {
                        ForEach(token.token, id: \.proofs.first?.C) { fragment in
                            Section {
                                TokenFragmentView(activeWallet: activeWallet,
                                                  fragment: fragment,
                                                  unit: Unit(token.unit) ?? .sat)
                            }
                        }
                    }

                    Section {
                        Button {
                            reset()
                        } label: {
                            HStack {
                                Text("Reset")
                                Spacer()
                                Image(systemName: "trash")
                            }
                        }
                        .disabled(addingMint)
                    }
                } else {
                    // MARK: This check is necessary to prevent a bug in URKit (or the system, who knows)
                    // MARK: from crashing the app when using the camera on an Apple Silicon Mac

                    if !ProcessInfo.processInfo.isiOSAppOnMac {
                        QRScanner(onResult: scannerDidDecodeString(_:))
                            .frame(minHeight: 300, maxHeight: 400)
                            .padding(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
                    }

                    Button {
                        paste()
                    } label: {
                        HStack {
                            Text("Paste from clipboard")
                            Spacer()
                            Image(systemName: "list.clipboard")
                        }
                    }
                }
            }
            .onAppear(perform: {
                if let tokenString {
                    parseTokenString(input: tokenString)
                }
            })
            .alertView(isPresented: $showAlert, currentAlert: currentAlert)
            .navigationTitle("Receive")
            .toolbar(.hidden, for: .tabBar)
            Button(action: {
                redeem()
            }, label: {
                if loading {
                    Text("Sending...")
                        .frame(maxWidth: .infinity)
                        .padding()
                } else if success {
                    Text("Done!")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .foregroundColor(.green)
                } else {
                    Text("Redeem")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            })
            .foregroundColor(.white)
            .buttonStyle(.bordered)
            .padding()
            .bold()
            .toolbar(.hidden, for: .tabBar)
            .disabled(tokenString == nil || loading || success || addingMint)
        }
    }

    // MARK: - LOGIC

    private func paste() {
        let pasteString = UIPasteboard.general.string ?? ""
        logger.info("user pasted string \(pasteString.prefix(20) + (pasteString.count < 20 ? "" : "..."))")
        parseTokenString(input: pasteString)
    }
    
    @MainActor
    private func scannerDidDecodeString(_ string: String) {
        parseTokenString(input: string)
    }

    @MainActor
    private func parseTokenString(input: String) {
        
        guard !input.isEmpty else {
            logger.error("pasted string was empty.")
            return
        }
        
        do {
            let t = try input.deserializeToken()
            self.token = t
            self.totalAmount = 0
            self.token?.token.forEach({ totalAmount += $0.proofs.sum })
            self.tokenString = input
        } catch {
            logger.error("could not decode token from string \(input) \(error)")
            displayAlert(alert: AlertDetail(title: "Could not decode token",
                                            description: String(describing: error)))
            self.tokenString = nil
        }
    }

    private func redeem() {
        guard let activeWallet, let token, let tokenString else {
            logger.error("""
                         "could not redeem, one or more of the following variables are nil:
                         activeWallet: \(activeWallet.debugDescription)
                         token: \(token.debugDescription)
                         """)
            return
        }

        let mintsInToken = activeWallet.mints.filter { mint in
            token.token.contains { fragment in
                mint.url.absoluteString == fragment.mint
            }
        }

        guard mintsInToken.count == token.token.count else {
            logger.error("mintsInToken.count does not equal token.token.count")
            displayAlert(alert: AlertDetail(title: "Unable to redeem",
                                            description: "Are all mints from this token known to the wallet?"))
            return
        }

        loading = true

        var combinedProofs: [Proof] = []

        Task {
            do {
                logger.debug("attempting to receive token...")
                let proofsDict = try await mintsInToken.receive(token: token, seed: activeWallet.seed)
                for mint in mintsInToken {
                    let proofsPerMint = proofsDict[mint.url.absoluteString]!
                    let internalProofs = proofsPerMint.map { p in
                        let keyset = mint.keysets.first(where: { $0.keysetID == p.keysetID } )
                        let fee = keyset?.inputFeePPK
                        let unit = Unit(keyset?.unit)
                        
                        if unit == nil {
                            logger.error("wallet could not determine unit for incoming proofs. defaulting to .sat")
                        }
                        
                        return Proof(p,
                                     unit: unit ?? .sat,
                                     inputFeePPK: fee ?? 0,
                                     state: .valid,
                                     mint: mint,
                                     wallet: activeWallet)
                    }
                    
                    if let usedKeyset = mint.keysets.first(where: { $0.keysetID == internalProofs.first?.keysetID }) {
                        mint.increaseDerivationCounterForKeysetWithID(usedKeyset.keysetID, by: internalProofs.count)
                    } else {
                        logger.error("""
                                     Could not determine applied keyset! \
                                     This will lead to issues with det sec counter and fee rates.
                                     """)
                    }
                    
                    mint.proofs?.append(contentsOf: internalProofs)
                    activeWallet.proofs.append(contentsOf: internalProofs)
                    
                    internalProofs.forEach { modelContext.insert($0) }
                    
                    combinedProofs.append(contentsOf: internalProofs)
                    
                    logger.info("""
                                receiving \(internalProofs.count) proof(s) with sum \
                                \(internalProofs.sum) from mint \(mint.url.absoluteString)
                                """)
                }
                
                let tokenInfo = TokenInfo(token: tokenString,
                                          mint: mintsInToken.count == 1 ? mintsInToken.first!.url.absoluteString : "Multi Mint",
                                          amount: combinedProofs.sum)
                
                let event = Event.receiveEvent(unit: .sat,
                                               shortDescription: "Receive",
                                               wallet: activeWallet,
                                               amount: combinedProofs.sum,
                                               longDescription: "",
                                               proofs: combinedProofs,
                                               memo: token.memo ?? "",
                                               tokens: [tokenInfo],
                                               redeemed: true)
                
                try await MainActor.run {
                    modelContext.insert(event)
                    try modelContext.save()
                    
                    logger.info("successfully added ecash to the database.")
                    self.loading = false
                    self.success = true
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    dismiss()
                }

            } catch {
                // receive unsuccessful
                logger.error("could not receive token due to error \(error)")
                displayAlert(alert: AlertDetail(error))
                self.loading = false
                self.success = false
            }
        }
    }

    private func reset() {
        tokenString = nil
        tokenMemo = nil
        token = nil
        tokenMemo = nil
        success = false
        addingMint = false
        totalAmount = 0
    }

    private func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}

struct TokenFragmentView: View {
    enum FragmentState {
        case spendable
        case notSpendable
        case mintUnavailable
    }

    @Environment(\.modelContext) private var modelContext

    @State var fragmentState: FragmentState? = .mintUnavailable
    @State var fragment: CashuSwift.ProofContainer
    @State var amount: Int = 0 // will need to change to decimal representation
    @State var unit: Unit = .sat
    @State var addingMint: Bool = false

    @State var unknownMint: Bool?

    var activeWallet: Wallet

    init(activeWallet: Wallet, fragment: CashuSwift.ProofContainer, unit: Unit = .sat) {
        self.activeWallet = activeWallet
        self.fragment = fragment
        self.unit = unit
    }

    var body: some View {
        HStack {
            Text("Amount:")
            Spacer()
            Text(String(amount))
            switch unit {
            case .sat:
                Text("sat")
            case .usd:
                Text("$")
            case .eur:
                Text("€")
            case .other:
                Text("other")
            }
        }
        .onAppear {
            checkFragmentState()
        }
        switch fragmentState {
        case .spendable:
            Text("Token part is valid.")
        case .notSpendable:
            Text("Token part is invalid.")
        case .mintUnavailable:
            Text("Mint unavailable")
        case .none:
            Text("Checking...")
        }
        if let unknownMint {
            if unknownMint {
                Button {
                    addMint()
                } label: {
                    if addingMint {
                        Text("Adding,,,") // TODO: communicate success or failure to the user
                    } else {
                        Text("Unknowm mint. Add it?")
                    }
                }
                .disabled(addingMint)
            }
        }
    }

    func checkFragmentState() {
        guard let url = URL(string: fragment.mint) else {
            fragmentState = .mintUnavailable
            return
        }
        
        amount = fragment.proofs.sum //

        if activeWallet.mints.contains(where: { $0.url == url }) {
            unknownMint = false
        } else {
            unknownMint = true
        }

        Task {
            do {
                let proofStates = try await CashuSwift.check(fragment.proofs, url: url)
                if proofStates.allSatisfy({ $0 == .unspent }) {
                    fragmentState = .spendable
                } else {
                    fragmentState = .notSpendable
                }
            } catch {
                fragmentState = .mintUnavailable
            }
        }
    }

    func addMint() {
        Task {
            do {
                addingMint = true
                guard let url = URL(string: fragment.mint) else {
                    logger.error("mint URL to add does not seem valid.")
                    addingMint = false
                    return
                }
                let mint: Mint = try await CashuSwift.loadMint(url: url, type: Mint.self)
                mint.wallet = activeWallet
                mint.proofs = []
                modelContext.insert(mint)
                try modelContext.save()
                logger.info("added mint \(mint.url.absoluteString) while trying to redeem a token")
                unknownMint = false
                checkFragmentState()
            } catch {
                logger.error("failed to add mint due to error \(error)")
                unknownMint = true
            }
            addingMint = false
        }
    }
}

#Preview {
    ReceiveView()
}
