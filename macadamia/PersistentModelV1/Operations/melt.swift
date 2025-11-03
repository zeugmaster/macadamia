//import Foundation
//import CashuSwift
//import OSLog
//
//fileprivate let meltLogger = Logger(subsystem: "macadamia", category: "MeltOperation")
//
//extension AppSchemaV1.Mint {
//    
//    ///This function performs database related operations and library calls for a melt.
//    ///Returns a payment result type
//    @MainActor
//    func melt(for quote: CashuSwift.Bolt11.MeltQuote,
//              with proofs: [Proof],
//              blankOutputSet: BlankOutputSet?,
//              completion: @escaping (PaymentResult) -> Void)  {
//        
//        guard let wallet = self.wallet else {
//            completion(.error(macadamiaError.databaseError("mint \(self.url.absoluteString) does not have an associated wallet.")))
//            return
//        }
//        
//        let sendableMint = CashuSwift.Mint(self)
//        
//        // TODO: ALLOW FOR DIFFERENT UNITS (from mint quote)
//        _ = Unit(quote.quoteRequest?.unit) ?? .sat
//        
//        let blankOutputs: (outputs: [CashuSwift.Output], blindingFactors: [String], secrets:[String])?
//        
//        if let blankOutputSet {
//            blankOutputs = (blankOutputSet.outputs, blankOutputSet.blindingFactors, blankOutputSet.secrets)
//        } else {
//            blankOutputs = nil
//        }
//        
//        Task {
//            do {
//                meltLogger.debug("Attempting to melt...")
//                
//                let meltResult = try await CashuSwift.melt(with: quote,
//                                                           mint: sendableMint,
//                                                           proofs: proofs.sendable(),
//                                                           blankOutputs: blankOutputs)
//                
//                meltLogger.info("DLEQ check on melt change proofs was\(meltResult.dleqValid ? " " : " NOT ")successful.")
//                
//                if meltResult.paid {
//                    // make sendable change proofs
//                    let sendableProofs = meltResult.change
//                    // ON MAIN: create event and return internal change proofs
//                    await MainActor.run {
//                        var internalChangeProofs = [Proof]()
//                        
//                        if let sendableProofs,
//                           !sendableProofs.isEmpty,
//                           let changeKeyset = sendableMint.keysets.first(where: { $0.keysetID == sendableProofs.first?.keysetID }) {
//                            
//                            meltLogger.debug("Melt quote includes change, attempting saving to db.")
//                            
//                            let unit = Unit(changeKeyset.unit) ?? .other
//                            let inputFee = changeKeyset.inputFeePPK
//                            
//                            internalChangeProofs = sendableProofs.map({ Proof($0,
//                                                                              unit: unit,
//                                                                              inputFeePPK: inputFee,
//                                                                              state: .valid,
//                                                                              mint: self,
//                                                                              wallet: wallet) })
//                            
//                            self.proofs?.append(contentsOf: internalChangeProofs)
//                            wallet.proofs.append(contentsOf: internalChangeProofs)
//                        }
//                        
//                        let meltEvent = Event.meltEvent(unit: .sat, // FIXME: remove hard coded unit
//                                                        shortDescription: "Payment",
//                                                        wallet: wallet,
//                                                        amount: (quote.amount),
//                                                        longDescription: "",
//                                                        mints: [self],
//                                                        meltQuote: quote)
//                        
//                        completion(.success((internalChangeProofs, meltEvent)))
//                    }
//                } else {
//                    DispatchQueue.main.async {
//                        meltLogger.info("""
//                                    Melt function returned a quote with state NOT PAID, \
//                                    probably because the lightning payment failed
//                                    """)
//                        
//                        completion(.failure);
//                    }
//                }
//            } catch {
//                DispatchQueue.main.async {
//                    completion(.error(error))
//                }
//            }
//        }
//    }
//    
//    
//    // MARK: - GET Melt (Quote State) with completion handler
//    @MainActor
//    func checkMelt(for quote: CashuSwift.Bolt11.MeltQuote,
//                   blankOutputSet: BlankOutputSet?,
//                   completion: @escaping (PaymentResult) -> Void)  {
//        
//        guard let wallet = self.wallet else {
//            completion(.error(macadamiaError.databaseError("mint \(self.url.absoluteString) does not have an associated wallet.")))
//            return
//        }
//        
//        let sendableMint = CashuSwift.Mint(self)
//        
//        var blankOutputs: (outputs: [CashuSwift.Output], blindingFactors: [String], secrets:[String])? = nil
//        
//        if let blankOutputSet {
//            blankOutputs = (blankOutputSet.outputs, blankOutputSet.blindingFactors, blankOutputSet.secrets)
//        }
//        
//        Task {
//            do {
//                meltLogger.debug("Attempting to melt...")
//                let meltResult = try await CashuSwift.meltState(for: quote.quote,
//                                                                with: sendableMint,
//                                                                blankOutputs: blankOutputs)
//                
//                if meltResult.quote.state == .paid {
//                    // make sendable change proofs
//                    let sendableProofs = meltResult.change
//                    // ON MAIN: create event and return internal change proofs
//                    await MainActor.run {
//                        var internalChangeProofs = [Proof]()
//                        
//                        if let sendableProofs, !sendableProofs.isEmpty,
//                           let changeKeyset = sendableMint.keysets.first(where: { $0.keysetID == sendableProofs.first?.keysetID }) {
//                            
//                            meltLogger.debug("Melt quote includes change, attempting saving to db.")
//                            
//                            let unit = Unit(changeKeyset.unit) ?? .other
//                            let inputFee = changeKeyset.inputFeePPK
//                            
//                            internalChangeProofs = sendableProofs.map({ Proof($0,
//                                                                              unit: unit,
//                                                                              inputFeePPK: inputFee,
//                                                                              state: .valid,
//                                                                              mint: self,
//                                                                              wallet: wallet) })
//                            
//                            self.proofs?.append(contentsOf: internalChangeProofs)
//                            wallet.proofs.append(contentsOf: internalChangeProofs)
//                        }
//                        
//                        let meltEvent = Event.meltEvent(unit: .sat, // FIXME: remove hard coded unit
//                                                        shortDescription: "Payment",
//                                                        wallet: wallet,
//                                                        amount: (quote.amount),
//                                                        longDescription: "",
//                                                        mints: [self],
//                                                        meltQuote: quote)
//                        completion(.success((internalChangeProofs, meltEvent)))
//                    }
//                } else {
//                    DispatchQueue.main.async {
//                        meltLogger.info("""
//                                    Melt function returned a quote with state NOT PAID, \
//                                    probably because the lightning payment failed
//                                    """)
//                        
//                        completion(.failure);
//                    }
//                }
//            } catch {
//                DispatchQueue.main.async {
//                    completion(.error(error))
//                }
//            }
//        }
//    }
//}
//
//enum PaymentResult {
//    case success((change:[Proof], event: Event))
//    case failure
//    case error(Error)
//}
