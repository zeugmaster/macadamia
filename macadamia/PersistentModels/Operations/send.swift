//
//  send.swift
//  macadamia
//
//  Created by zm on 12.12.24.
//

import Foundation
import CashuSwift

extension AppSchemaV1.Mint {
    
    func send(proofs: [Proof],
              targetAmount: Int,
              memo: String?) async throws -> (token: CashuSwift.Token,
                                              swapped: [Proof],
                                              event: Event) {
        
        guard let wallet = self.wallet else {
            throw macadamiaError.databaseError("mint \(self.url.absoluteString) does not have an associated wallet.")
        }
        
        let units = Set(proofs.map({ $0.unit }))
        
        guard let unit = units.first, units.count == 1 else {
            throw CashuError.unitError("Input proofs seem to contain more than one unit, which is not allowed.")
        }
        
        var token: CashuSwift.Token
        var swapped: [Proof]
        var event: Event
        
        proofs.forEach({ $0.state = .pending })
        
        if targetAmount == proofs.sum {
            logger.debug("target amount and selected proof sum are an exact match, no swap necessary...")
                        
            token = CashuSwift.Token(proofs: [self.url.absoluteString: proofs],
                                     unit: unit.rawValue,
                                     memo: memo)
            
            event = Event.sendEvent(unit: unit,
                                    shortDescription: "Send",
                                    wallet: wallet,
                                    amount: targetAmount,
                                    longDescription: "",
                                    proofs: proofs,
                                    memo: memo ?? "",
                                    mint: self)
            swapped = []
        
        } else if proofs.sum > targetAmount {
            logger.debug("Token amount and selected proof are not a match, swapping...")
            
            // swap to amount specified by user
            let sendProofs: [ProofRepresenting]
            let changeProofs: [ProofRepresenting]
            
            do {
                (sendProofs, changeProofs) = try await CashuSwift.swap(mint: self,
                                                         proofs: proofs,
                                                         amount: targetAmount,
                                                         seed: wallet.seed)
            } catch {
                proofs.forEach({ $0.state = .valid })
                throw error
            }
            
            // increase derivation counter BEFORE any more failure prone operations
            let usedKeyset = self.keysets.first(where: { $0.keysetID == sendProofs.first?.keysetID })
            if let usedKeyset {
                self.increaseDerivationCounterForKeysetWithID(usedKeyset.keysetID,
                                                              by: sendProofs.count + changeProofs.count)
            } else {
                logger.error("Could not determine applied keyset! This will lead to issues with det sec counter and fee rates.")
            }
            
            // if the swap succeeds the input proofs need to be marked as spent
            proofs.forEach({ $0.state = .spent })
            
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

            token = CashuSwift.Token(proofs: [self.url.absoluteString: internalSendProofs],
                                     unit: unit.rawValue,
                                     memo: memo)
            
            event = Event.sendEvent(unit: unit,
                                    shortDescription: "Send",
                                    wallet: wallet,
                                    amount: targetAmount,
                                    longDescription: "",
                                    proofs: internalSendProofs,
                                    memo: memo ?? "",
                                    mint: self)
            
            swapped = internalSendProofs + internalChangeProofs

            logger.info("successfully created sendable token.")
        } else {
            logger.critical("amount must not exceed preselected proof sum. .pick() should have returned nil.")
            throw CashuError.invalidAmount
        }
        
        return (token, swapped, event)
    }
    
    
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
        
        let sendableMint = self.sendable
        let seed = wallet.seed
        
        let units = Set(proofs.map({ $0.unit }))
        
        guard let unit = units.first, units.count == 1 else {
            completion(.failure(CashuError.unitError("Input proofs seem to contain more than one unit, which is not allowed.")))
            return
        }
                
        proofs.forEach({ $0.state = .pending })
        
        if targetAmount == proofs.sum {
            
            logger.debug("target amount and selected proof sum are an exact match, no swap necessary...")
                        
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
                    
                    let sendProofs: [ProofRepresenting]
                    let changeProofs: [ProofRepresenting]
                    
                    (sendProofs, changeProofs) = try await CashuSwift.swap(mint: self,
                                                                           proofs: proofs,
                                                                           amount: targetAmount,
                                                                           seed: wallet.seed)
                    
                    let sendableSendProofs = sendProofs.sendable
                    let sendableChangeProofs = changeProofs.sendable
                    
                    DispatchQueue.main.async {
                        // if the swap succeeds the input proofs need to be marked as spent
                        proofs.forEach({ $0.state = .spent })
                        
                        let usedKeyset = self.keysets.first(where: { $0.keysetID == sendableSendProofs.first?.keysetID })
                        if let usedKeyset {
                            self.increaseDerivationCounterForKeysetWithID(usedKeyset.keysetID,
                                                                          by: sendableSendProofs.count + sendableChangeProofs.count)
                        } else {
                            logger.error("Could not determine applied keyset! This will lead to issues with det sec counter and fee rates.")
                        }
                        
                        let feeRate = usedKeyset?.inputFeePPK ?? 0
                        
                        let internalSendProofs = sendableSendProofs.map({ Proof($0,
                                                                        unit: unit,
                                                                        inputFeePPK: feeRate,
                                                                        state: .pending,
                                                                        mint: self,
                                                                        wallet: wallet) })
                        
                        wallet.proofs.append(contentsOf: internalSendProofs)
                        
                        let internalChangeProofs = sendableChangeProofs.map({ Proof($0,
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

                        logger.info("successfully created sendable token.")
                        completion(.success((token, swapped, event)))
                        return
                    }
                } catch {
                    DispatchQueue.main.async {
                        proofs.forEach({ $0.state = .valid })
                        completion(.failure(error))
                    }
                }
            }
            
        } else {
            logger.critical("amount must not exceed preselected proof sum. .pick() should have returned nil.")
            completion(.failure(CashuError.invalidAmount))
            return
        }
    }
}

extension Array where Element == ProofRepresenting {
    var sendable: [SendableProof] {
        self.map { p in
            SendableProof(from: p)
        }
    }
}


