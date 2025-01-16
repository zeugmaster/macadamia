//
//  issue.swift
//  macadamia
//
//  Created by zm on 12.12.24.
//

import Foundation
import CashuSwift

extension AppSchemaV1.Mint {
    
    func issue(for quote: CashuSwift.Bolt11.MintQuote) async throws -> (proofs: [Proof],
                                                                        event: Event) {
        
        guard let wallet = self.wallet else {
            throw macadamiaError.databaseError("mint \(self.url.absoluteString) does not have an associated wallet.")
        }
        
        let proofs: [Proof] = try await CashuSwift.issue(for: quote, on: self,
                                                         seed: wallet.seed).map { p in
            let unit = Unit(quote.requestDetail?.unit ?? "other") ?? .other
            return Proof(p,
                         unit: unit,
                         inputFeePPK: 0,
                         state: .valid,
                         mint: self,
                         wallet: wallet)
        }
        
        // replace keyset to persist derivation counter
        self.increaseDerivationCounterForKeysetWithID(proofs.first!.keysetID,
                                                              by: proofs.count)
        let keysetFee = self.keysets.first(where: { $0.keysetID == proofs.first?.keysetID })?.inputFeePPK ?? 0
        proofs.forEach({ $0.inputFeePPK = keysetFee })
        
        // FIXME: for some reason SwiftData does not manage the inverse relationship here, so we have to do it ourselves
        self.proofs?.append(contentsOf: proofs)
        wallet.proofs.append(contentsOf: proofs)
        
        let event = Event.mintEvent(unit: Unit(quote.requestDetail?.unit) ?? .other,
                                    shortDescription: "Mint",
                                    wallet: wallet,
                                    quote: quote,
                                    mint: self,
                                    amount: quote.requestDetail?.amount ?? 0)
        
        return (proofs, event)
    }
    
    func issue (for quote: CashuSwift.Bolt11.MintQuote,
                completion: @escaping (Result<(proofs: [Proof],
                                               event: Event), Error>) -> Void) {
        
        guard let wallet = self.wallet else {
            completion(.failure(macadamiaError.databaseError("mint \(self.url.absoluteString) does not have an associated wallet.")))
            return
        }
        
        let sendableMint = self.sendable
        let seed = wallet.seed
        
        Task {
            do {
                print("Starting issuance on thread: \(Thread.current)")
                let sendableProofs = try await CashuSwift.issue(for: quote, on: sendableMint, seed: seed).map({ SendableProof(from: $0) })
                DispatchQueue.main.sync {
                    print("Completing issuance on thread: \(Thread.current)")
                    
                    let proofs = sendableProofs.map { p in
                        let unit = Unit(quote.requestDetail?.unit ?? "other") ?? .other
                        return Proof(p,
                                     unit: unit,
                                     inputFeePPK: 0,
                                     state: .valid,
                                     mint: self,
                                     wallet: wallet)
                    }
                    
                    self.increaseDerivationCounterForKeysetWithID(proofs.first!.keysetID,
                                                                          by: proofs.count)
                    let keysetFee = self.keysets.first(where: { $0.keysetID == proofs.first?.keysetID })?.inputFeePPK ?? 0
                    proofs.forEach({ $0.inputFeePPK = keysetFee })
                    
                    // FIXME: for some reason SwiftData does not manage the inverse relationship here, so we have to do it ourselves
                    self.proofs?.append(contentsOf: proofs)
                    wallet.proofs.append(contentsOf: proofs)
                    
                    let event = Event.mintEvent(unit: Unit(quote.requestDetail?.unit) ?? .other,
                                                shortDescription: "Mint",
                                                wallet: wallet,
                                                quote: quote,
                                                mint: self,
                                                amount: quote.requestDetail?.amount ?? 0)
                    completion(.success((proofs, event)))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
        
    }
}




