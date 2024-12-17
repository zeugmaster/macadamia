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
    }

    var body: some View {
        VStack {
            if let tokenString {
                List {
                    Section {
                        TokenText(text: tokenString)
                            .frame(idealHeight: 70)
                        HStack {
                            Text("Total Amount: ")
                            Spacer()
                            Text(String(totalAmount) + " sats")
                        }
                        .foregroundStyle(.secondary)
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
                }
            } else {
                List {
                    InputView { result in
                        parseTokenString(input: result)
                    }
                }
            }
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
        .alertView(isPresented: $showAlert, currentAlert: currentAlert)
        .navigationTitle("Receive")
        .toolbar(.hidden, for: .tabBar)
        .onAppear(perform: {
            if let tokenString {
                parseTokenString(input: tokenString)
            }
        })
    }

    // MARK: - LOGIC

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

        loading = true

        Task {
            do {
                let (combinedProofs, event) = try await activeWallet.redeem(token)
                
                insert(combinedProofs + [event])
                try modelContext.save()
                
                self.loading = false
                self.success = true
                
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
            default:
                EmptyView()
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
