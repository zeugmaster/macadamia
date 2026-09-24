import Foundation
import SwiftData
import CashuSwift
import OSLog

fileprivate let swapLogger = Logger(subsystem: "macadamia", category: "SwapOperation")

@MainActor
final class SwapManager: ObservableObject {

    enum State: Equatable {
        case waiting, preparing, melting, minting, success
        /// The transfer could not finish yet but remains resumable from the
        /// transaction list (e.g. issuance retries exhausted, payment in flight).
        case pending(String)
        case fail(Error)

        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.waiting, .waiting): return true
            case (.preparing, .preparing): return true
            case (.melting, .melting): return true
            case (.minting, .minting): return true
            case (.success, .success): return true
            case (.pending, .pending): return true
            case (.fail, .fail): return true
            default: return false
            }
        }
    }

    struct TransferState: Equatable {
        let from: Mint
        let to: Mint
        var state: State

        static func == (lhs: TransferState, rhs: TransferState) -> Bool {
            lhs.from.id == rhs.from.id && lhs.to.id == rhs.to.id && lhs.state == rhs.state
        }
    }

    @Published var multiTransactionState: [TransferState]?
    @Published var singleTransactionState: State?

    private var swapList: [(from: Mint, to: Mint, amount: Int, seed: String, modelContext: ModelContext)]?
    private var currentSwapIndex: Int = 0

    private func setCurrentSwapState(_ state: State) {
        if swapList != nil {
            guard var multiTransactionState, multiTransactionState.indices.contains(currentSwapIndex) else {
                swapLogger.error("Failed to set swap state: multiTransactionState is nil or index \(self.currentSwapIndex) out of bounds")
                return
            }

            multiTransactionState[currentSwapIndex].state = state
            self.multiTransactionState = multiTransactionState
        } else {
            singleTransactionState = state
        }
    }

    // batch tx function
    func swap(transfers: [(from: Mint, to: Mint, amount: Int, seed: String)], modelContext: ModelContext) {

        if swapList == nil {
            multiTransactionState = transfers.map { transfer in
                TransferState(from: transfer.from, to: transfer.to, state: .waiting)
            }
            singleTransactionState = nil
            currentSwapIndex = 0
            swapList = transfers.map({ (from: $0.from, to: $0.to, amount: $0.amount, seed: $0.seed, modelContext: modelContext) })
        }

        guard let swapList else {
            swapLogger.error("swap() called but swapList is nil")
            return
        }

        if currentSwapIndex >= swapList.count {
            // must be done with all tx, reset and return

            self.swapList = nil
            self.currentSwapIndex = 0
            print("swap queue completed.")
            return
        }

        swap(fromMint: swapList[currentSwapIndex].from,
             toMint: swapList[currentSwapIndex].to,
             amount: swapList[currentSwapIndex].amount,
             seed: swapList[currentSwapIndex].seed,
             modelContext: swapList[currentSwapIndex].modelContext)
    }

    func swap(token: CashuSwift.Token, toMint: AppSchemaV1.Mint, seed: String, modelContext: ModelContext) {
        setCurrentSwapState(.preparing)

        let tokenSum = token.sum()

        guard let mintURLstring = token.proofsByMint.first?.key,
              let mintURL = URL(string: mintURLstring) else {
            swapLogger.error("Failed to swap token: missing mint URL in token")
            setCurrentSwapState(.fail(CashuError.unknownError("Missing mint URL in token")))
            return
        }

        Task {
            do {
                swapLogger.debug("loading mint for untrusted swap \(mintURLstring)...")
                let fromMint = try await CashuSwift.loadMint(url: mintURL)

                let dummyMintQuoteRequest = CashuSwift.Bolt11.MintQuoteRequest(unit: token.unit, amount: tokenSum)
                let dummyMintQuote = try await CashuSwift.Bolt11.requestMintQuote(dummyMintQuoteRequest,
                                                                                  from: CashuSwift.Mint(toMint))

                let dummyMeltQuoteRequest = CashuSwift.Bolt11.MeltQuoteRequest(unit: token.unit,
                                                                               request: dummyMintQuote.request,
                                                                               options:nil)

                let dummyMeltQuote = try await CashuSwift.Bolt11.requestMeltQuote(dummyMeltQuoteRequest,
                                                                                  from: fromMint)

                guard let proofs = token.proofsByMint.first?.value else {
                    swapLogger.error("No proofs found in token for swap")
                    setCurrentSwapState(.fail(CashuError.unknownError("No proofs found in token")))
                    return
                }

                let inputFee = try CashuSwift.calculateFee(for: proofs, of: fromMint)
                let swapAmount = tokenSum - dummyMeltQuote.feeReserve - inputFee

                try await MainActor.run  {
                    swapLogger.debug("attempting swap from token with total amount \(tokenSum) and swapAmount \(swapAmount)")
                    let fromMint = try AppSchemaV1.addMint(fromMint, to: modelContext, hidden: true, proofs: proofs)
                    swap(fromMint: fromMint, toMint: toMint, amount: swapAmount, seed: seed, modelContext: modelContext)
                }
            } catch {
                swapLogger.error("Token swap failed with error: \(error.localizedDescription)")
                setCurrentSwapState(.fail(error))
            }
        }
    }

    func swap(fromMint: AppSchemaV1.Mint, toMint: AppSchemaV1.Mint, amount: Int, seed: String, modelContext: ModelContext) {
        setCurrentSwapState(.preparing)

        guard fromMint.supportedUnits.contains(.sat), toMint.supportedUnits.contains(.sat) else {
            setCurrentSwapState(.fail(TransferError.missingData("Transfers can only be prepared between mints that both support sat ecash.")))
            return
        }

        Task {
            do {
                let mintQuoteRequest = CashuSwift.Bolt11.MintQuoteRequest(unit: Unit.sat.currencyCode,
                                                                          amount: amount)
                let mintQuote = try await CashuSwift.Bolt11.requestMintQuote(mintQuoteRequest,
                                                                             from: CashuSwift.Mint(toMint))
                let meltQuoteRequest = CashuSwift.Bolt11.MeltQuoteRequest(unit: Unit.sat.currencyCode,
                                                                          request: mintQuote.request,
                                                                          options: nil)
                let meltQuote = try await CashuSwift.Bolt11.requestMeltQuote(meltQuoteRequest,
                                                                             from: CashuSwift.Mint(fromMint))

                await MainActor.run {
                    guard let selection = fromMint.select(amount: amount + meltQuote.feeReserve,
                                                          unit: .sat) else {
                        swapLogger.error("Insufficient inputs for swap: need \(amount + meltQuote.feeReserve) sat from \(fromMint.url)")
                        setCurrentSwapState(.fail(CashuError.insufficientInputs("")))
                        return
                    }

                    setupDidSucceed(fromMint: fromMint,
                                    toMint: toMint,
                                    seed: seed,
                                    mintQuote: mintQuote,
                                    meltQuote: meltQuote,
                                    selectedProofs: selection.selected,
                                    modelContext: modelContext)
                }
            } catch {
                swapLogger.error("Swap preparation failed: \(error.localizedDescription)")
                await MainActor.run {
                    setCurrentSwapState(.fail(error))
                }
            }
        }
    }

    func resumeTransfer(with pendingTransferEvent: Event, modelContext: ModelContext) {
        guard let mintQuote = pendingTransferEvent.mintQuote,
              let (from, to) = pendingTransferEvent.transferMints else {
            swapLogger.error("Cannot resume transfer: missing mint quote or mints")
            setCurrentSwapState(.fail(TransferError.missingData("Unable to find the mint quote or the mints associated with this transfer event.")))
            return
        }

        // these are only required for specific resume paths, not up front
        let meltQuote = pendingTransferEvent.bolt11MeltQuote
        let blankOutputSet = pendingTransferEvent.blankOutputs
        let proofs = pendingTransferEvent.proofs
        let expired = (pendingTransferEvent.mintQuoteExpiry ?? .distantFuture) < Date()

        let sendableFrom = CashuSwift.Mint(from)
        let sendableTo = CashuSwift.Mint(to)

        setCurrentSwapState(.preparing)

        Task {
            // destination first: did the payment arrive, was the ecash already issued?
            let destination: TransferFlow.QuoteCheck
            if let state = (try? await CashuSwift.Bolt11.mintQuoteState(mintQuote.quote, from: sendableTo))?.state {
                destination = .state(state)
            } else {
                destination = .unavailable
            }

            // consult the source melt quote only when the destination has not seen the payment
            var source: TransferFlow.QuoteCheck? = nil
            var sourceMeltResult: CashuSwift.MeltResult<CashuSwift.Bolt11.MeltQuote>? = nil
            if destination == .state(.unpaid), let meltQuote {
                let outputs = (blankOutputSet?.outputs.isEmpty == false) ? blankOutputSet?.tuple() : nil
                sourceMeltResult = try? await CashuSwift.Bolt11.meltState(meltQuote.quote,
                                                                          from: sendableFrom,
                                                                          blankOutputs: outputs)
                source = sourceMeltResult.flatMap { result in
                    result.quote.state.map { TransferFlow.QuoteCheck.state($0) }
                } ?? .unavailable
            }

            let context = TransferFlow.ResumeContext(destination: destination,
                                                     source: source,
                                                     mintQuoteExpired: expired,
                                                     hasProofs: !(proofs ?? []).isEmpty,
                                                     hasBlankOutputs: blankOutputSet != nil)
            let action = TransferFlow.resumeAction(for: context)
            swapLogger.info("resuming transfer: destination \(String(describing: destination)), source \(String(describing: source)) → \(String(describing: action))")

            switch action {
            case .issue, .pollDestinationThenIssue:
                await TransferFlow.recoverSourceSide(meltQuote: meltQuote,
                                                     from: from,
                                                     sendableFrom: sendableFrom,
                                                     preFetched: sourceMeltResult,
                                                     blankOutputSet: blankOutputSet,
                                                     proofs: proofs,
                                                     modelContext: modelContext)
                transferIssue(mintQuote: mintQuote,
                              meltQuote: sourceMeltResult?.quote ?? meltQuote,
                              from: from,
                              to: to,
                              pendingTransferEvent: pendingTransferEvent,
                              modelContext: modelContext)

            case .informAlreadyIssued:
                setCurrentSwapState(.fail(TransferError.alreadyIssued))

            case .waitSourcePending:
                setCurrentSwapState(.pending(String(localized: "The Lightning payment is still in flight. Check again in a moment.")))

            case .remelt:
                guard let meltQuote, let proofs, !proofs.isEmpty else {
                    setCurrentSwapState(.fail(TransferError.missingData("The original ecash for this transfer is no longer attached to the event.")))
                    return
                }
                if blankOutputSet == nil {
                    swapLogger.warning("re-melting without blank outputs — overpaid fees will not be returned as change")
                }
                proofs.setState(.pending)
                transferMelt(meltQuote: meltQuote,
                             mintQuote: mintQuote,
                             from: from,
                             to: to,
                             with: proofs,
                             pendingTransferEvent: pendingTransferEvent,
                             modelContext: modelContext)

            case .missingDataForRemelt:
                setCurrentSwapState(.fail(TransferError.missingData("The payment was never made and the original ecash is no longer attached to this transfer event.")))

            case .informExpiredUnpaid:
                // expired before the payment happened — reverting is the right call
                setCurrentSwapState(.fail(TransferError.meltFailure(TransferError.mintQuoteExpired)))

            case .expiredStranded:
                setCurrentSwapState(.pending(String(localized: """
                                    The payment went through but the destination mint's quote expired. \
                                    Contact the mint operator to recover the funds.
                                    """)))

            case .keepPendingUnknown:
                setCurrentSwapState(.pending(String(localized: "Could not determine the transfer's state. Nothing was changed — try again later.")))
            }
        }
    }

    private func setupDidSucceed(fromMint: Mint,
                                 toMint: Mint,
                                 seed: String,
                                 mintQuote: CashuSwift.Bolt11.MintQuote,
                                 meltQuote: CashuSwift.Bolt11.MeltQuote,
                                 selectedProofs: [Proof],
                                 modelContext: ModelContext) {
        swapLogger.info("melt input proof sum \(selectedProofs.sum), quote amount \(meltQuote.amount)")

        guard let changeOutputs = try? CashuSwift.generateBlankOutputs(quote: meltQuote,
                                                                       proofs: selectedProofs,
                                                                       mint: fromMint,
                                                                       unit: meltQuote.unit,
                                                                       seed: seed) else {
            swapLogger.error("Failed to create change outputs for swap from \(fromMint.url) to \(toMint.url)")
            setCurrentSwapState(.fail(CashuError.cryptoError("Unable to create change outputs.")))
            return
        }

        swapLogger.info("in .setupDidSucceed: created \(changeOutputs.outputs.count) change outputs")

        let changeOutputSet = BlankOutputSet(tuple: changeOutputs)

        if let keysetID = changeOutputs.outputs.first?.id {
            fromMint.increaseDerivationCounterForKeysetWithID(keysetID,
                                                              by: changeOutputs.outputs.count)
        }

        guard let wallet = fromMint.wallet else {
            swapLogger.error("Mint \(fromMint.url) does not have an associated wallet")
            setCurrentSwapState(.fail(macadamiaError.databaseError("mint \(fromMint.url.absoluteString) does not have an associated wallet.")))
            return
        }

        let pendingTransferEvent = Event.pendingTransferEvent(wallet: wallet,
                                                              amount: meltQuote.amount,
                                                              from: fromMint,
                                                              to: toMint,
                                                              proofs: selectedProofs,
                                                              meltQuote: meltQuote,
                                                              mintQuote: mintQuote,
                                                              groupingID: nil)

        pendingTransferEvent.blankOutputs = changeOutputSet

        modelContext.insert(pendingTransferEvent)

        selectedProofs.setState(.pending)

        try? modelContext.save()

        transferMelt(meltQuote: meltQuote,
                     mintQuote: mintQuote,
                     from: fromMint,
                     to: toMint,
                     with: selectedProofs,
                     pendingTransferEvent: pendingTransferEvent,
                     modelContext: modelContext)
    }

    // MARK: - Inlined melt operation
    private func transferMelt(meltQuote: CashuSwift.Bolt11.MeltQuote,
                              mintQuote: CashuSwift.Bolt11.MintQuote,
                              from: Mint,
                              to: Mint,
                              with proofs: [Proof],
                              pendingTransferEvent: Event,
                              modelContext: ModelContext) {

        setCurrentSwapState(.melting)

        let sendableFrom = CashuSwift.Mint(from)
        let blankOutputSet = pendingTransferEvent.blankOutputs

        Task {
            do {
                swapLogger.debug("Attempting to melt...")

                swapLogger.debug("transfer event has change outputs assigned: \(blankOutputSet?.outputs.isEmpty ?? true ? "empty" : "assigned and populated")")

                let meltResult = try await CashuSwift.Bolt11.melt(quote: meltQuote,
                                                                  from: sendableFrom,
                                                                  proofs: proofs.sendable(),
                                                                  blankOutputs: blankOutputSet?.tuple())

                swapLogger.info("DLEQ check on melt change proofs: \(String(describing: meltResult.dleqResult))")

                if meltResult.quote.state == .paid {

                    meltDidSucceed(mintQuote: mintQuote,
                                   newMeltQuote: meltResult.quote,
                                   change: meltResult.change ?? [],
                                   proofs: proofs,
                                   from: from,
                                   to: to,
                                   pendingTransferEvent: pendingTransferEvent,
                                   modelContext: modelContext)
                } else {

                    swapLogger.info("""
                                    Melt function returned a quote with state NOT PAID, \
                                    probably because the lightning payment failed
                                    """)
                    meltFailed(with: CashuError.unknownError("Transfer did not complete because the melt quote was returned with state UNPAID."),
                               reportedState: meltResult.quote.state,
                               proofs: proofs,
                               pendingTransferEvent: pendingTransferEvent,
                               modelContext: modelContext)
                }
            } catch {
                swapLogger.error("Melt operation failed: \(error.localizedDescription)")

                // The thrown error alone cannot tell us whether the payment happened
                // (e.g. a timeout while the payment settles). Re-check the quote once
                // before deciding what to do with the inputs.
                let outputs = (blankOutputSet?.outputs.isEmpty == false) ? blankOutputSet?.tuple() : nil
                let recheck = try? await CashuSwift.Bolt11.meltState(meltQuote.quote,
                                                                     from: sendableFrom,
                                                                     blankOutputs: outputs)

                if let recheck, recheck.quote.state == .paid {
                    swapLogger.info("melt threw but the quote is PAID — continuing with issuance")
                    meltDidSucceed(mintQuote: mintQuote,
                                   newMeltQuote: recheck.quote,
                                   change: recheck.change ?? [],
                                   proofs: proofs,
                                   from: from,
                                   to: to,
                                   pendingTransferEvent: pendingTransferEvent,
                                   modelContext: modelContext)
                } else {
                    meltFailed(with: error,
                               reportedState: recheck?.quote.state,
                               proofs: proofs,
                               pendingTransferEvent: pendingTransferEvent,
                               modelContext: modelContext)
                }
            }
        }
    }

    private func meltDidSucceed(mintQuote: CashuSwift.Bolt11.MintQuote,
                                newMeltQuote: CashuSwift.Bolt11.MeltQuote,
                                change: [CashuSwift.Proof],
                                proofs: [Proof],
                                from: Mint,
                                to: Mint,
                                pendingTransferEvent: Event,
                                modelContext: ModelContext) {

        proofs.setState(.spent)

        do {
            try from.addProofs(change,
                               to: modelContext,
                               increaseDerivationCounter: false)
            // Save immediately to persist change proofs to database
            try modelContext.save()
            swapLogger.debug("Successfully saved \(change.count) change proofs for mint \(from.url)")
        } catch {
            swapLogger.error("Failed to add/save \(change.count) change proofs to mint \(from.url): \(error.localizedDescription)")
            // This is a critical error - change proofs are lost, but we continue with minting
            // The user effectively paid the full amount without getting change back
        }

        transferIssue(mintQuote: mintQuote,
                      meltQuote: newMeltQuote,
                      from: from,
                      to: to,
                      pendingTransferEvent: pendingTransferEvent,
                      modelContext: modelContext)

    }

    private func meltFailed(with error: Error,
                            reportedState: CashuSwift.QuoteState?,
                            proofs: [Proof],
                            pendingTransferEvent: Event,
                            modelContext: ModelContext) {
        switch TransferFlow.classifyMeltFailure(error: error, reportedState: reportedState) {
        case .definitelyUnpaid:
            swapLogger.error("Melt definitively unpaid: \(error.localizedDescription). Reverting proofs to valid state.")
            proofs.setState(.valid)
            // the event keeps its proofs and blank outputs so the melt can be retried
            try? modelContext.save()
            setCurrentSwapState(.fail(TransferError.meltFailure(error)))

        case .unknownOutcome:
            swapLogger.warning("Melt outcome unknown: \(error.localizedDescription). Keeping proofs pending and event data intact.")
            try? modelContext.save()
            setCurrentSwapState(.pending(String(localized: """
                                The payment outcome could not be determined. \
                                Check this transfer again later from the transaction list.
                                """)))
        }

        nextSwapIfPresent()
    }

    private func transferIssue(mintQuote: CashuSwift.Bolt11.MintQuote,
                               meltQuote: CashuSwift.Bolt11.MeltQuote?,
                               from: Mint,
                               to: Mint,
                               pendingTransferEvent: Event,
                               modelContext: ModelContext) {

        guard let wallet = from.wallet else {
            swapLogger.error("Mint \(from.url) does not have an associated wallet during issue")
            setCurrentSwapState(.fail(macadamiaError.databaseError("mint \(from.url.absoluteString) does not have an associated wallet.")))
            nextSwapIfPresent()
            return
        }

        setCurrentSwapState(.minting)

        let sendableMint = CashuSwift.Mint(to)
        let seed = wallet.seed
        let quoteID = mintQuote.quote

        Task {
            guard !TransferFlow.activeQuoteIDs.contains(quoteID) else {
                swapLogger.warning("issuance already in progress for quote \(quoteID), skipping duplicate run")
                return
            }
            TransferFlow.activeQuoteIDs.insert(quoteID)
            defer { TransferFlow.activeQuoteIDs.remove(quoteID) }

            let outcome = await TransferFlow.pollAndIssue(mintQuote: mintQuote,
                                                          on: sendableMint,
                                                          seed: seed)

            switch outcome {
            case .success(let result):
                do {
                    try TransferFlow.finalizeIssuedTransfer(issueResult: result,
                                                            mintQuote: mintQuote,
                                                            meltQuote: meltQuote,
                                                            from: from,
                                                            to: to,
                                                            pendingTransferEvent: pendingTransferEvent,
                                                            modelContext: modelContext)
                    setCurrentSwapState(.success)
                } catch {
                    swapLogger.error("Failed to persist issued transfer: \(error.localizedDescription)")
                    setCurrentSwapState(.fail(error))
                }

            case .parkedPending(let message, let lastError):
                swapLogger.warning("transfer parked as pending. last error: \(String(describing: lastError))")
                try? modelContext.save()
                setCurrentSwapState(.pending(message))

            case .alreadyIssued:
                setCurrentSwapState(.fail(TransferError.alreadyIssued))

            case .staleOutputs(let error):
                swapLogger.error("stale outputs during issuance: \(error.localizedDescription)")
                setCurrentSwapState(.fail(error))

            case .expired:
                setCurrentSwapState(.fail(TransferError.mintQuoteExpired))

            case .failed(let error):
                swapLogger.error("Mint/issue operation failed: \(error.localizedDescription)")
                setCurrentSwapState(.fail(error))
            }

            nextSwapIfPresent()
        }
    }

    @MainActor
    private func nextSwapIfPresent() {
        guard let swapList else { return }

        currentSwapIndex += 1

        // Check if there's another swap to process
        guard currentSwapIndex < swapList.count else {
            // All swaps complete, reset
            self.swapList = nil
            self.currentSwapIndex = 0
            return
        }

        // Process next swap
        swap(fromMint: swapList[currentSwapIndex].from,
             toMint: swapList[currentSwapIndex].to,
             amount: swapList[currentSwapIndex].amount,
             seed: swapList[currentSwapIndex].seed,
             modelContext: swapList[currentSwapIndex].modelContext)
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

                    let mintQuoteRequest = CashuSwift.Bolt11.MintQuoteRequest(unit: Unit.sat.currencyCode,
                                                                              amount: amount)
                    let mintQuote = try await CashuSwift.Bolt11.requestMintQuote(mintQuoteRequest,
                                                                                 from: CashuSwift.Mint(toMint))

                    let meltQuoteRequest = CashuSwift.Bolt11.MeltQuoteRequest(unit: Unit.sat.currencyCode,
                                                                              request: mintQuote.request,
                                                                              options: nil)
                    let meltQuote = try await CashuSwift.Bolt11.requestMeltQuote(meltQuoteRequest,
                                                                                 from: CashuSwift.Mint(fromMint))

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
                                                                           unit: Unit.sat.currencyCode,
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

                    let meltResult = try await CashuSwift.Bolt11.melt(quote: meltQuote,
                                                                      from: CashuSwift.Mint(fromMint),
                                                                      proofs: selection.selected.sendable(),
                                                                      blankOutputs: blankOutputs)
                    selection.selected.setState(.spent)

                    let meltEvent = Event.meltEvent(unit: .sat,
                                                    shortDescription: "Payment",
                                                    wallet: activeWallet,
                                                    amount: amount,
                                                    longDescription: "",
                                                    mints: [fromMint],
                                                    meltQuote: meltQuote)

                    modelContext.insert(meltEvent)
                    pendingMeltEvent.visible = false
                    try modelContext.save()

                    if let change = meltResult.change {
                        try fromMint.addProofs(change, to: modelContext, increaseDerivationCounter: false)
                    }

                    continuation.yield(.minting)
                    let mintResult = try await CashuSwift.Bolt11.mint(quote: mintQuote,
                                                                      from: CashuSwift.Mint(toMint),
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
final class InlineSwapManager: ObservableObject {

    enum State {
        case ready, loading, melting, minting, success
        /// The transfer could not finish yet but remains resumable from the
        /// transaction list (e.g. issuance retries exhausted, payment in flight).
        case pending(message: String)
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

                let dummyMintQuoteRequest = CashuSwift.Bolt11.MintQuoteRequest(unit: token.unit, amount: tokenSum)
                let dummyMintQuote = try await CashuSwift.Bolt11.requestMintQuote(dummyMintQuoteRequest,
                                                                                  from: CashuSwift.Mint(toMint))

                let dummyMeltQuoteRequest = CashuSwift.Bolt11.MeltQuoteRequest(unit: token.unit,
                                                                               request: dummyMintQuote.request,
                                                                               options:nil)

                let dummyMeltQuote = try await CashuSwift.Bolt11.requestMeltQuote(dummyMeltQuoteRequest,
                                                                                  from: fromMint)

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

        guard fromMint.supportedUnits.contains(.sat), toMint.supportedUnits.contains(.sat) else {
            updateHandler(.fail(error: TransferError.missingData("Transfers can only be prepared between mints that both support sat ecash.")))
            return
        }

        Task {
            do {
                let mintQuoteRequest = CashuSwift.Bolt11.MintQuoteRequest(unit: Unit.sat.currencyCode,
                                                                          amount: amount)
                let mintQuote = try await CashuSwift.Bolt11.requestMintQuote(mintQuoteRequest,
                                                                             from: CashuSwift.Mint(toMint))
                let meltQuoteRequest = CashuSwift.Bolt11.MeltQuoteRequest(unit: Unit.sat.currencyCode,
                                                                          request: mintQuote.request,
                                                                          options: nil)
                let meltQuote = try await CashuSwift.Bolt11.requestMeltQuote(meltQuoteRequest,
                                                                             from: CashuSwift.Mint(fromMint))

                await MainActor.run {
                    guard let selection = fromMint.select(amount: amount + meltQuote.feeReserve,
                                                          unit: .sat) else {
                        updateHandler(.fail(error: CashuError.insufficientInputs("")))
                        return
                    }

                    setupDidSucceed(fromMint: fromMint,
                                    toMint: toMint,
                                    seed: seed,
                                    mintQuote: mintQuote,
                                    meltQuote: meltQuote,
                                    selectedProofs: selection.selected)
                }
            } catch {
                await MainActor.run {
                    updateHandler(.fail(error: error))
                }
            }
        }
    }

    func resumeTransfer(with pendingTransferEvent: Event) {
        guard let mintQuote = pendingTransferEvent.mintQuote,
              let (from, to) = pendingTransferEvent.transferMints else {
            updateHandler(.fail(error: TransferError.missingData("Unable to find the mint quote or the mints associated with this transfer event.")))
            return
        }

        // these are only required for specific resume paths, not up front
        let meltQuote = pendingTransferEvent.bolt11MeltQuote
        let blankOutputSet = pendingTransferEvent.blankOutputs
        let proofs = pendingTransferEvent.proofs
        let expired = (pendingTransferEvent.mintQuoteExpiry ?? .distantFuture) < Date()

        let sendableFrom = CashuSwift.Mint(from)
        let sendableTo = CashuSwift.Mint(to)

        updateHandler(.loading)

        Task {
            // destination first: did the payment arrive, was the ecash already issued?
            let destination: TransferFlow.QuoteCheck
            if let state = (try? await CashuSwift.Bolt11.mintQuoteState(mintQuote.quote, from: sendableTo))?.state {
                destination = .state(state)
            } else {
                destination = .unavailable
            }

            // consult the source melt quote only when the destination has not seen the payment
            var source: TransferFlow.QuoteCheck? = nil
            var sourceMeltResult: CashuSwift.MeltResult<CashuSwift.Bolt11.MeltQuote>? = nil
            if destination == .state(.unpaid), let meltQuote {
                let outputs = (blankOutputSet?.outputs.isEmpty == false) ? blankOutputSet?.tuple() : nil
                sourceMeltResult = try? await CashuSwift.Bolt11.meltState(meltQuote.quote,
                                                                          from: sendableFrom,
                                                                          blankOutputs: outputs)
                source = sourceMeltResult.flatMap { result in
                    result.quote.state.map { TransferFlow.QuoteCheck.state($0) }
                } ?? .unavailable
            }

            let context = TransferFlow.ResumeContext(destination: destination,
                                                     source: source,
                                                     mintQuoteExpired: expired,
                                                     hasProofs: !(proofs ?? []).isEmpty,
                                                     hasBlankOutputs: blankOutputSet != nil)
            let action = TransferFlow.resumeAction(for: context)
            swapLogger.info("resuming transfer: destination \(String(describing: destination)), source \(String(describing: source)) → \(String(describing: action))")

            switch action {
            case .issue, .pollDestinationThenIssue:
                await TransferFlow.recoverSourceSide(meltQuote: meltQuote,
                                                     from: from,
                                                     sendableFrom: sendableFrom,
                                                     preFetched: sourceMeltResult,
                                                     blankOutputSet: blankOutputSet,
                                                     proofs: proofs,
                                                     modelContext: modelContext)
                transferIssue(mintQuote: mintQuote,
                              meltQuote: sourceMeltResult?.quote ?? meltQuote,
                              from: from,
                              to: to,
                              pendingTransferEvent: pendingTransferEvent)

            case .informAlreadyIssued:
                updateHandler(.fail(error: TransferError.alreadyIssued))

            case .waitSourcePending:
                updateHandler(.pending(message: String(localized: "The Lightning payment is still in flight. Check again in a moment.")))

            case .remelt:
                guard let meltQuote, let proofs, !proofs.isEmpty else {
                    updateHandler(.fail(error: TransferError.missingData("The original ecash for this transfer is no longer attached to the event.")))
                    return
                }
                if blankOutputSet == nil {
                    swapLogger.warning("re-melting without blank outputs — overpaid fees will not be returned as change")
                }
                proofs.setState(.pending)
                transferMelt(meltQuote: meltQuote,
                             mintQuote: mintQuote,
                             from: from,
                             to: to,
                             with: proofs,
                             pendingTransferEvent: pendingTransferEvent)

            case .missingDataForRemelt:
                updateHandler(.fail(error: TransferError.missingData("The payment was never made and the original ecash is no longer attached to this transfer event.")))

            case .informExpiredUnpaid:
                // expired before the payment happened — reverting is the right call
                updateHandler(.fail(error: TransferError.meltFailure(TransferError.mintQuoteExpired)))

            case .expiredStranded:
                updateHandler(.pending(message: String(localized: """
                              The payment went through but the destination mint's quote expired. \
                              Contact the mint operator to recover the funds.
                              """)))

            case .keepPendingUnknown:
                updateHandler(.pending(message: String(localized: "Could not determine the transfer's state. Nothing was changed — try again later.")))
            }
        }
    }

    private func setupDidSucceed(fromMint: Mint,
                                 toMint: Mint,
                                 seed: String,
                                 mintQuote: CashuSwift.Bolt11.MintQuote,
                                 meltQuote: CashuSwift.Bolt11.MeltQuote,
                                 selectedProofs: [Proof]) {
        swapLogger.info("melt input proof sum \(selectedProofs.sum), quote amount \(meltQuote.amount)")

        guard let changeOutputs = try? CashuSwift.generateBlankOutputs(quote: meltQuote,
                                                                       proofs: selectedProofs,
                                                                       mint: fromMint,
                                                                       unit: meltQuote.unit,
                                                                       seed: seed) else {
            updateHandler(.fail(error: CashuError.cryptoError("Unable to create change outputs.")))
            return
        }

        swapLogger.info("in .setupDidSucceed: created \(changeOutputs.outputs.count) change outputs")

        let changeOutputSet = BlankOutputSet(tuple: changeOutputs)

        if let keysetID = changeOutputs.outputs.first?.id {
            fromMint.increaseDerivationCounterForKeysetWithID(keysetID,
                                                              by: changeOutputs.outputs.count)
        }

        guard let wallet = fromMint.wallet else {
            updateHandler(.fail(error: macadamiaError.databaseError("mint \(fromMint.url.absoluteString) does not have an associated wallet.")))
            return
        }

        let pendingTransferEvent = Event.pendingTransferEvent(wallet: wallet,
                                                              amount: meltQuote.amount,
                                                              from: fromMint,
                                                              to: toMint,
                                                              proofs: selectedProofs,
                                                              meltQuote: meltQuote,
                                                              mintQuote: mintQuote,
                                                              groupingID: nil)

        pendingTransferEvent.blankOutputs = changeOutputSet

        modelContext.insert(pendingTransferEvent)

        selectedProofs.setState(.pending)

        try? modelContext.save()

        transferMelt(meltQuote: meltQuote,
                     mintQuote: mintQuote,
                     from: fromMint,
                     to: toMint,
                     with: selectedProofs,
                     pendingTransferEvent: pendingTransferEvent)
    }

    // MARK: - Inlined melt operation
    private func transferMelt(meltQuote: CashuSwift.Bolt11.MeltQuote,
                              mintQuote: CashuSwift.Bolt11.MintQuote,
                              from: Mint,
                              to: Mint,
                              with proofs: [Proof],
                              pendingTransferEvent: Event) {

        updateHandler(.melting)

        let sendableFrom = CashuSwift.Mint(from)
        let blankOutputSet = pendingTransferEvent.blankOutputs

        Task {
            do {
                swapLogger.debug("Attempting to melt...")

                swapLogger.debug("transfer event has change outputs assigned: \(blankOutputSet?.outputs.isEmpty ?? true ? "empty" : "assigned and populated")")

                let meltResult = try await CashuSwift.Bolt11.melt(quote: meltQuote,
                                                                  from: sendableFrom,
                                                                  proofs: proofs.sendable(),
                                                                  blankOutputs: blankOutputSet?.tuple())

                swapLogger.info("DLEQ check on melt change proofs: \(String(describing: meltResult.dleqResult))")

                if meltResult.quote.state == .paid {

                    meltDidSucceed(mintQuote: mintQuote,
                                   newMeltQuote: meltResult.quote,
                                   change: meltResult.change ?? [],
                                   proofs: proofs,
                                   from: from,
                                   to: to,
                                   pendingTransferEvent: pendingTransferEvent)
                } else {

                    swapLogger.info("""
                                    Melt function returned a quote with state NOT PAID, \
                                    probably because the lightning payment failed
                                    """)
                    meltFailed(with: CashuError.unknownError("Transfer did not complete because the melt quote was returned with state UNPAID."),
                               reportedState: meltResult.quote.state,
                               proofs: proofs,
                               pendingTransferEvent: pendingTransferEvent)
                }
            } catch {
                swapLogger.error("Melt operation failed: \(error.localizedDescription)")

                // The thrown error alone cannot tell us whether the payment happened
                // (e.g. a timeout while the payment settles). Re-check the quote once
                // before deciding what to do with the inputs.
                let outputs = (blankOutputSet?.outputs.isEmpty == false) ? blankOutputSet?.tuple() : nil
                let recheck = try? await CashuSwift.Bolt11.meltState(meltQuote.quote,
                                                                     from: sendableFrom,
                                                                     blankOutputs: outputs)

                if let recheck, recheck.quote.state == .paid {
                    swapLogger.info("melt threw but the quote is PAID — continuing with issuance")
                    meltDidSucceed(mintQuote: mintQuote,
                                   newMeltQuote: recheck.quote,
                                   change: recheck.change ?? [],
                                   proofs: proofs,
                                   from: from,
                                   to: to,
                                   pendingTransferEvent: pendingTransferEvent)
                } else {
                    meltFailed(with: error,
                               reportedState: recheck?.quote.state,
                               proofs: proofs,
                               pendingTransferEvent: pendingTransferEvent)
                }
            }
        }
    }

    private func meltDidSucceed(mintQuote: CashuSwift.Bolt11.MintQuote,
                                newMeltQuote: CashuSwift.Bolt11.MeltQuote,
                                change: [CashuSwift.Proof],
                                proofs: [Proof],
                                from: Mint,
                                to: Mint,
                                pendingTransferEvent: Event) {

        proofs.setState(.spent)

        do {
            try from.addProofs(change,
                               to: modelContext,
                               increaseDerivationCounter: false)
            // Save immediately to persist change proofs to database
            try modelContext.save()
            swapLogger.debug("Successfully saved \(change.count) change proofs for mint \(from.url)")
        } catch {
            swapLogger.error("Failed to add/save \(change.count) change proofs to mint \(from.url): \(error.localizedDescription)")
        }

        transferIssue(mintQuote: mintQuote,
                      meltQuote: newMeltQuote,
                      from: from,
                      to: to,
                      pendingTransferEvent: pendingTransferEvent)

    }

    private func meltFailed(with error: Error,
                            reportedState: CashuSwift.QuoteState?,
                            proofs: [Proof],
                            pendingTransferEvent: Event) {
        switch TransferFlow.classifyMeltFailure(error: error, reportedState: reportedState) {
        case .definitelyUnpaid:
            swapLogger.error("Melt definitively unpaid: \(error.localizedDescription). Reverting proofs to valid state.")
            proofs.setState(.valid)
            // the event keeps its proofs and blank outputs so the melt can be retried
            try? modelContext.save()
            updateHandler(.fail(error: TransferError.meltFailure(error)))

        case .unknownOutcome:
            swapLogger.warning("Melt outcome unknown: \(error.localizedDescription). Keeping proofs pending and event data intact.")
            try? modelContext.save()
            updateHandler(.pending(message: String(localized: """
                          The payment outcome could not be determined. \
                          Check this transfer again later from the transaction list.
                          """)))
        }
    }

    private func transferIssue(mintQuote: CashuSwift.Bolt11.MintQuote,
                               meltQuote: CashuSwift.Bolt11.MeltQuote?,
                               from: Mint,
                               to: Mint,
                               pendingTransferEvent: Event) {

        guard let wallet = from.wallet else {
            updateHandler(.fail(error: macadamiaError.databaseError("mint \(from.url.absoluteString) does not have an associated wallet.")))
            return
        }

        updateHandler(.minting)

        let sendableMint = CashuSwift.Mint(to)
        let seed = wallet.seed
        let quoteID = mintQuote.quote

        Task {
            guard !TransferFlow.activeQuoteIDs.contains(quoteID) else {
                swapLogger.warning("issuance already in progress for quote \(quoteID), skipping duplicate run")
                return
            }
            TransferFlow.activeQuoteIDs.insert(quoteID)
            defer { TransferFlow.activeQuoteIDs.remove(quoteID) }

            let outcome = await TransferFlow.pollAndIssue(mintQuote: mintQuote,
                                                          on: sendableMint,
                                                          seed: seed)

            switch outcome {
            case .success(let result):
                do {
                    try TransferFlow.finalizeIssuedTransfer(issueResult: result,
                                                            mintQuote: mintQuote,
                                                            meltQuote: meltQuote,
                                                            from: from,
                                                            to: to,
                                                            pendingTransferEvent: pendingTransferEvent,
                                                            modelContext: modelContext)
                    updateHandler(.success)
                } catch {
                    swapLogger.error("Failed to persist issued transfer: \(error.localizedDescription)")
                    updateHandler(.fail(error: error))
                }

            case .parkedPending(let message, let lastError):
                swapLogger.warning("transfer parked as pending. last error: \(String(describing: lastError))")
                try? modelContext.save()
                updateHandler(.pending(message: message))

            case .alreadyIssued:
                updateHandler(.fail(error: TransferError.alreadyIssued))

            case .staleOutputs(let error):
                swapLogger.error("stale outputs during issuance: \(error.localizedDescription)")
                updateHandler(.fail(error: error))

            case .expired:
                updateHandler(.fail(error: TransferError.mintQuoteExpired))

            case .failed(let error):
                swapLogger.error("Mint/issue operation failed: \(error.localizedDescription)")
                updateHandler(.fail(error: error))
            }
        }
    }
}
