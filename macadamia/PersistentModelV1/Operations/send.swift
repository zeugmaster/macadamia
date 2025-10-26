import Foundation
import CashuSwift
import OSLog
import SwiftData

fileprivate let sendLogger = Logger(subsystem: "macadamia", category: "SendOperation")

extension AppSchemaV1.Mint {
    
    @MainActor
    func send(amount: Int,
              memo: String?,
              modelContext: ModelContext,
              completion: @escaping (Result<CashuSwift.Token, Error>) -> Void) {
        
        guard let wallet = self.wallet else {
            completion(.failure(macadamiaError.databaseError("mint \(self.url.absoluteString) does not have an associated wallet.")))
            return
        }
        
        let sendableMint = CashuSwift.Mint(self)
        
        guard let selection = self.select(amount: amount, unit: .sat) else {
            completion(.failure(CashuError.insufficientInputs("")))
            return
        }
        
        sendLogger.info("wallet selected \(selection.selected.count) proofs with a total input fee of \(selection.fee)")
        
        selection.selected.setState(.pending)
        
        Task {
            do {
                let sendResult = try await CashuSwift.send(inputs: selection.selected.sendable(),
                                                           mint: sendableMint,
                                                           amount: amount,
                                                           seed: wallet.seed,
                                                           memo: memo,
                                                           lockToPublicKey: nil)
                
                await MainActor.run {
                    
                    do {
                        try self.addProofs(sendResult.change, to: modelContext, increaseDerivationCounter: false)
                        
                        if let counterIncrease = sendResult.counterIncrease {
                            self.increaseDerivationCounterForKeysetWithID(counterIncrease.keysetID,
                                                                          by: counterIncrease.increase)
                        }
                    } catch {
                        sendLogger.error("send operation returned a result, but the \(sendResult.change.count) change proofs could not be saved to the database due to error \(error)")
                    }
                    
                    selection.selected.setState(.spent)
                    
                    let event = Event.sendEvent(unit: .sat,
                                                shortDescription: "Send",
                                                wallet: wallet,
                                                amount: amount,
                                                longDescription: "",
                                                proofs: selection.selected,
                                                memo: memo ?? "",
                                                mint: self)
                    
                    modelContext.insert(event)
                    try? modelContext.save()
                    
                    completion(.success(sendResult.token))
                }
            } catch {
                selection.selected.setState(.valid)
                completion(.failure(error))
            }
        }
    }
}



