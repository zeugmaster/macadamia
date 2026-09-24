//
//  transfer.swift
//  macadamia
//
//  Shared engine for the mint-to-mint transfer flow (melt at source mint,
//  issue at destination mint). Used by both SwapManager and InlineSwapManager.
//

import Foundation
import SwiftData
import CashuSwift
import OSLog

fileprivate let transferLogger = Logger(subsystem: "macadamia", category: "TransferFlow")

/// Errors specific to the transfer (melt + issue) flow.
enum TransferError: Error {
    case missingData(String)
    /// The melt definitively did not happen — the mint reported the quote unpaid.
    case meltFailure(Error)
    /// The melt request errored in a way that leaves the payment outcome unknown.
    case meltOutcomeUnknown
    case unknownQuoteState
    /// The destination mint reports the quote as already issued.
    case alreadyIssued
    /// The destination mint refuses to issue because the quote expired.
    case mintQuoteExpired
    /// The lightning payment at the source mint is still in flight.
    case paymentInFlight
}

extension TransferError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingData(let detail):
            return detail
        case .meltFailure(let error):
            return String(localized: "The payment did not go through: \(error.localizedDescription)")
        case .meltOutcomeUnknown:
            return String(localized: "The payment outcome could not be determined. Nothing was changed — check again later.")
        case .unknownQuoteState:
            return String(localized: "The mint returned an unknown quote state.")
        case .alreadyIssued:
            return String(localized: """
                          The destination mint reports that the ecash for this transfer \
                          was already issued. If your balance does not reflect it, \
                          you can recover it via Settings → Restore.
                          """)
        case .mintQuoteExpired:
            return String(localized: """
                          The destination mint's quote for this transfer has expired. \
                          If the payment already went through, the funds can only be \
                          recovered by the mint operator.
                          """)
        case .paymentInFlight:
            return String(localized: "The Lightning payment is still in flight. Check again in a moment.")
        }
    }
}

enum TransferFlow {

    // MARK: - Error classification

    enum IssueErrorClass: Equatable {
        case retryable      // transport errors or payment not yet registered
        case alreadyIssued  // 20002
        case staleOutputs   // 10002 — derivation counter desync
        case expired        // 20007
        case terminal
    }

    static func classifyIssueError(_ error: Error) -> IssueErrorClass {
        if error is URLError { return .retryable }
        guard let cashuError = error as? CashuError else { return .terminal }
        switch cashuError {
        case .networkError, .quoteNotPaid, .quoteIsPending:
            return .retryable
        case .proofsAlreadyIssuedForQuote:
            return .alreadyIssued
        case .blindedMessageAlreadySigned:
            return .staleOutputs
        case .quoteIsExpired:
            return .expired
        default:
            return .terminal
        }
    }

    // MARK: - Retry policy

    struct IssueRetryPolicy: Sendable {
        let quotePollInterval: TimeInterval
        let quotePollMaxAttempts: Int
        let mintMaxAttempts: Int
        let backoffBase: TimeInterval
        let backoffCap: TimeInterval
        let totalBudget: TimeInterval

        static let interactive = IssueRetryPolicy(quotePollInterval: 2,
                                                  quotePollMaxAttempts: 5,
                                                  mintMaxAttempts: 3,
                                                  backoffBase: 1,
                                                  backoffCap: 4,
                                                  totalBudget: 30)

        func backoff(forAttempt attempt: Int) -> TimeInterval {
            min(backoffCap, backoffBase * pow(2, Double(attempt - 1)))
        }
    }

    // MARK: - Poll & issue

    enum IssueOutcome {
        case success(CashuSwift.IssueResult)
        /// Retries or time budget exhausted without a definitive failure.
        /// The pending event stays resumable.
        case parkedPending(message: String, lastError: Error?)
        case alreadyIssued
        case staleOutputs(Error)
        case expired
        case failed(Error)
    }

    /// Quote IDs currently being issued, to prevent the same transfer from
    /// being completed twice concurrently (e.g. a double-tapped button).
    @MainActor static var activeQuoteIDs = Set<String>()

    /// Polls the destination mint's quote state until it is paid, then issues
    /// ecash with retry and backoff on transient errors.
    ///
    /// Operates on sendable snapshots only and never touches SwiftData models.
    /// Never throws — every path maps to an `IssueOutcome`.
    static func pollAndIssue(mintQuote: CashuSwift.Bolt11.MintQuote,
                             on mint: CashuSwift.Mint,
                             seed: String?,
                             policy: IssueRetryPolicy = .interactive,
                             quoteState: (@Sendable (String, CashuSwift.Mint) async throws -> CashuSwift.Bolt11.MintQuote)? = nil,
                             mintExecutor: (@Sendable (CashuSwift.Bolt11.MintQuote, CashuSwift.Mint, String?) async throws -> CashuSwift.IssueResult)? = nil,
                             sleeper: (@Sendable (TimeInterval) async -> Void)? = nil) async -> IssueOutcome {

        let fetchQuoteState = quoteState ?? { id, mint in
            try await CashuSwift.Bolt11.mintQuoteState(id, from: mint)
        }
        let executeMint = mintExecutor ?? { quote, mint, seed in
            try await CashuSwift.Bolt11.mint(quote: quote, from: mint, seed: seed)
        }
        let sleep = sleeper ?? { seconds in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }

        let start = Date()
        func budgetExhausted() -> Bool {
            Date().timeIntervalSince(start) >= policy.totalBudget
        }

        // Phase 1: wait for the destination mint to register the payment.
        // A state-check failure is never terminal (it is read-only) — only a
        // reported state can end the wait early.
        var lastKnownState: CashuSwift.QuoteState? = nil
        pollLoop: for attempt in 1...policy.quotePollMaxAttempts {
            do {
                let current = try await fetchQuoteState(mintQuote.quote, mint)
                lastKnownState = current.state
                transferLogger.debug("quote state poll \(attempt): \(current.state?.rawValue ?? "nil")")
            } catch {
                transferLogger.warning("quote state poll \(attempt) failed: \(error.localizedDescription)")
                if classifyIssueError(error) == .expired { return .expired }
            }

            switch lastKnownState {
            case .paid:
                break pollLoop
            case .issued:
                return .alreadyIssued
            default:
                if attempt < policy.quotePollMaxAttempts, !budgetExhausted() {
                    await sleep(policy.quotePollInterval)
                }
            }
        }

        if lastKnownState == .unpaid || lastKnownState == .pending {
            return .parkedPending(message: String(localized: """
                                  The destination mint has not registered the payment yet. \
                                  You can complete this transfer later from the transaction list.
                                  """),
                                  lastError: nil)
        }
        // State .paid or unknown (all polls errored): attempt to mint anyway —
        // the mint endpoint is authoritative and its errors are classified below.

        // Phase 2: issue with retry and backoff.
        var lastError: Error? = nil
        mintLoop: for attempt in 1...policy.mintMaxAttempts {
            do {
                let result = try await executeMint(mintQuote, mint, seed)
                transferLogger.info("issued ecash after \(attempt) attempt(s), DLEQ: \(String(describing: result.dleqResult))")
                return .success(result)
            } catch {
                lastError = error
                let classification = classifyIssueError(error)
                transferLogger.warning("mint attempt \(attempt) failed (\(String(describing: classification))): \(error.localizedDescription)")

                switch classification {
                case .retryable:
                    guard attempt < policy.mintMaxAttempts, !budgetExhausted() else {
                        break mintLoop
                    }
                    await sleep(policy.backoff(forAttempt: attempt))
                case .alreadyIssued:
                    return .alreadyIssued
                case .staleOutputs:
                    return .staleOutputs(error)
                case .expired:
                    return .expired
                case .terminal:
                    return .failed(error)
                }
            }
        }

        return .parkedPending(message: String(localized: """
                              The destination mint did not respond. \
                              You can complete this transfer later from the transaction list.
                              """),
                              lastError: lastError)
    }

    // MARK: - Resume decision

    /// What we know about a quote at the time of resuming a transfer.
    enum QuoteCheck: Equatable {
        case state(CashuSwift.QuoteState)
        case unavailable
    }

    struct ResumeContext: Equatable {
        let destination: QuoteCheck     // mint quote state at the destination mint
        let source: QuoteCheck?         // melt quote state at the source mint; nil = not consulted
        let mintQuoteExpired: Bool
        let hasProofs: Bool
        let hasBlankOutputs: Bool
    }

    enum ResumeAction: Equatable {
        case issue                      // destination paid → issue now
        case informAlreadyIssued
        case pollDestinationThenIssue   // source paid, destination lagging
        case waitSourcePending          // lightning payment in flight — change nothing
        case remelt                     // nothing happened yet, inputs available
        case missingDataForRemelt
        case informExpiredUnpaid        // quote expired before payment — reversion allowed
        case expiredStranded            // paid but expired — operator recovery
        case keepPendingUnknown         // could not determine states — change nothing
    }

    /// Pure, destination-first decision on how to resume a pending transfer.
    static func resumeAction(for ctx: ResumeContext) -> ResumeAction {
        switch ctx.destination {
        case .unavailable:
            return .keepPendingUnknown
        case .state(.paid):
            // Attempt issuance even when expired — some mints allow it,
            // a refusal surfaces as IssueOutcome.expired.
            return .issue
        case .state(.issued):
            return .informAlreadyIssued
        case .state(.pending):
            // Destination is mid-issuance (possibly a concurrent attempt) — do not interfere.
            return .keepPendingUnknown
        case .state(.unpaid):
            guard let source = ctx.source else { return .keepPendingUnknown }
            switch source {
            case .unavailable, .state(.issued):
                return .keepPendingUnknown
            case .state(.paid):
                return ctx.mintQuoteExpired ? .expiredStranded : .pollDestinationThenIssue
            case .state(.pending):
                return .waitSourcePending
            case .state(.unpaid):
                if ctx.mintQuoteExpired { return .informExpiredUnpaid }
                return ctx.hasProofs ? .remelt : .missingDataForRemelt
            }
        }
    }

    // MARK: - Melt failure classification

    enum MeltFailureClass: Equatable {
        /// The mint reported the quote unpaid (or the request never reached it) —
        /// inputs can safely return to the valid state.
        case definitelyUnpaid
        /// The payment may still settle — inputs must stay pending and the
        /// event must keep its data.
        case unknownOutcome
    }

    static func classifyMeltFailure(error: Error?, reportedState: CashuSwift.QuoteState?) -> MeltFailureClass {
        if reportedState == .unpaid { return .definitelyUnpaid }

        if let cashuError = error as? CashuError {
            switch cashuError {
            // Thrown by client-side validation before the melt request is sent,
            // or by the mint refusing to pay an expired quote.
            case .quoteIsExpired, .insufficientInputs, .unitError, .noActiveKeysetForUnit:
                return .definitelyUnpaid
            default:
                return .unknownOutcome
            }
        }
        return .unknownOutcome
    }

    // MARK: - Source-side recovery

    /// Opportunistically settles the source side of a transfer whose payment is
    /// known to have happened: marks the inputs spent and stores any NUT-08
    /// change. Failures are logged and never block issuance at the destination.
    @MainActor
    static func recoverSourceSide(meltQuote: CashuSwift.Bolt11.MeltQuote?,
                                  from: Mint,
                                  sendableFrom: CashuSwift.Mint,
                                  preFetched: CashuSwift.MeltResult<CashuSwift.Bolt11.MeltQuote>?,
                                  blankOutputSet: BlankOutputSet?,
                                  proofs: [Proof]?,
                                  modelContext: ModelContext) async {
        guard let meltQuote else { return }

        let result: CashuSwift.MeltResult<CashuSwift.Bolt11.MeltQuote>?
        if let preFetched {
            result = preFetched
        } else {
            let outputs = (blankOutputSet?.outputs.isEmpty == false) ? blankOutputSet?.tuple() : nil
            result = try? await CashuSwift.Bolt11.meltState(meltQuote.quote,
                                                            from: sendableFrom,
                                                            blankOutputs: outputs)
        }

        guard let result, result.quote.state == .paid else { return }

        proofs?.setState(.spent)
        if let change = result.change, !change.isEmpty {
            do {
                // re-adding previously stored change is safe: duplicates are skipped by C value
                try from.addProofs(change, to: modelContext, increaseDerivationCounter: false)
            } catch {
                transferLogger.warning("could not store melt change during resume: \(error.localizedDescription)")
            }
        }
        try? modelContext.save()
    }

    // MARK: - Finalization

    /// Persists the result of a successful issuance: stores the new proofs
    /// (incrementing the destination keyset counter), records the transfer
    /// event and hides the pending event.
    @MainActor
    static func finalizeIssuedTransfer(issueResult: CashuSwift.IssueResult,
                                       mintQuote: CashuSwift.Bolt11.MintQuote,
                                       meltQuote: CashuSwift.Bolt11.MeltQuote?,
                                       from: Mint,
                                       to: Mint,
                                       pendingTransferEvent: Event,
                                       modelContext: ModelContext) throws {
        guard let wallet = from.wallet else {
            throw macadamiaError.databaseError("mint \(from.url.absoluteString) does not have an associated wallet.")
        }

        let internalProofs = try to.addProofs(issueResult.proofs, to: modelContext)

        guard let meltQuote = meltQuote ?? pendingTransferEvent.bolt11MeltQuote else {
            // No melt quote to record — still persist the proofs and resolve the event.
            transferLogger.warning("finalizing transfer without a melt quote on record")
            pendingTransferEvent.visible = false
            try modelContext.save()
            return
        }

        let transferEvent = Event.transferEvent(wallet: wallet,
                                                amount: pendingTransferEvent.amount ?? 0,
                                                from: from,
                                                to: to,
                                                proofs: internalProofs,
                                                meltQuote: meltQuote,
                                                mintQuote: mintQuote,
                                                preImage: meltQuote.paymentPreimage,
                                                groupingID: nil)
        modelContext.insert(transferEvent)
        pendingTransferEvent.visible = false
        try modelContext.save()
    }
}
