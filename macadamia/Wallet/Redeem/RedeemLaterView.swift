import SwiftUI
import CashuSwift
import SwiftData
import secp256k1

struct RedeemLaterView: View {
    let event: Event
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]

    private var activeWallet: Wallet? {
        wallets.first
    }
    
    @State private var showAlert: Bool = false
    @State private var currentAlert: AlertDetail?
    
    @State private var buttonState: ActionButtonState = .idle("")
    
    private var mint: Mint? {
        event.mints?.first
    }
    
    var body: some View {
        List {
            Section {
                HStack {
                    Text("Mint:")
                    Spacer()
                    Text(mint?.displayName ?? "nil")
                }
                .lineLimit(1)
                HStack {
                    Text("Total Amount: ")
                    Spacer()
                    Text(amountDisplayString(event.token?.sum() ?? 0,
                                             unit: event.unit))
                }
                .foregroundStyle(.secondary)
                if let tokenMemo = event.memo, !tokenMemo.isEmpty {
                    Text("Memo: \(tokenMemo)")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("cashu Token")
            }
            .onAppear {
                buttonState = .idle("Redeem", action: {
                    redeem()
                })
            }
            if let tokenLockState {
                LockedTokenBanner(dleqState: dleqResult, lockState: tokenLockState) {
                    EmptyView()
                }
                .listRowBackground(EmptyView())
            }
        }
        ActionButton(state: $buttonState)
            .actionDisabled(false)
    }
    
    private var dleqResult: CashuSwift.Crypto.DLEQVerificationResult {
        if let mint, let proofs = event.token?.proofsByMint.first?.value {
            return (try? CashuSwift.Crypto.checkDLEQ(for: proofs, with: mint)) ?? .noData
        } else {
            return .noData
        }
    }
    
    private var tokenLockState: CashuSwift.Token.LockVerificationResult? {
        guard let token = event.token else {
            return nil
        }
        return try? token.checkAllInputsLocked(to: activeWallet?.publicKeyString)
    }
    
    private func redeem() {
        guard let wallet = activeWallet,
              let mint,
              let token = event.token else {
            return
        }
        
        guard let keyData = wallet.privateKeyData else {
            displayAlert(alert: AlertDetail(title: "Error",
                                            description: "Unable to read private key from database."))
            return
        }
        
        let privateKeyHex = String(bytes: keyData)
        
        buttonState = .loading()
        
        Task {
            do {
                let (proofs, _, _) = try await CashuSwift.receive(token: token,
                                                                  of: CashuSwift.Mint(mint),
                                                                  seed: wallet.seed,
                                                                  privateKey: privateKeyHex)
                
                try await MainActor.run {
                    let internalProofs = try wallet.internalRepresentation(of: proofs,
                                                                       mint: mint,
                                                                       state: .valid)
                    
                    let receiveEvent = Event.receiveEvent(unit: Unit(token.unit) ?? .sat,
                                                   shortDescription: "Receive",
                                                   wallet: wallet,
                                                   amount: internalProofs.sum,
                                                   longDescription: "",
                                                   proofs: internalProofs,
                                                   memo: token.memo,
                                                   mint: mint,
                                                   redeemed: true)
                    
                    AppSchemaV1.insert(internalProofs + [receiveEvent], into: modelContext)
                    event.visible = false
                    try modelContext.save()
                    buttonState = .success()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        dismiss()
                    }
                }
            } catch {
                buttonState = .fail()
                displayAlert(alert: AlertDetail(with: error))
                logger.error("redeeming of locked failed due to error \(error)")
            }
        }
    }
    
    private func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}

extension AppSchemaV1.Wallet {
    
    @MainActor
    func internalRepresentation(of proofs: [CashuSwift.Proof],
                                mint: Mint,
                                state: Proof.State,
                                increaseDerivationCounter: Bool = true) throws -> [Proof] {
         
        let grouped = Dictionary(grouping: proofs, by: { $0.keysetID })
        
        var new = [Proof]()
        for (id, proofsByID) in grouped {
            guard let keyset = mint.keysets.first(where: { $0.keysetID == id }) else {
                throw macadamiaError.unknownKeyset("""
                            The wallet has no record of a keyset \(id) for \
                            mint \(mint.url.absoluteString) and cannot associate proof data.
                            """)
            }
            let internalProofs = proofsByID.map({ Proof($0,
                                                  unit: Unit(keyset.unit) ?? .sat,
                                                  inputFeePPK: keyset.inputFeePPK,
                                                  state: state,
                                                  mint: mint,
                                                  wallet: self) })
            new.append(contentsOf: internalProofs)
            self.proofs.append(contentsOf: internalProofs)
            mint.proofs?.append(contentsOf: internalProofs)
            
            if increaseDerivationCounter {
                mint.increaseDerivationCounterForKeysetWithID(keyset.keysetID,
                                                              by: internalProofs.count)
            }
        }
        return new
    }
}
