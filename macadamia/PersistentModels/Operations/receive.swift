//
//  receive.swift
//  macadamia
//
//  Created by zm on 12.12.24.
//

import Foundation
import CashuSwift

extension AppSchemaV1.Wallet {
    
    func redeem(_ token: CashuSwift.Token) async throws -> (combinedProofs: [Proof], event: Event) {
        
        let mintsInToken = self.mints.filter { mint in
            token.token.contains { fragment in
                mint.url.absoluteString == fragment.mint
            }
        }

        guard mintsInToken.count == token.token.count else {
            logger.error("mintsInToken.count does not equal token.token.count")
            throw macadamiaError.unknownMint("""
                                             The wallet does not have one or more of the mints \
                                             involved in this operation saved in the database. \
                                             Please make sure all mints are added.
                                             """)
        }
        
        var combinedProofs: [Proof] = []
        
        logger.debug("attempting to receive token...")
        
        let proofsDict = try await mintsInToken.receive(token: token, seed: self.seed)
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
                             wallet: self)
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
            self.proofs.append(contentsOf: internalProofs)
                        
            combinedProofs.append(contentsOf: internalProofs)
            
            logger.info("""
                        receiving \(internalProofs.count) proof(s) with sum \
                        \(internalProofs.sum) from mint \(mint.url.absoluteString)
                        """)
        }
        
        // FIXME: we should not save the token as a string in the db, also not as this TokenInfo object that was only meant for UI
        let tokenInfo = TokenInfo(token: try token.serialize(.V3),
                                  mint: mintsInToken.count == 1 ? mintsInToken.first!.url.absoluteString : "Multi Mint",
                                  amount: combinedProofs.sum)
        
        let event = Event.receiveEvent(unit: .sat,
                                       shortDescription: "Receive",
                                       wallet: self,
                                       amount: combinedProofs.sum,
                                       longDescription: "",
                                       proofs: combinedProofs,
                                       memo: token.memo ?? "",
                                       mints: mintsInToken,
                                       tokens: [tokenInfo],
                                       redeemed: true)
        
        return (combinedProofs, event)
    }
}
