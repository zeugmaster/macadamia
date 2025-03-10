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
    
    enum MintState {
        case none
        case known
        case unknown
        case adding
        case unavailable
    }

    @State private var tokenString: String?
    @State private var token: CashuSwift.Token?
    @State private var unit: Unit = .other
    @State private var loading = false
    @State private var success = false
    @State private var mintState: MintState = .none
    
    @State private var showAlert: Bool = false
    @State private var currentAlert: AlertDetail?
    
    private var totalAmount: Int {
        if let token {
            var amount = 0
            for prooflist in token.proofsByMint.values {
                for p in prooflist {
                    amount += p.amount
                }
            }
            return amount
        }
        return 0
    }

    init(tokenString: String? = nil) {
        self._tokenString = State(initialValue: tokenString)
    }

    var body: some View {
        VStack {
            if let token {
                List {
                    Section {
                        TokenText(text: tokenString ?? "")
                            .frame(idealHeight: 70)
                        HStack {
                            Text("Total Amount: ")
                            Spacer()
                            Text(amountDisplayString(totalAmount, unit: Unit(token.unit) ?? .sat))
                        }
                        .foregroundStyle(.secondary)
                        Text(token.proofsByMint.keys.first ?? "")
                            .foregroundStyle(.secondary)
                        if let tokenMemo = token.memo, !tokenMemo.isEmpty {
                            Text("Memo: \(tokenMemo)")
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("cashu Token")
                    }
                    Section {
                        switch mintState {
                        case .none, .known:
                            EmptyView()
                        case .unknown:
                            HStack {
                                Button {
                                    addMint()
                                } label: {
                                    Text("Unknown Mint. Add it?")
                                }
                                Spacer()
                                Image(systemName: "plus")
                            }
                        case .adding:
                            Text("Adding...")
                        case .unavailable:
                            Button {
                                addMint()
                            } label: {
                                Text("Mint unavailable. Try again?")
                                    .foregroundStyle(.red)
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
                        .disabled(mintState == .adding)
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
            .disabled(tokenString == nil || loading || success || mintState == .adding)
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
        
        guard let activeWallet else {
            return
        }
        
        guard !input.hasPrefix("creq") else {
            displayAlert(alert: AlertDetail(title: "Cashu Payment Request 🫴", description: "macadamia does not yet support payment requests, but will soon™."))
            return
        }
        
        do {
            let t = try input.deserializeToken()
            
            guard t.proofsByMint.count == 1 else {
                displayAlert(alert: AlertDetail(with: macadamiaError.multiMintToken))
                return
            }
            
            self.token = t
            self.tokenString = input
            
            // check if mint is known
            let urlFromToken = t.proofsByMint.keys.first
            if activeWallet.mints.contains(where: { m in
                m.url.absoluteString == urlFromToken
            }) {
                mintState = .known
            } else {
                mintState = .unknown
            }
            
        } catch {
            logger.error("could not decode token from string \(input) \(error)")
            displayAlert(alert: AlertDetail(with: error))
            self.tokenString = nil
        }
    }
    
    func addMint() {
        Task {
            guard let urlString = token?.proofsByMint.keys.first else {
                return
            }
            
            withAnimation {
                mintState = .adding
            }
            
            do {
                guard let url = URL(string: urlString) else {
                    logger.error("mint URL to add does not seem valid.")
                    return
                }
                
                let mint: Mint = try await CashuSwift.loadMint(url: url, type: Mint.self)
                mint.wallet = activeWallet
                mint.proofs = []
                modelContext.insert(mint) // TODO: move to main queue
                try modelContext.save()
                logger.info("added mint \(mint.url.absoluteString) while trying to redeem a token")
                
                withAnimation {
                    mintState = .known
                }
            } catch {
                logger.error("failed to add mint due to error \(error)")
                
                withAnimation {
                    mintState = .unavailable
                }
            }
        }
    }

    private func redeem() {
        
        guard let activeWallet,
              let token else {
            logger.error("""
                         "could not redeem, one or more of the following variables are nil:
                         activeWallet: \(activeWallet.debugDescription)
                         token: \(token.debugDescription)
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
        
        // make sure the mint is known
        guard let mint = activeWallet.mints.first(where: { $0.url.absoluteString == token.proofsByMint.keys.first }) else {
            logger.error("unable to determinw mint to redeem from.")
            displayAlert(alert: AlertDetail(with: macadamiaError.unknownMint(nil)))
            return
        }

        loading = true

        mint.redeem(token: token) { result in
            switch result {
            case .success(let (proofs, event)):
                AppSchemaV1.insert(proofs + [event], into: modelContext)
                
                self.loading = false
                self.success = true
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    dismiss()
                }
                
            case .failure(let error):
                logger.error("could not receive token due to error \(error)")
                displayAlert(alert: AlertDetail(with: error))
                self.loading = false
                self.success = false
                
            }
        }
    }

    private func reset() {
        tokenString = nil
        token = nil
        success = false
        mintState = .none
    }

    private func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}

#Preview {
    ReceiveView()
}
