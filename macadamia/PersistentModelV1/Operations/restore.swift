//
//  Restore.swift
//  macadamia
//
//  Created by zm on 16.01.25.
//

import Foundation
import CashuSwift
import BIP39

extension macadamiaApp {
    static func restore(from mints: [Mint],
                        with words: [String],
                        completion: @escaping (Result<(proofs: [Proof],
                                                       newWallet: Wallet,
                                                       newMints: [Mint],
                                                       event: Event), Error>) -> Void) {
               
        guard let mnemo = try? Mnemonic(phrase: words) else {
            completion(.failure(CashuError.restoreError("Could not generate seed from text input. Please try again.")))
            return
        }
        
        let seed = String(bytes: mnemo.seed)
        
        Task {
            do {
                var resultsListPerMint = [String: [CashuSwift.KeysetRestoreResult]]() // this should be the only object passed across thread boundaries TODO: make explicitly sendable
        
                for oldMint in mints {
                    let proofsByKeyset = try await CashuSwift.restore(mint: oldMint, with: seed, batchSize: 50)
                    resultsListPerMint[oldMint.url.absoluteString] = proofsByKeyset
                }
        
                DispatchQueue.main.async {
                    let newWallet = Wallet(mnemonic: mnemo.phrase.joined(separator: " "),
                                           seed: seed)
        
                    var restoredProofs = [Proof]()
                    var newMints = [Mint]()
        
                    for oldMint in mints {
                        // create new mint
                        let newMint = Mint(url: oldMint.url, keysets: oldMint.keysets)
                        newMint.userIndex = oldMint.userIndex
                        newMint.nickName = oldMint.nickName
                        newMints.append(newMint)            // handle all bi-directional relationship (?)
                        newWallet.mints.append(newMint)     // also here
                        newMint.wallet = newWallet          // and here FIXME: revise AppSchema so this happens automagically
        
                        // unwrap proofs to internal
                        guard let resultList = resultsListPerMint[oldMint.url.absoluteString],
                              !resultList.isEmpty else {
                            continue
                        }
        
                        for result in resultList {
                            let internalProofs = result.proofs.map({ p in
                                Proof(p,
                                      unit: Unit(result.unitString) ?? .sat,
                                      inputFeePPK: result.inputFeePPK,
                                      state: .valid,
                                      mint: newMint,
                                      wallet: newWallet)
                            })
        
                            restoredProofs.append(contentsOf: internalProofs)
                            newMint.proofs?.append(contentsOf: internalProofs)
                            newWallet.proofs.append(contentsOf: internalProofs)
        
                            newMint.increaseDerivationCounterForKeysetWithID(result.keysetID,
                                                                             by: result.derivationCounter)
                        }
        
                        logger.info("""
                                    restored proofs from mint \(newMint.url.absoluteString) \
                                    new keyset derivation counters are: \(resultList.map({ $0.derivationCounter }))
                                    """)
        
        
                    }
        
                    let event = Event.restoreEvent(shortDescription: "Restore",
                                                   wallet: newWallet,
                                                   longDescription: """
                                                                    Successfully recovered ecash \
                                                                    from \(newWallet.mints.count) mints \
                                                                    using a seed phrase! 🤠
                                                                    """)
        
                    completion(.success((restoredProofs, newWallet, newMints, event)))
                }
            } catch {
                completion(.failure(error))
            }
        }
    }
}
