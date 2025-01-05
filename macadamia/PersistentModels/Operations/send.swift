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
            
            // construct token
//            let proofContainer = CashuSwift.ProofContainer(mint: self.url.absoluteString,
//                                                           proofs: proofs.map({ CashuSwift.Proof($0) }))
            
            token = CashuSwift.Token(proofs: [self.url.absoluteString: proofs],
                                     unit: unit.rawValue,
                                     memo: memo)
            
            let tokenString = try token.serialize(to: .V3)
            

#warning("here we need to write the generalized token instead of a string")
            
            event = Event.sendEvent(unit: unit,
                                    shortDescription: "Send",
                                    wallet: wallet,
                                    amount: targetAmount,
                                    longDescription: "",
                                    proofs: proofs,
                                    memo: memo ?? "",
                                    tokens: [TokenInfo(token: tokenString,
                                                       mint: self.url.absoluteString,
                                                       amount: targetAmount)],
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

//            let proofContainer = CashuSwift.ProofContainer(mint: self.url.absoluteString,
//                                                           proofs: sendProofs.map({ CashuSwift.Proof($0) }))
            
            token = CashuSwift.Token(proofs: [self.url.absoluteString: internalSendProofs],
                                     unit: unit.rawValue,
                                     memo: memo)
            
#warning("here we need to write the generalized token instead of a string")
            
            let tokenString = try token.serialize(to: .V3)
            
            event = Event.sendEvent(unit: unit,
                                        shortDescription: "Send",
                                        wallet: wallet,
                                        amount: targetAmount,
                                        longDescription: "",
                                        proofs: internalSendProofs,
                                        memo: memo ?? "",
                                        tokens: [TokenInfo(token: tokenString,
                                                           mint: self.url.absoluteString,
                                                           amount: internalSendProofs.sum)],
                                        mint: self)
            
            swapped = internalSendProofs + internalChangeProofs

            logger.info("successfully created sendable token.")
        } else {
            logger.critical("amount must not exceed preselected proof sum. .pick() should have returned nil.")
            throw CashuError.invalidAmount
        }
        
        return (token, swapped, event)
    }
}
