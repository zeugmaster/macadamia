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
                            unit: Currency.Unit,
                            memo: String,
                            modelContext: ModelContext,
                            lockingKey: String?) async throws -> CashuSwift.Token {

        guard let selection = mint.select(amount: amount, unit: unit) else {
            throw CashuError.insufficientInputs("")
        }
        
        selection.selected.setState(.pending)
        
        let sendResult: CashuSwift.SendResult
        
        do {
            sendResult = try await CashuSwift.send(inputs: selection.selected.sendable(),
                                                       mint: CashuSwift.Mint(mint),
                                                       amount: amount,
                                                       seed: activeWallet.seed,
                                                       memo: memo,
                                                       lockToPublicKey: lockingKey)
        } catch {
            selection.selected.setState(.valid)
            throw error
        }
        
        let sentProofs: [Proof]
        let swapFee: Int
        if sendResult.send.isEmpty && sendResult.change.isEmpty {
            // Exact-amount direct path: the library skipped the swap and the token
            // is made of the inputs themselves. They are in flight until the
            // recipient redeems them, so keep them pending rather than spent.
            selection.selected.setState(.pending)
            sentProofs = selection.selected
            swapFee = 0
        } else {
            selection.selected.setState(.spent)
            // the library splits inputs into send + keep + fee, so the remainder is the fee
            swapFee = selection.selected.sum - sendResult.send.sum - sendResult.change.sum
            
            try mint.addProofs(sendResult.change,
                               to: modelContext,
                               state: .valid,
                               increaseDerivationCounter: false)
            
            sentProofs = try mint.addProofs(sendResult.send,
                                            to: modelContext,
                                            state: .pending,
                                            increaseDerivationCounter: false)
        }
        
        if let increase = sendResult.counterIncrease {
            mint.increaseDerivationCounterForKeysetWithID(increase.keysetID, by: increase.increase)
        }
        
        let event = Event.sendEvent(unit: unit,
                                    shortDescription: "Send",
                                    wallet: activeWallet,
                                    amount: amount,
                                    token: sendResult.token,
                                    longDescription: "",
                                    proofs: sentProofs,
                                    memo: memo,
                                    mint: mint)
        event.inputFee = swapFee
        
        modelContext.insert(event)
        try modelContext.save()
        
        return sendResult.token
    }
    
}

