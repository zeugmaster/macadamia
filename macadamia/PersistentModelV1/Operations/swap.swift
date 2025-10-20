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
        
        if meltAttemptEvent.blankOutputs == nil {
            guard let outputs = try? CashuSwift.generateBlankOutputs(quote: meltQuote,
                                                                     proofs: selectedProofs,
                                                                     mint: fromMint,
                                                                     unit: meltQuote.quoteRequest?.unit ?? "sat",
                                                                     seed: seed) else {
                updateHandler(.fail(error: CashuError.cryptoError("Unable to create change outputs.")))
                return
            }
                    
            swapLogger.debug("no blank outputs were assigned, creating new")
            let blankOutputSet = BlankOutputSet(tuple: outputs)
            meltAttemptEvent.blankOutputs = blankOutputSet
            
            if !blankOutputSet.outputs.isEmpty {
                if let keysetID = outputs.outputs.first?.id {
                    fromMint.increaseDerivationCounterForKeysetWithID(keysetID,
                                                                      by: outputs.outputs.count)
                } else {
                    swapLogger.error("unable to determine correct keyset to increase det sec counter.")
                }
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


// MARK: Swap Service can not yet be used because using model contexts on non-main actors causes inconsistent state on the main context that can not be easily and cleanly resolved
@MainActor
final class SwapService {
    
    enum State {
        case preparing, melting, minting, success
        case fail(Error)
    }
    
    let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    private var activeWallet: Wallet? {
        try? modelContext.fetch(FetchDescriptor<Wallet>()).first(where: { $0.active == true })
    }
    
    func swap(from: PersistentIdentifier,
              to: PersistentIdentifier,
              amount: Int) -> AsyncStream<State> {
        
        AsyncStream { continuation in
            Task {
                continuation.yield(.preparing)
                do {
                    guard let fromMint:Mint = modelContext.model(for: from) as? Mint,
                          let toMint:Mint = modelContext.model(for: to) as? Mint else {
                        throw macadamiaError.databaseError("Unable to fetch data models by persistent identifier.")
                    }
                    
                    guard let activeWallet else {
                        throw macadamiaError.databaseError("Unable to find active wallet.")
                    }
                    
                    let mintQuoteRequest = CashuSwift.Bolt11.RequestMintQuote(unit: "sat",
                                                                              amount: amount)
                    guard let mintQuote = try await CashuSwift.getQuote(mint: CashuSwift.Mint(toMint),
                                                                        quoteRequest: mintQuoteRequest) as? CashuSwift.Bolt11.MintQuote else {
                        fatalError()
                    }
                    
                    let meltQuoteRequest = CashuSwift.Bolt11.RequestMeltQuote(unit: "sat",
                                                                              request: mintQuote.request,
                                                                              options: nil)
                    guard let meltQuote = try await CashuSwift.getQuote(mint: CashuSwift.Mint(fromMint),
                                                                        quoteRequest: meltQuoteRequest) as? CashuSwift.Bolt11.MeltQuote else {
                        fatalError()
                    }
                    
                    continuation.yield(.melting)
                    guard let selection = fromMint.select(amount: amount + meltQuote.feeReserve,
                                                          unit: .sat) else {
                        fatalError()
                    }
                    
                    swapLogger.debug("sum of selected proofs: \(selection.selected.sum), target amount + fee reserve: \(amount+meltQuote.feeReserve)")
                    
                    // create blank output set
                    let blankOutputs = try CashuSwift.generateBlankOutputs(quote: meltQuote,
                                                                           proofs: selection.selected,
                                                                           mint: fromMint,
                                                                           unit: "sat",
                                                                           seed: activeWallet.seed)
                    
                    if let keysetID = blankOutputs.outputs.first?.id, blankOutputs.outputs.count > 0 {
                        swapLogger.debug("increasing derivation counter for keyset \(keysetID) by \(blankOutputs.outputs.count)")
                        fromMint.increaseDerivationCounterForKeysetWithID(keysetID, by: blankOutputs.outputs.count)
                    } else {
                        swapLogger.error("\(blankOutputs.outputs.count) blank outputs where created but no keyset ID could be determined for counter increase.")
                    }
                    
                    let pendingMeltEvent = Event.pendingMeltEvent(unit: .sat,
                                                                  shortDescription: "Pending Payment",
                                                                  visible: true,
                                                                  wallet: activeWallet,
                                                                  quote: meltQuote,
                                                                  amount: amount,
                                                                  expiration: meltQuote.expiry.map({ Date(timeIntervalSince1970: TimeInterval($0)) }),
                                                                  mints: [fromMint],
                                                                  proofs: selection.selected,
                                                                  groupingID: nil)
                    
                    pendingMeltEvent.blankOutputs = BlankOutputSet(tuple: blankOutputs)
                    selection.selected.setState(.pending)
                    
                    modelContext.insert(pendingMeltEvent)
                    try modelContext.save()
                    
                    let meltResult = try await CashuSwift.melt(quote: meltQuote,
                                                               mint: CashuSwift.Mint(fromMint),
                                                               proofs: selection.selected.sendable(),
                                                               blankOutputs: blankOutputs)
                    selection.selected.setState(.spent)
                    
                    let meltEvent = Event.meltEvent(unit: .sat,
                                                    shortDescription: "Payment",
                                                    wallet: activeWallet,
                                                    amount: amount,
                                                    longDescription: "",
                                                    mints: [fromMint])
                    
                    modelContext.insert(meltEvent)
                    pendingMeltEvent.visible = false
                    try modelContext.save()
                    
                    if let change = meltResult.change {
                        try fromMint.addProofs(change, to: modelContext, increaseDerivationCounter: false)
                    }
                    
                    continuation.yield(.minting)
                    let mintResult = try await CashuSwift.issue(for: mintQuote,
                                                                mint: CashuSwift.Mint(toMint),
                                                                seed: activeWallet.seed)
                    
                    try toMint.addProofs(mintResult.proofs, to: modelContext)
                    
                    let mintEvent = Event.mintEvent(unit: .sat,
                                                    shortDescription: "Ecash created",
                                                    wallet: activeWallet,
                                                    quote: mintQuote,
                                                    mint: toMint,
                                                    amount: amount)
                    
                    modelContext.insert(mintEvent)
                    try modelContext.save()
                    
                    continuation.yield(.success)
                    continuation.finish()
                } catch {
                    continuation.yield(.fail(error))
                }
            }
        }
    }
}


// MARK: - Inline Swap Manager (with inlined operations from getQuote, issue, and melt)
@MainActor
struct InlineSwapManager {
    
    enum State {
        case ready, loading, melting, minting, success
        case fail(error: Error?)
    }
    
    let modelContext: ModelContext
    private let updateHandler: (InlineSwapManager.State) -> Void
    
    init(modelContext: ModelContext, updateHandler: @escaping (InlineSwapManager.State) -> Void) {
        self.modelContext = modelContext
        self.updateHandler = updateHandler
    }
    
    func swap(token: CashuSwift.Token, toMint: AppSchemaV1.Mint, seed: String) {
        updateHandler(.loading)
        
        let tokenSum = token.sum()
        
        guard let mintURLstring = token.proofsByMint.first?.key,
              let mintURL = URL(string: mintURLstring) else {
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
        
        // Inline getQuote for toMint (mint quote)
        inlineGetQuote(for: mintQuoteRequest, on: toMint) { result in
            switch result {
            case .success((let quote, let mintAttemptEvent)):
                guard let mintQuote = quote as? CashuSwift.Bolt11.MintQuote else {
                    swapLogger.error("returned quote was not a bolt11 mint quote. aborting swap.")
                    return
                }
                
                let meltQuoteRequest = CashuSwift.Bolt11.RequestMeltQuote(unit: "sat",
                                                                          request: mintQuote.request,
                                                                          options: nil)
                
                // Inline getQuote for fromMint (melt quote)
                inlineGetQuote(for: meltQuoteRequest, on: fromMint) { result in
                    switch result {
                    case .success((let quote, let meltAttemptEvent)):
                        guard let meltQuote = quote as? CashuSwift.Bolt11.MeltQuote else {
                            swapLogger.error("returned quote was not a bolt11 melt quote. aborting swap.")
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
    
    // MARK: - Inlined getQuote operation
    private func inlineGetQuote(for quoteRequest: CashuSwift.QuoteRequest,
                                on mint: AppSchemaV1.Mint,
                                completion: @escaping (Result<(quote: CashuSwift.Quote, event: Event), Error>) -> Void) {
        
        guard let wallet = mint.wallet else {
            completion(.failure(macadamiaError.databaseError("mint \(mint.url.absoluteString) does not have an associated wallet.")))
            return
        }
        
        let sendableMint = CashuSwift.Mint(mint)
        
        Task {
            do {
                let quote = try await CashuSwift.getQuote(mint: sendableMint, quoteRequest: quoteRequest)
                
                await MainActor.run {
                    let event: Event
                    switch quote {
                    case let quote as CashuSwift.Bolt11.MintQuote:
                        event = Event.pendingMintEvent(unit: Unit(quote.requestDetail?.unit) ?? .other,
                                                       shortDescription: "Mint Quote",
                                                       wallet: wallet,
                                                       quote: quote,
                                                       amount: quote.requestDetail?.amount ?? 0,
                                                       expiration: Date(timeIntervalSince1970: TimeInterval(quote.expiry ?? 0)),
                                                       mint: mint)
                        completion(.success((quote, event)))
                        
                    case let quote as CashuSwift.Bolt11.MeltQuote:
                        event = Event.pendingMeltEvent(unit: .sat,
                                                       shortDescription: "Pending Payment",
                                                       wallet: wallet,
                                                       quote: quote,
                                                       amount: (quote.amount),
                                                       expiration: Date(timeIntervalSince1970: TimeInterval(quote.expiry ?? 0)),
                                                       mints: [mint],
                                                       proofs: nil)
                        completion(.success((quote, event)))
                        
                    default:
                        completion(.failure(CashuError.typeMismatch("quote is not of any known type.")))
                    }
                }
            } catch {
                await MainActor.run {
                    completion(.failure(error))
                }
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
        
        if meltAttemptEvent.blankOutputs == nil {
            guard let outputs = try? CashuSwift.generateBlankOutputs(quote: meltQuote,
                                                                     proofs: selectedProofs,
                                                                     mint: fromMint,
                                                                     unit: meltQuote.quoteRequest?.unit ?? "sat",
                                                                     seed: seed) else {
                updateHandler(.fail(error: CashuError.cryptoError("Unable to create change outputs.")))
                return
            }
                    
            swapLogger.debug("no blank outputs were assigned, creating new")
            let blankOutputSet = BlankOutputSet(tuple: outputs)
            meltAttemptEvent.blankOutputs = blankOutputSet
            
            if !blankOutputSet.outputs.isEmpty {
                if let keysetID = outputs.outputs.first?.id {
                    fromMint.increaseDerivationCounterForKeysetWithID(keysetID,
                                                                      by: outputs.outputs.count)
                } else {
                    swapLogger.error("unable to determine correct keyset to increase det sec counter.")
                }
            }
            
            try? modelContext.save()
        }
        
        // Inline melt operation
        inlineMelt(for: meltQuote,
                   on: fromMint,
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
    
    // MARK: - Inlined melt operation
    private func inlineMelt(for quote: CashuSwift.Bolt11.MeltQuote,
                            on mint: AppSchemaV1.Mint,
                            with proofs: [Proof],
                            blankOutputSet: BlankOutputSet?,
                            completion: @escaping (PaymentResult) -> Void) {
        
        guard let wallet = mint.wallet else {
            completion(.error(macadamiaError.databaseError("mint \(mint.url.absoluteString) does not have an associated wallet.")))
            return
        }
        
        let sendableMint = CashuSwift.Mint(mint)
        
        let blankOutputs: (outputs: [CashuSwift.Output], blindingFactors: [String], secrets:[String])?
        
        if let blankOutputSet {
            blankOutputs = (blankOutputSet.outputs, blankOutputSet.blindingFactors, blankOutputSet.secrets)
        } else {
            blankOutputs = nil
        }
        
        Task {
            do {
                swapLogger.debug("Attempting to melt...")
                
                let meltResult = try await CashuSwift.melt(with: quote,
                                                           mint: sendableMint,
                                                           proofs: proofs.sendable(),
                                                           blankOutputs: blankOutputs)
                
                swapLogger.info("DLEQ check on melt change proofs was\(meltResult.dleqValid ? " " : " NOT ")successful.")
                
                if meltResult.paid {
                    let sendableProofs = meltResult.change
                    await MainActor.run {
                        var internalChangeProofs = [Proof]()
                        
                        if let sendableProofs,
                           !sendableProofs.isEmpty,
                           let changeKeyset = sendableMint.keysets.first(where: { $0.keysetID == sendableProofs.first?.keysetID }) {
                            
                            swapLogger.debug("Melt quote includes change, attempting saving to db.")
                            
                            let unit = Unit(changeKeyset.unit) ?? .other
                            let inputFee = changeKeyset.inputFeePPK
                            
                            internalChangeProofs = sendableProofs.map({ Proof($0,
                                                                              unit: unit,
                                                                              inputFeePPK: inputFee,
                                                                              state: .valid,
                                                                              mint: mint,
                                                                              wallet: wallet) })
                            
                            mint.proofs?.append(contentsOf: internalChangeProofs)
                            wallet.proofs.append(contentsOf: internalChangeProofs)
                        }
                        
                        let meltEvent = Event.meltEvent(unit: .sat,
                                                        shortDescription: "Payment",
                                                        wallet: wallet,
                                                        amount: (quote.amount),
                                                        longDescription: "",
                                                        mints: [mint])
                        
                        completion(.success((internalChangeProofs, meltEvent)))
                    }
                } else {
                    DispatchQueue.main.async {
                        swapLogger.info("""
                                    Melt function returned a quote with state NOT PAID, \
                                    probably because the lightning payment failed
                                    """)
                        
                        completion(.failure);
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.error(error))
                }
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
    
    private func issueCycle(toMint: Mint,
                            mintQuote: CashuSwift.Bolt11.MintQuote,
                            mintAttemptEvent: Event,
                            currentCycle: Int, maxCycle: Int = 5, interval: Int = 2) {
        
        // Inline issue operation
        inlineIssue(for: mintQuote, on: toMint) { result in
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
    
    // MARK: - Inlined issue operation
    private func inlineIssue(for quote: CashuSwift.Bolt11.MintQuote,
                             on mint: AppSchemaV1.Mint,
                             completion: @escaping (Result<(proofs: [Proof], event: Event), Error>) -> Void) {
        
        guard let wallet = mint.wallet else {
            completion(.failure(macadamiaError.databaseError("mint \(mint.url.absoluteString) does not have an associated wallet.")))
            return
        }
        
        let sendableMint = CashuSwift.Mint(mint)
        let seed = wallet.seed
        
        Task {
            do {
                let (sendableProofs, dleqPassed) = try await CashuSwift.issue(for: quote, with: sendableMint, seed: seed)
                swapLogger.info("DLEQ check on newly minted proofs was\(dleqPassed ? " " : " NOT ")successful.")
                
                await MainActor.run {
                    let proofs = sendableProofs.map { p in
                        let unit = Unit(quote.requestDetail?.unit ?? "other") ?? .other
                        return Proof(p,
                                     unit: unit,
                                     inputFeePPK: 0,
                                     state: .valid,
                                     mint: mint,
                                     wallet: wallet)
                    }
                    
                    mint.increaseDerivationCounterForKeysetWithID(proofs.first!.keysetID,
                                                                  by: proofs.count)
                    let keysetFee = mint.keysets.first(where: { $0.keysetID == proofs.first?.keysetID })?.inputFeePPK ?? 0
                    proofs.forEach({ $0.inputFeePPK = keysetFee })
                    
                    mint.proofs?.append(contentsOf: proofs)
                    wallet.proofs.append(contentsOf: proofs)
                    
                    let event = Event.mintEvent(unit: Unit(quote.requestDetail?.unit) ?? .other,
                                                shortDescription: "Ecash created",
                                                wallet: wallet,
                                                quote: quote,
                                                mint: mint,
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
    
    private func mintingDidSucceed(mintAttemptEvent: Event,
                                   mintEvent: Event,
                                   proofs: [Proof]) {
        
        mintAttemptEvent.visible = false
        AppSchemaV1.insert(proofs + [mintEvent], into: modelContext)
        
        updateHandler(.success)
    }
}
