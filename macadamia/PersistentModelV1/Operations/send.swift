import Foundation
import CashuSwift
import OSLog

fileprivate let sendLogger = Logger(subsystem: "macadamia", category: "SendOperation")

extension AppSchemaV1.Mint {
    
    @MainActor
    func send(proofs: [Proof],
              targetAmount: Int,
              memo: String?,
              completion: @escaping (Result<(token: CashuSwift.Token,
                                             swapped: [Proof], // includes all proofs, properly marked .valid for change and .pending for those included in the token
                                             event: Event), Error>) -> Void) {
        
        guard let wallet = self.wallet else {
            completion(.failure(macadamiaError.databaseError("mint \(self.url.absoluteString) does not have an associated wallet.")))
            return
        }
        
        let sendableMint = CashuSwift.Mint(self)
        
        let units = Set(proofs.map({ $0.unit }))
        
        guard let unit = units.first, units.count == 1 else {
            completion(.failure(CashuError.unitError("Input proofs seem to contain more than one unit, which is not allowed.")))
            return
        }
                
        proofs.setState(.pending)
        
        if targetAmount == proofs.sum {
            
            sendLogger.debug("target amount and selected proof sum are an exact match, no swap necessary...")
                        
            let token = CashuSwift.Token(proofs: [self.url.absoluteString: proofs],
                                     unit: unit.rawValue,
                                     memo: memo)
            
            let event = Event.sendEvent(unit: unit,
                                    shortDescription: "Send",
                                    wallet: wallet,
                                    amount: targetAmount,
                                    longDescription: "",
                                    proofs: proofs,
                                    memo: memo ?? "",
                                    mint: self)
            
            completion(.success((token, [], event)))
            return
        } else if proofs.sum > targetAmount {
            Task {
                do {
                    // swap on background thread

                    let (sendProofs, changeProofs, dleqPassed) = try await CashuSwift.swap(with: sendableMint,
                                                                                          inputs: proofs.sendable(),
                                                                                          amount: targetAmount,
                                                                                          seed: wallet.seed)
                    sendLogger.info("DLEQ check on swapped proofs was\(dleqPassed ? " " : " NOT ")successful.")
                    
                    await MainActor.run {
                        // if the swap succeeds the input proofs need to be marked as spent
                        proofs.forEach({ $0.state = .spent })
                        
                        let usedKeyset = self.keysets.first(where: { $0.keysetID == sendProofs.first?.keysetID })
                        if let usedKeyset {
                            self.increaseDerivationCounterForKeysetWithID(usedKeyset.keysetID,
                                                                          by: sendProofs.count + changeProofs.count)
                        } else {
                            sendLogger.error("Could not determine applied keyset! This will lead to issues with det sec counter and fee rates.")
                        }
                        
                        let feeRate = usedKeyset?.inputFeePPK ?? 0
                        
                        let internalSendProofs = sendProofs.map({ Proof($0,
                                                                        unit: unit,
                                                                        inputFeePPK: feeRate,
                                                                        state: .pending,
                                                                        mint: self,
                                                                        wallet: wallet) })
                        
                        wallet.proofs.append(contentsOf: internalSendProofs)
                        
                        let internalChangeProofs = changeProofs.map({ Proof($0,
                                                                            unit: unit,
                                                                            inputFeePPK: feeRate,
                                                                            state: .valid,
                                                                            mint: self,
                                                                            wallet: wallet) })
                        
                        wallet.proofs.append(contentsOf: internalChangeProofs + internalSendProofs)
                        self.proofs?.append(contentsOf: internalSendProofs + internalChangeProofs)

                        let token = CashuSwift.Token(proofs: [self.url.absoluteString: internalSendProofs],
                                                 unit: unit.rawValue,
                                                 memo: memo)
                        
                        let event = Event.sendEvent(unit: unit,
                                                shortDescription: "Send",
                                                wallet: wallet,
                                                amount: targetAmount,
                                                longDescription: "",
                                                proofs: internalSendProofs,
                                                memo: memo ?? "",
                                                mint: self)
                        
                        let swapped = internalSendProofs + internalChangeProofs

                        sendLogger.info("successfully created sendable token.")
                        completion(.success((token, swapped, event)))
                        return
                    }
                } catch {
                    await MainActor.run {
                        proofs.forEach({ $0.state = .valid })
                        completion(.failure(error))
                    }
                }
            }
            
        } else {
            sendLogger.critical("amount must not exceed preselected proof sum. .pick() should have returned nil.")
            completion(.failure(CashuError.invalidAmount))
            return
        }
    }
}



