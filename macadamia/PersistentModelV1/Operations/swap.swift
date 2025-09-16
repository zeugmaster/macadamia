import Foundation
import SwiftData
import CashuSwift
import OSLog

fileprivate let swapLogger = Logger(subsystem: "macadamia", category: "SwapOperation")


@MainActor
struct SwapManager {
    
    enum State {
        case ready, loading, melting, minting, success
        case fail(error: Error?)
    }
    
    let modelContext: ModelContext
    private let updateHandler: (SwapManager.State) -> Void
    
    init(modelContext: ModelContext, updateHandler: @escaping (SwapManager.State) -> Void) {
        self.modelContext = modelContext
        self.updateHandler = updateHandler
    }
    
    func swap(token: CashuSwift.Token, toMint: AppSchemaV1.Mint, seed: String) {
        // load from mint
        // guess fee by creating dummy quote
        
        updateHandler(.loading)
        
        let tokenSum = token.sum()
        
        guard let mintURLstring = token.proofsByMint.first?.key,
              let mintURL = URL(string: mintURLstring) else {
            // log error
            return
        }
        
        Task {
            do {
                swapLogger.debug("loading mint for untrusted swap \(mintURLstring)...")
                let fromMint = try await CashuSwift.loadMint(url: mintURL)
                
                let dummyMintQuoteRequest = CashuSwift.Bolt11.RequestMintQuote(unit: token.unit, amount: tokenSum)
                guard let dummyMintQuote = try await CashuSwift.getQuote(mint: CashuSwift.Mint(toMint),
                                                                         quoteRequest: dummyMintQuoteRequest) as? CashuSwift.Bolt11.MintQuote else {
                    updateHandler(.fail(error: nil))
                    return
                }
                
                let dummyMeltQuoteRequest = CashuSwift.Bolt11.RequestMeltQuote(unit: token.unit,
                                                                               request: dummyMintQuote.request,
                                                                               options:nil)
                
                guard let dummyMeltQuote = try await CashuSwift.getQuote(mint: fromMint,
                                                                         quoteRequest: dummyMeltQuoteRequest) as? CashuSwift.Bolt11.MeltQuote else {
                    // ...
                    updateHandler(.fail(error: nil))
                    return
                }
                
                guard let proofs = token.proofsByMint.first?.value else {
                    updateHandler(.fail(error: nil))
                    return
                }
                
                let inputFee = try CashuSwift.calculateFee(for: proofs, of: fromMint)
                let swapAmount = tokenSum - dummyMeltQuote.feeReserve - inputFee
                
                try await MainActor.run  {
                    swapLogger.debug("attempting swap from token with total amount \(tokenSum) and swapAmount \(swapAmount)")
                    // proofs from the new mint can be added without counter increase because they are from a diff seed and will be swapped immediately
                    let fromMint = try AppSchemaV1.addMint(fromMint, to: modelContext, hidden: true, proofs: proofs)
                    swap(fromMint: fromMint, toMint: toMint, amount: swapAmount, seed: seed)
                }
            } catch {
                updateHandler(.fail(error: error))
            }
        }
    }
    
    func swap(fromMint: AppSchemaV1.Mint, toMint: AppSchemaV1.Mint, amount: Int, seed: String) {
        updateHandler(.loading)
        
        let mintQuoteRequest = CashuSwift.Bolt11.RequestMintQuote(unit: "sat", amount: amount)
        toMint.getQuote(for: mintQuoteRequest) { result in
            switch result {
            case .success((let quote, let mintAttemptEvent)):
                guard let mintQuote = quote as? CashuSwift.Bolt11.MintQuote else {
                    swapLogger.error("returned quote was not a bolt11 mint quote. aborting swap.")
                    return
                }
                
                let meltQuoteRequest = CashuSwift.Bolt11.RequestMeltQuote(unit: "sat",
                                                                          request: mintQuote.request,
                                                                          options: nil)
                fromMint.getQuote(for: meltQuoteRequest) { result in
                    switch result {
                    case .success((let quote, let meltAttemptEvent)):
                        guard let meltQuote = quote as? CashuSwift.Bolt11.MeltQuote else {
                            swapLogger.error("returned quote was not a bolt11 mint quote. aborting swap.")
                            return
                        }
                        
                        guard let selection = fromMint.select(amount: amount + meltQuote.feeReserve,
                                                              unit: .sat) else {
                            
                            updateHandler(.fail(error: CashuError.insufficientInputs("")))
                            return
                        }
                        
                        selection.selected.setState(.pending)
                        
                        setupDidSucceed(fromMint: fromMint,
                                        toMint: toMint,
                                        seed: seed,
                                        mintAttemptEvent: mintAttemptEvent,
                                        meltAttemptEvent: meltAttemptEvent,
                                        selectedProofs: selection.selected)
                        
                    case .failure(let error):
                        updateHandler(.fail(error: error))
                    }
                }
            case .failure(let error):
                updateHandler(.fail(error: error))
            }
        }
    }
    
    private func setupDidSucceed(fromMint: Mint,
                                 toMint: Mint,
                                 seed: String,
                                 mintAttemptEvent: Event,
                                 meltAttemptEvent: Event,
                                 selectedProofs: [Proof]) {
        
        AppSchemaV1.insert([mintAttemptEvent, meltAttemptEvent], into: modelContext)
        
        guard let meltQuote = meltAttemptEvent.bolt11MeltQuote else {
            updateHandler(.fail(error: nil))
            return
        }
        
        updateHandler(.melting)
        
        if meltAttemptEvent.blankOutputs == nil,
           let outputs = try? CashuSwift.generateBlankOutputs(quote: meltQuote,
                                                              proofs: selectedProofs,
                                                              mint: fromMint,
                                                              unit: meltQuote.quoteRequest?.unit ?? "sat",
                                                              seed: seed) {
            swapLogger.debug("no blank outputs were assigned, creating new")
            let blankOutputSet = BlankOutputSet(tuple: outputs)
            meltAttemptEvent.blankOutputs = blankOutputSet
            if let keysetID = outputs.outputs.first?.id {
                fromMint.increaseDerivationCounterForKeysetWithID(keysetID,
                                                                  by: outputs.outputs.count)
            } else {
                swapLogger.error("unable to determine correct keyset to increase det sec counter.")
            }
            try? modelContext.save()
        }
        
        fromMint.melt(for: meltQuote,
                      with: selectedProofs,
                      blankOutputSet: meltAttemptEvent.blankOutputs) { result in
            switch result {
            case .error(let error):
                meltAttemptEvent.proofs = nil
                selectedProofs.setState(.valid)
                swapLogger.error("melt operation failed with error: \(error)")
                updateHandler(.fail(error: error))
            case .failure:
                selectedProofs.setState(.pending)
                swapLogger.info("payment on mint \(fromMint.url.absoluteString) failed")
                updateHandler(.fail(error: nil))
            case .success(let (change, event)):
                swapLogger.debug("melt operation was successful.")
                selectedProofs.setState(.spent)
                meltingDidSucceed(toMint: toMint,
                                  mintAttemptEvent: mintAttemptEvent,
                                  meltAttemptEvent: meltAttemptEvent,
                                  meltEvent: event,
                                  change: change)
            }
        }
    }
    
    private func meltingDidSucceed(toMint: Mint, mintAttemptEvent: Event,
                                   meltAttemptEvent: Event,
                                   meltEvent: Event,
                                   change: [Proof]) {

        meltAttemptEvent.visible = false
        AppSchemaV1.insert([meltEvent] + change, into: modelContext)
        
        updateHandler(.minting)
        
        guard let mintQuote = mintAttemptEvent.bolt11MintQuote else {
            updateHandler(.fail(error: nil))
            swapLogger.error("toMint was nil, could not complete minting")
            return
        }
        
        issueCycle(toMint: toMint, mintQuote: mintQuote, mintAttemptEvent: mintAttemptEvent, currentCycle: 0)
    }
    
    // TODO: make reusable actor
    private func issueCycle(toMint: Mint,
                            mintQuote: CashuSwift.Bolt11.MintQuote,
                            mintAttemptEvent: Event,
                            currentCycle: Int, maxCycle: Int = 5, interval: Int = 2) {
        
        toMint.issue(for: mintQuote) { result in
            switch result {
            case .success((let proofs, let mintEvent)):
                mintingDidSucceed(mintAttemptEvent: mintAttemptEvent,
                                  mintEvent: mintEvent,
                                  proofs: proofs)
            case .failure(let error):
                swapLogger.warning("minting for mint swap failed due to error: \(error)")
                updateHandler(.fail(error: error))
            }
        }
    }
    
    private func mintingDidSucceed(mintAttemptEvent: Event,
                                   mintEvent: Event,
                                   proofs: [Proof]) {
        
        mintAttemptEvent.visible = false
        AppSchemaV1.insert(proofs + [mintEvent], into: modelContext)
        
        updateHandler(.success)
    }
}
