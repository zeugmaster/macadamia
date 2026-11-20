import Foundation
import CashuSwift
import SwiftData

extension AppSchemaV1 {
    enum SendError: LocalizedError {
        case pending
        var errorDescription: String? {
            String(localized: "The mint has not confirmed this send. Your funds remain reserved. Open this send in History to recover it before trying another payment.")
        }
    }

    @MainActor
    static func createToken(mint: Mint, activeWallet: Wallet, amount: Int, unit: Currency.Unit,
                            memo: String, modelContext: ModelContext, lockingKey: String?, network: NetworkController = .shared) async throws -> CashuSwift.Token {
        func select() throws -> CashuSwift.ProofSelectionResult<Proof> {
            try CashuSwift.selectProofs((mint.proofs ?? []).filter { $0.state == .valid },
                targetAmount: amount, mint: mint, unit: unit.currencyCode.lowercased(),
                purpose: lockingKey == nil ? .tokenTransferUnlocked : .tokenTransferLocked)
        }
        func offlineToken(_ selection: CashuSwift.ProofSelectionResult<Proof>) throws -> CashuSwift.Token {
            let token = try CashuSwift.offlineToken(for: selection.selected.sendable(), mint: CashuSwift.Mint(mint), memo: memo)
            selection.selected.setState(.pending)
            let event = Event.sendEvent(unit: unit, shortDescription: "Send", wallet: activeWallet, amount: amount,
                token: token, longDescription: "", proofs: selection.selected, memo: memo, mint: mint)
            event.inputFee = 0
            modelContext.insert(event)
            do { try modelContext.save() } catch { modelContext.rollback(); throw error }
            return token
        }

        var selection = try select()
        if selection.kind == .directToken { return try offlineToken(selection) }

        let session = try await network.session(for: mint.url)
        // Other payments may have reserved proofs or advanced counters while Tor started.
        selection = try select()
        if selection.kind == .directToken { return try offlineToken(selection) }
        let context = try CashuSwift.prepareSend(inputs: selection.selected.sendable(), mint: CashuSwift.Mint(mint),
            amount: amount, seed: activeWallet.seed, memo: memo, lockToPublicKey: lockingKey)
        let contextData = try JSONEncoder().encode(context)
        let event = Event(date: Date(), unit: unit, shortDescription: "Send", visible: true, kind: .send,
            wallet: activeWallet, amount: amount, proofs: selection.selected, memo: memo, mints: [mint])
        event.sendContextData = contextData
        selection.selected.setState(.pending)
        mint.increaseDerivationCounterForKeysetWithID(context.counterIncrease.keysetID, by: context.counterIncrease.increase)
        modelContext.insert(event)
        do { try modelContext.save() } catch { modelContext.rollback(); throw error }

        do {
            let result = try await CashuSwift.send(context: context, from: CashuSwift.Mint(mint), session: session)
            return try completeSend(result, event: event, mint: mint, modelContext: modelContext)
        } catch {
            // A timeout or cancellation can happen after the mint has consumed the inputs.
            throw SendError.pending
        }
    }

    @MainActor
    static func recoverSend(event: Event, modelContext: ModelContext, network: NetworkController = .shared) async throws -> CashuSwift.Token {
        if let token = event.token { return token }
        guard let data = event.sendContextData, let mint = event.mints?.first else { throw SendError.pending }
        let context = try JSONDecoder().decode(CashuSwift.SendContext.self, from: data)
        let result = try await CashuSwift.restoreSend(context: context, from: CashuSwift.Mint(mint),
            session: network.session(for: mint.url))
        // A second recovery may have completed while this one awaited the mint.
        if let token = event.token { return token }
        guard let result else { throw SendError.pending }
        return try completeSend(result, event: event, mint: mint, modelContext: modelContext)
    }

    @MainActor
    private static func completeSend(_ result: CashuSwift.SendResult, event: Event, mint: Mint,
                                     modelContext: ModelContext) throws -> CashuSwift.Token {
        do {
            let inputs = event.proofs ?? []
            event.inputFee = inputs.sum - result.send.sum - result.change.sum
            inputs.setState(.spent)
            try mint.addProofs(result.change, to: modelContext, state: .valid, increaseDerivationCounter: false)
            event.proofs = try mint.addProofs(result.send, to: modelContext, state: .pending, increaseDerivationCounter: false)
            event.token = result.token
            event.sendContextData = nil
            try modelContext.save()
            return result.token
        } catch {
            modelContext.rollback()
            throw error
        }
    }
}
