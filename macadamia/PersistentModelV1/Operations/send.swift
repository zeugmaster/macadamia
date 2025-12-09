import Foundation
import CashuSwift
import OSLog
import SwiftData

fileprivate let sendLogger = Logger(subsystem: "macadamia", category: "SendOperation")

extension AppSchemaV1 {
    
    @MainActor
    static func createToken(mint: Mint,
                            activeWallet: Wallet,
                            amount: Int,
                            memo: String,
                            modelContext: ModelContext,
                            lockingKey: String?) async throws -> CashuSwift.Token {
        
        guard let selection = mint.select(amount: amount, unit: .sat) else {
            throw CashuError.insufficientInputs("")
        }
        
        selection.selected.setState(.pending)
        
        let sendResult = try await CashuSwift.send(inputs: selection.selected.sendable(),
                                                   mint: CashuSwift.Mint(mint),
                                                   amount: amount,
                                                   seed: activeWallet.seed,
                                                   memo: memo,
                                                   lockToPublicKey: lockingKey)
        
        selection.selected.setState(.spent)
        
        let changeProofs = try mint.addProofs(sendResult.change,
                                                      to: modelContext,
                                                      state: .valid,
                                                      increaseDerivationCounter: false)
        
        let sentProofs = try mint.addProofs(sendResult.send,
                                                    to: modelContext,
                                                    state: .pending,
                                                    increaseDerivationCounter: false)
        
        let event = Event.sendEvent(unit: .sat,
                                    shortDescription: "Send",
                                    wallet: activeWallet,
                                    amount: amount,
                                    token: sendResult.token,
                                    longDescription: "",
                                    proofs: [],
                                    memo: memo,
                                    mint: mint)
        
        modelContext.insert(event)
        try modelContext.save()
        
        return sendResult.token
    }
    
}

