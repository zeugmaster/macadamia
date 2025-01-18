import Foundation
import CashuSwift

extension AppSchemaV1.Mint {
    
    ///This function performs database related operations and library calls for a melt.
    ///Returning a result means the operation was successful,
    ///returning a nil value instead of the results tuple means the lightning payment was unsuccessful
    func melt(for quote: CashuSwift.Bolt11.MeltQuote,
              with proofs: [Proof]) async throws -> (changeProofs: [Proof],
                                                     event: Event)? {
        
        guard let wallet = self.wallet else {
            throw macadamiaError.databaseError("mint \(self.url.absoluteString) does not have an associated wallet.")
        }
        
        logger.debug("Attempting to melt...")
        
        let meltResult = try await CashuSwift.melt(mint: self,
                                                   quote: quote,
                                                   proofs: proofs,
                                                   seed: wallet.seed)
        
        let result: ([Proof], Event)?
        
        if meltResult.paid {
            
            logger.debug("Melt function returned a quote with state PAID")
            
            var internalChangeProofs = [Proof]()
            
            if !meltResult.change.isEmpty,
               let changeKeyset = self.keysets.first(where: { $0.keysetID == meltResult.change.first?.keysetID }) {
                
                logger.debug("Melt quote includes change, attempting saving to db.")
                
                let unit = Unit(changeKeyset.unit) ?? .other
                let inputFee = changeKeyset.inputFeePPK
                
                internalChangeProofs = meltResult.change.map({ Proof($0,
                                                                     unit: unit,
                                                                     inputFeePPK: inputFee,
                                                                     state: .valid,
                                                                     mint: self,
                                                                     wallet: wallet) })
                
                self.proofs?.append(contentsOf: internalChangeProofs)
                wallet.proofs.append(contentsOf: internalChangeProofs)
                
                self.increaseDerivationCounterForKeysetWithID(changeKeyset.keysetID,
                                                              by: meltResult.derivationCounterIncrease)
            }
            
            // this does not seem to work because it is not reflected in the database
            proofs.forEach { $0.state = .spent }

            // make pending melt event non visible and create melt event for history
            let meltEvent = Event.meltEvent(unit: .sat, // FIXME: remove hard coded unit
                                            shortDescription: "Melt",
                                            wallet: wallet,
                                            amount: (quote.amount),
                                            longDescription: "",
                                            mints: [self])
            
            result = (internalChangeProofs, meltEvent)
        } else {
            logger.info("""
                        Melt function returned a quote with state NOT PAID, \
                        probably because the lightning payment failed
                        """)
            
            proofs.forEach { $0.state = .valid }
            result = nil
        }
        
        return result
    }
    
    
    func melt(for quote: CashuSwift.Bolt11.MeltQuote,
              with proofs: [Proof],
              completion: @escaping (PaymentResult) -> Void) -> BlankOutputSet?  {
        
        guard let wallet = self.wallet else {
            completion(.error(macadamiaError.databaseError("mint \(self.url.absoluteString) does not have an associated wallet.")))
            return nil
        }
        
        let sendableMint = self.sendable
        let seed = wallet.seed
        let unit = Unit(quote.quoteRequest?.unit) ?? .sat
        
        let blankOutputs = try? CashuSwift.generateBlankOutputs(quote: quote,
                                                                proofs: proofs,
                                                                mint: self,
                                                                unit: unit.rawValue,
                                                                seed: seed)
        
        Task {
            do {
                logger.debug("Attempting to melt...")
                
                let meltResult = try await CashuSwift.melt(mint: self,
                                                           quote: quote,
                                                           proofs: proofs,
                                                           seed: wallet.seed,
                                                           blankOutputs: blankOutputs)
                
                if meltResult.paid {
                    // make sendable change proofs
                    let sendableProofs = meltResult.change.sendable
                    // ON MAIN: create event and return internal change proofs
                    DispatchQueue.main.async {
                        var internalChangeProofs = [Proof]()
                        
                        if !meltResult.change.isEmpty,
                           let changeKeyset = self.keysets.first(where: { $0.keysetID == meltResult.change.first?.keysetID }) {
                            
                            logger.debug("Melt quote includes change, attempting saving to db.")
                            
                            let unit = Unit(changeKeyset.unit) ?? .other
                            let inputFee = changeKeyset.inputFeePPK
                            
                            internalChangeProofs = sendableProofs.map({ Proof($0,
                                                                                 unit: unit,
                                                                                 inputFeePPK: inputFee,
                                                                                 state: .valid,
                                                                                 mint: self,
                                                                                 wallet: wallet) })
                            
                            self.proofs?.append(contentsOf: internalChangeProofs)
                            wallet.proofs.append(contentsOf: internalChangeProofs)
                        }
                        
                        let meltEvent = Event.meltEvent(unit: .sat, // FIXME: remove hard coded unit
                                                        shortDescription: "Melt",
                                                        wallet: wallet,
                                                        amount: (quote.amount),
                                                        longDescription: "",
                                                        mints: [self])
                        completion(.success((internalChangeProofs, meltEvent)))
                    }
                } else {
                    
                    DispatchQueue.main.async {
                        logger.info("""
                                    Melt function returned a quote with state NOT PAID, \
                                    probably because the lightning payment failed
                                    """)
                        
                        proofs.forEach { $0.state = .valid }
                        completion(.failure);
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.error(error))
                }
            }
        }
        
        if let blankOutputs {
            if let blankOutputKeysetID = Set(blankOutputs.outputs.map({ $0.id })).first {
                self.increaseDerivationCounterForKeysetWithID(blankOutputKeysetID, by: blankOutputs.outputs.count)
            }
            
            return BlankOutputSet(outputs: blankOutputs.outputs,
                                  blindingFactors: blankOutputs.blindingFactors,
                                  secrets: blankOutputs.secrets)
        } else {
            return nil
        }
    }
}

enum PaymentResult {
    case success((change:[Proof], event: Event))
    case failure
    case error(Error)
}
