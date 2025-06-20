import Foundation
import CashuSwift

extension AppSchemaV1.Mint {
    
    @MainActor
    func redeem(token: CashuSwift.Token, privateKeyString: String?,
                completion: @escaping (Result<(proofs: [Proof],
                                               event: Event), Error>) -> Void) {
        
        guard let wallet = self.wallet else {
            completion(.failure(macadamiaError.databaseError("mint \(self.url.absoluteString) does not have an associated wallet.")))
            return
        }
        
        Task {
            do {
              
                let (sendableProofs, inputDLEQ, outputDLEQ) = try await CashuSwift.receive(token: token,
                                                                                           of: CashuSwift.Mint(self),
                                                                                           seed: wallet.seed,
                                                                                           privateKey: privateKeyString)
                
                logger.info("DLEQ check on incoming: \(String(describing: outputDLEQ))")
                
                await MainActor.run {
                    let internalProofs = sendableProofs.map { p in
                        let keyset = self.keysets.first(where: { $0.keysetID == p.keysetID } )
                        let fee = keyset?.inputFeePPK
                        let unit = Unit(keyset?.unit)
                        
                        if unit == nil {
                            logger.error("wallet could not determine unit for incoming proofs. defaulting to .sat")
                        }
                        
                        return Proof(p,
                                     unit: unit ?? .sat,
                                     inputFeePPK: fee ?? 0,
                                     state: .valid,
                                     mint: self,
                                     wallet: wallet)
                    }
                    
                    if let usedKeyset = self.keysets.first(where: { $0.keysetID == internalProofs.first?.keysetID }) {
                        self.increaseDerivationCounterForKeysetWithID(usedKeyset.keysetID, by: internalProofs.count)
                    } else {
                        logger.error("""
                                     Could not determine applied keyset! \
                                     This will lead to issues with det sec counter and fee rates.
                                     """)
                    }
                    
                    self.proofs?.append(contentsOf: internalProofs)
                    wallet.proofs.append(contentsOf: internalProofs)
                                
                    
                    logger.info("""
                                receiving \(internalProofs.count) proof(s) with sum \
                                \(internalProofs.sum) from mint \(self.url.absoluteString)
                                """)

                    let event = Event.receiveEvent(unit: .sat,
                                                   shortDescription: "Receive",
                                                   wallet: wallet,
                                                   amount: internalProofs.sum,
                                                   longDescription: "",
                                                   proofs: internalProofs,
                                                   memo: token.memo ?? "",
                                                   mint: self,
                                                   redeemed: true)
                    completion(.success((internalProofs, event)))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
}
