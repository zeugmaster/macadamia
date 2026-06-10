@testable import macadamia
import XCTest
import CashuSwift
import SwiftData
import BIP39

final class TransferFlowTests: XCTestCase {

    // MARK: - Helpers

    /// Test-only recorder for injected closures. Access is single-threaded in
    /// these tests (the engine awaits every closure call).
    private final class Recorder: @unchecked Sendable {
        var delays: [TimeInterval] = []
        var quoteStateCalls = 0
        var mintCalls = 0
    }

    private func makeMintQuote(state: CashuSwift.QuoteState? = .paid,
                               expiry: Int? = nil) -> CashuSwift.Bolt11.MintQuote {
        CashuSwift.Bolt11.MintQuote(quote: "quote-id-123",
                                    request: "lnbc210n1...",
                                    amount: 21,
                                    unit: "sat",
                                    state: state,
                                    expiry: expiry)
    }

    private func makeSendableMint() -> CashuSwift.Mint {
        CashuSwift.Mint(url: URL(string: "http://localhost:3338")!, keysets: [])
    }

    private func makeIssueResult() throws -> CashuSwift.IssueResult {
        // IssueResult has no public initializer but is Codable
        let json = #"{"proofs":[],"dleqResult":{"valid":{}}}"#
        return try JSONDecoder().decode(CashuSwift.IssueResult.self, from: Data(json.utf8))
    }

    // MARK: - Issue error classification

    func testClassifyIssueError() {
        XCTAssertEqual(TransferFlow.classifyIssueError(CashuError.networkError), .retryable)
        XCTAssertEqual(TransferFlow.classifyIssueError(CashuError.quoteNotPaid), .retryable)
        XCTAssertEqual(TransferFlow.classifyIssueError(CashuError.quoteIsPending), .retryable)
        XCTAssertEqual(TransferFlow.classifyIssueError(URLError(.timedOut)), .retryable)

        XCTAssertEqual(TransferFlow.classifyIssueError(CashuError.proofsAlreadyIssuedForQuote), .alreadyIssued)
        XCTAssertEqual(TransferFlow.classifyIssueError(CashuError.blindedMessageAlreadySigned), .staleOutputs)
        XCTAssertEqual(TransferFlow.classifyIssueError(CashuError.quoteIsExpired), .expired)

        XCTAssertEqual(TransferFlow.classifyIssueError(CashuError.unknownError("weird")), .terminal)
        XCTAssertEqual(TransferFlow.classifyIssueError(CashuError.alreadySpent), .terminal)
        XCTAssertEqual(TransferFlow.classifyIssueError(macadamiaError.multiMintToken), .terminal)
    }

    // MARK: - Melt failure classification

    func testClassifyMeltFailure() {
        // the mint reported unpaid — definitive, regardless of the error
        XCTAssertEqual(TransferFlow.classifyMeltFailure(error: CashuError.networkError, reportedState: .unpaid),
                       .definitelyUnpaid)
        XCTAssertEqual(TransferFlow.classifyMeltFailure(error: nil, reportedState: .unpaid),
                       .definitelyUnpaid)

        // errors thrown before the request is sent, or refusal of an expired quote
        XCTAssertEqual(TransferFlow.classifyMeltFailure(error: CashuError.quoteIsExpired, reportedState: nil),
                       .definitelyUnpaid)
        XCTAssertEqual(TransferFlow.classifyMeltFailure(error: CashuError.insufficientInputs(""), reportedState: nil),
                       .definitelyUnpaid)
        XCTAssertEqual(TransferFlow.classifyMeltFailure(error: CashuError.unitError(""), reportedState: nil),
                       .definitelyUnpaid)

        // anything transport-shaped must preserve funds
        XCTAssertEqual(TransferFlow.classifyMeltFailure(error: CashuError.networkError, reportedState: nil),
                       .unknownOutcome)
        XCTAssertEqual(TransferFlow.classifyMeltFailure(error: CashuError.quoteIsPending, reportedState: nil),
                       .unknownOutcome)
        XCTAssertEqual(TransferFlow.classifyMeltFailure(error: URLError(.timedOut), reportedState: nil),
                       .unknownOutcome)
        XCTAssertEqual(TransferFlow.classifyMeltFailure(error: nil, reportedState: nil),
                       .unknownOutcome)
        XCTAssertEqual(TransferFlow.classifyMeltFailure(error: nil, reportedState: .pending),
                       .unknownOutcome)
    }

    // MARK: - Resume decision table

    private func ctx(dest: TransferFlow.QuoteCheck,
                     source: TransferFlow.QuoteCheck? = nil,
                     expired: Bool = false,
                     hasProofs: Bool = true,
                     hasBlankOutputs: Bool = true) -> TransferFlow.ResumeContext {
        TransferFlow.ResumeContext(destination: dest,
                                   source: source,
                                   mintQuoteExpired: expired,
                                   hasProofs: hasProofs,
                                   hasBlankOutputs: hasBlankOutputs)
    }

    func testResumeActionDecisionTable() {
        // destination paid → issue, no matter what else
        XCTAssertEqual(TransferFlow.resumeAction(for: ctx(dest: .state(.paid))), .issue)
        XCTAssertEqual(TransferFlow.resumeAction(for: ctx(dest: .state(.paid), expired: true, hasProofs: false, hasBlankOutputs: false)), .issue)

        // destination issued
        XCTAssertEqual(TransferFlow.resumeAction(for: ctx(dest: .state(.issued))), .informAlreadyIssued)

        // destination mid-issuance → hands off
        XCTAssertEqual(TransferFlow.resumeAction(for: ctx(dest: .state(.pending))), .keepPendingUnknown)

        // destination unreachable → change nothing
        XCTAssertEqual(TransferFlow.resumeAction(for: ctx(dest: .unavailable)), .keepPendingUnknown)
        XCTAssertEqual(TransferFlow.resumeAction(for: ctx(dest: .unavailable, source: .state(.paid))), .keepPendingUnknown)

        // destination unpaid, source paid → settlement lag (or stranded when expired)
        XCTAssertEqual(TransferFlow.resumeAction(for: ctx(dest: .state(.unpaid), source: .state(.paid))), .pollDestinationThenIssue)
        XCTAssertEqual(TransferFlow.resumeAction(for: ctx(dest: .state(.unpaid), source: .state(.paid), expired: true)), .expiredStranded)

        // source payment in flight → wait, preserve everything
        XCTAssertEqual(TransferFlow.resumeAction(for: ctx(dest: .state(.unpaid), source: .state(.pending))), .waitSourcePending)
        XCTAssertEqual(TransferFlow.resumeAction(for: ctx(dest: .state(.unpaid), source: .state(.pending), expired: true)), .waitSourcePending)

        // nothing happened yet
        XCTAssertEqual(TransferFlow.resumeAction(for: ctx(dest: .state(.unpaid), source: .state(.unpaid))), .remelt)
        XCTAssertEqual(TransferFlow.resumeAction(for: ctx(dest: .state(.unpaid), source: .state(.unpaid), hasProofs: false)), .missingDataForRemelt)
        XCTAssertEqual(TransferFlow.resumeAction(for: ctx(dest: .state(.unpaid), source: .state(.unpaid), expired: true)), .informExpiredUnpaid)
        XCTAssertEqual(TransferFlow.resumeAction(for: ctx(dest: .state(.unpaid), source: .state(.unpaid), expired: true, hasProofs: false)), .informExpiredUnpaid)

        // source state unknown → change nothing
        XCTAssertEqual(TransferFlow.resumeAction(for: ctx(dest: .state(.unpaid), source: .unavailable)), .keepPendingUnknown)
        XCTAssertEqual(TransferFlow.resumeAction(for: ctx(dest: .state(.unpaid), source: nil)), .keepPendingUnknown)
    }

    // MARK: - pollAndIssue

    func testPollAndIssueRetriesThenSucceeds() async throws {
        let recorder = Recorder()
        let result = try makeIssueResult()

        let outcome = await TransferFlow.pollAndIssue(
            mintQuote: makeMintQuote(state: .unpaid),
            on: makeSendableMint(),
            seed: nil,
            quoteState: { [recorder] _, _ in
                recorder.quoteStateCalls += 1
                return self.makeMintQuote(state: .paid)
            },
            mintExecutor: { [recorder] _, _, _ in
                recorder.mintCalls += 1
                if recorder.mintCalls < 3 { throw CashuError.networkError }
                return result
            },
            sleeper: { [recorder] delay in recorder.delays.append(delay) }
        )

        guard case .success = outcome else {
            return XCTFail("expected success, got \(outcome)")
        }
        XCTAssertEqual(recorder.mintCalls, 3)
        // two failed mint attempts → exponential backoff 1s, 2s
        XCTAssertEqual(recorder.delays, [1, 2])
    }

    func testPollAndIssueParksWhileUnpaid() async {
        let recorder = Recorder()

        let outcome = await TransferFlow.pollAndIssue(
            mintQuote: makeMintQuote(state: .unpaid),
            on: makeSendableMint(),
            seed: nil,
            quoteState: { [recorder] _, _ in
                recorder.quoteStateCalls += 1
                return self.makeMintQuote(state: .unpaid)
            },
            mintExecutor: { [recorder] _, _, _ in
                recorder.mintCalls += 1
                XCTFail("must not attempt to mint an unpaid quote")
                throw CashuError.quoteNotPaid
            },
            sleeper: { [recorder] delay in recorder.delays.append(delay) }
        )

        guard case .parkedPending = outcome else {
            return XCTFail("expected parkedPending, got \(outcome)")
        }
        XCTAssertEqual(recorder.quoteStateCalls, 5)
        XCTAssertEqual(recorder.mintCalls, 0)
        // sleeps between polls only (none after the final one)
        XCTAssertEqual(recorder.delays, [2, 2, 2, 2])
    }

    func testPollAndIssueDetectsAlreadyIssuedFromQuoteState() async {
        let recorder = Recorder()

        let outcome = await TransferFlow.pollAndIssue(
            mintQuote: makeMintQuote(state: .paid),
            on: makeSendableMint(),
            seed: nil,
            quoteState: { _, _ in self.makeMintQuote(state: .issued) },
            mintExecutor: { [recorder] _, _, _ in
                recorder.mintCalls += 1
                throw CashuError.proofsAlreadyIssuedForQuote
            },
            sleeper: { _ in }
        )

        guard case .alreadyIssued = outcome else {
            return XCTFail("expected alreadyIssued, got \(outcome)")
        }
        XCTAssertEqual(recorder.mintCalls, 0)
    }

    func testPollAndIssueDetectsAlreadyIssuedFromMintError() async {
        let outcome = await TransferFlow.pollAndIssue(
            mintQuote: makeMintQuote(state: .paid),
            on: makeSendableMint(),
            seed: nil,
            quoteState: { _, _ in self.makeMintQuote(state: .paid) },
            mintExecutor: { _, _, _ in throw CashuError.proofsAlreadyIssuedForQuote },
            sleeper: { _ in }
        )

        guard case .alreadyIssued = outcome else {
            return XCTFail("expected alreadyIssued, got \(outcome)")
        }
    }

    func testPollAndIssueExpired() async {
        let outcome = await TransferFlow.pollAndIssue(
            mintQuote: makeMintQuote(state: .paid),
            on: makeSendableMint(),
            seed: nil,
            quoteState: { _, _ in self.makeMintQuote(state: .paid) },
            mintExecutor: { _, _, _ in throw CashuError.quoteIsExpired },
            sleeper: { _ in }
        )

        guard case .expired = outcome else {
            return XCTFail("expected expired, got \(outcome)")
        }
    }

    func testPollAndIssueTerminalError() async {
        let outcome = await TransferFlow.pollAndIssue(
            mintQuote: makeMintQuote(state: .paid),
            on: makeSendableMint(),
            seed: nil,
            quoteState: { _, _ in self.makeMintQuote(state: .paid) },
            mintExecutor: { _, _, _ in throw CashuError.unknownError("broken") },
            sleeper: { _ in }
        )

        guard case .failed = outcome else {
            return XCTFail("expected failed, got \(outcome)")
        }
    }

    func testPollAndIssueParksAfterMintRetriesExhausted() async {
        let recorder = Recorder()

        let outcome = await TransferFlow.pollAndIssue(
            mintQuote: makeMintQuote(state: .paid),
            on: makeSendableMint(),
            seed: nil,
            quoteState: { _, _ in self.makeMintQuote(state: .paid) },
            mintExecutor: { [recorder] _, _, _ in
                recorder.mintCalls += 1
                throw CashuError.networkError
            },
            sleeper: { [recorder] delay in recorder.delays.append(delay) }
        )

        guard case .parkedPending(_, let lastError) = outcome else {
            return XCTFail("expected parkedPending, got \(outcome)")
        }
        XCTAssertNotNil(lastError)
        XCTAssertEqual(recorder.mintCalls, 3)
        XCTAssertEqual(recorder.delays, [1, 2])
    }

    func testPollAndIssueMintsEvenWhenStateChecksFail() async throws {
        // the state endpoint being broken must not block issuance — the mint
        // endpoint is authoritative
        let result = try makeIssueResult()
        let recorder = Recorder()

        let outcome = await TransferFlow.pollAndIssue(
            mintQuote: makeMintQuote(state: nil),
            on: makeSendableMint(),
            seed: nil,
            quoteState: { _, _ in throw CashuError.networkError },
            mintExecutor: { [recorder] _, _, _ in
                recorder.mintCalls += 1
                return result
            },
            sleeper: { [recorder] delay in recorder.delays.append(delay) }
        )

        guard case .success = outcome else {
            return XCTFail("expected success, got \(outcome)")
        }
        XCTAssertEqual(recorder.mintCalls, 1)
    }

    // MARK: - Event helpers

    @MainActor
    func testTransferMintsHelper() throws {
        let schema = Schema([Proof.self, Mint.self, Wallet.self, Event.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext

        let mnemonic = Mnemonic()
        let wallet = Wallet(mnemonic: mnemonic.phrase.joined(separator: " "),
                            seed: String(bytes: mnemonic.seed))
        context.insert(wallet)

        let mintA = Mint(url: URL(string: "http://localhost:3338")!, keysets: [])
        let mintB = Mint(url: URL(string: "http://localhost:3339")!, keysets: [])
        context.insert(mintA)
        context.insert(mintB)

        // input proofs of a pending transfer always live at the SOURCE mint
        let inputProof = Proof(CashuSwift.Proof(keysetID: "009a1f293253e41e",
                                                amount: 21,
                                                secret: "secret",
                                                C: "02abc"),
                               unit: .sat,
                               inputFeePPK: 0,
                               state: .pending,
                               mint: mintA,
                               wallet: wallet)
        context.insert(inputProof)

        let quote = makeMintQuote(state: .paid, expiry: 1750000000)

        let event = Event(date: Date(),
                          unit: .sat,
                          shortDescription: "Pending Transfer",
                          visible: true,
                          kind: .pendingTransfer,
                          wallet: wallet,
                          mintQuote: quote,
                          proofs: [inputProof],
                          mints: [mintA, mintB])
        context.insert(event)
        try context.save()

        // SwiftData does not guarantee relationship array order across saves,
        // so from/to must be recovered via the proofs' mint — regardless of
        // how the mints array comes back.
        let endpoints = try XCTUnwrap(event.transferMints)
        XCTAssertEqual(endpoints.from.url, mintA.url)
        XCTAssertEqual(endpoints.to.url, mintB.url)

        // a completed transfer holds the issued ecash at the DESTINATION mint
        let issuedProof = Proof(CashuSwift.Proof(keysetID: "009a1f293253e41e",
                                                 amount: 21,
                                                 secret: "secret2",
                                                 C: "02def"),
                                unit: .sat,
                                inputFeePPK: 0,
                                state: .valid,
                                mint: mintB,
                                wallet: wallet)
        context.insert(issuedProof)

        let completedEvent = Event(date: Date(),
                                   unit: .sat,
                                   shortDescription: "Transfer",
                                   visible: true,
                                   kind: .transfer,
                                   wallet: wallet,
                                   mintQuote: quote,
                                   proofs: [issuedProof],
                                   mints: [mintA, mintB])
        context.insert(completedEvent)
        try context.save()

        let completedEndpoints = try XCTUnwrap(completedEvent.transferMints)
        XCTAssertEqual(completedEndpoints.from.url, mintA.url)
        XCTAssertEqual(completedEndpoints.to.url, mintB.url)

        // no index trap and nil result for events with fewer than two mints
        let singleMintEvent = Event(date: Date(),
                                    unit: .sat,
                                    shortDescription: "Pending Transfer",
                                    visible: true,
                                    kind: .pendingTransfer,
                                    wallet: wallet,
                                    mints: [mintA])
        context.insert(singleMintEvent)
        XCTAssertNil(singleMintEvent.transferMints)

        // expiry falls back to the stored quote when `expiration` was never set
        XCTAssertNil(event.expiration)
        XCTAssertEqual(event.mintQuoteExpiry, Date(timeIntervalSince1970: 1750000000))

        // dedicated endpoint references always win over the heuristics
        event.fromMint = mintB
        event.toMint = mintA
        let dedicated = try XCTUnwrap(event.transferMints)
        XCTAssertEqual(dedicated.from.url, mintB.url)
        XCTAssertEqual(dedicated.to.url, mintA.url)
    }

    // MARK: - Migration

    /// Writes a store shaped like the schema BEFORE `Event.fromMint`/`toMint`
    /// existed, then opens it with the current schema — the exact upgrade
    /// existing users perform. Must lightweight-migrate without a throw, keep
    /// legacy rows resolvable, and persist dedicated endpoints on new rows.
    @MainActor
    func testLightweightMigrationAddsDedicatedFromToMints() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macadamia-fromto-migration-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
            }
        }

        let urlA = URL(string: "http://localhost:3338")!
        let urlB = URL(string: "http://localhost:3339")!

        // 1) Write the pre-fromMint/toMint store with a full transfer object graph.
        do {
            let container = try ModelContainer(for: PreFromToSchema.Wallet.self,
                                               PreFromToSchema.Mint.self,
                                               PreFromToSchema.Proof.self,
                                               PreFromToSchema.Event.self,
                                               configurations: ModelConfiguration(url: storeURL))
            let context = ModelContext(container)

            let wallet = PreFromToSchema.Wallet(mnemonic: "m", seed: "s")
            context.insert(wallet)

            let mintA = PreFromToSchema.Mint(url: urlA)
            let mintB = PreFromToSchema.Mint(url: urlB)
            mintA.wallet = wallet
            mintB.wallet = wallet
            context.insert(mintA)
            context.insert(mintB)

            let inputProof = PreFromToSchema.Proof(C: "02abc", mint: mintA, wallet: wallet)
            context.insert(inputProof)

            context.insert(PreFromToSchema.Event(shortDescription: "Pending Transfer",
                                                 kind: .pendingTransfer,
                                                 wallet: wallet,
                                                 proofs: [inputProof],
                                                 mints: [mintA, mintB]))
            try context.save()
        }

        // 2) Open the SAME store with the current schema (the production upgrade).
        do {
            let container = try ModelContainer(for: Wallet.self, Proof.self, Mint.self, Event.self,
                                               configurations: ModelConfiguration(url: storeURL))
            let context = ModelContext(container)

            let legacyEvent = try XCTUnwrap(try context.fetch(FetchDescriptor<Event>()).first)
            XCTAssertNil(legacyEvent.fromMint, "rows from before the fields existed must read nil")
            XCTAssertNil(legacyEvent.toMint)

            // legacy resolution still orients via the proofs relationship
            let endpoints = try XCTUnwrap(legacyEvent.transferMints)
            XCTAssertEqual(endpoints.from.url, urlA)
            XCTAssertEqual(endpoints.to.url, urlB)

            // 3) A new event created through the factory carries dedicated endpoints.
            let wallet = try XCTUnwrap(try context.fetch(FetchDescriptor<Wallet>()).first)
            let mints = try context.fetch(FetchDescriptor<Mint>())
            let from = try XCTUnwrap(mints.first(where: { $0.url == urlA }))
            let to = try XCTUnwrap(mints.first(where: { $0.url == urlB }))

            let meltQuote = CashuSwift.Bolt11.MeltQuote(quote: "melt-q",
                                                        request: "lnbc210n1...",
                                                        amount: 21,
                                                        unit: "sat",
                                                        feeReserve: 1,
                                                        state: .unpaid,
                                                        expiry: nil)
            let pending = Event.pendingTransferEvent(wallet: wallet,
                                                     amount: 21,
                                                     from: from,
                                                     to: to,
                                                     proofs: [],
                                                     meltQuote: meltQuote,
                                                     mintQuote: makeMintQuote(state: .unpaid),
                                                     groupingID: nil)
            context.insert(pending)
            try context.save()
        }

        // 4) Reopen once more: the dedicated references must survive on disk —
        //    unlike the mints array, whose order SwiftData scrambles.
        let container = try ModelContainer(for: Wallet.self, Proof.self, Mint.self, Event.self,
                                           configurations: ModelConfiguration(url: storeURL))
        let context = ModelContext(container)

        let events = try context.fetch(FetchDescriptor<Event>())
        let newEvent = try XCTUnwrap(events.first(where: { $0.fromMint != nil }))
        XCTAssertEqual(newEvent.fromMint?.url, urlA)
        XCTAssertEqual(newEvent.toMint?.url, urlB)

        let resolved = try XCTUnwrap(newEvent.transferMints)
        XCTAssertEqual(resolved.from.url, urlA)
        XCTAssertEqual(resolved.to.url, urlB)
    }
}

/// Minimal stand-in for the persisted schema BEFORE `Event.fromMint`/`Event.toMint`
/// existed, used only to write a pre-migration store. Mirrors the relationship
/// topology between the four entities (same entity names, same inverses) so the
/// current schema recognises the store and lightweight-migrates it.
private enum PreFromToSchema {

    @Model
    final class Wallet {
        @Attribute(.unique) var walletID: UUID
        var mnemonic: String
        var seed: String
        var active: Bool
        var dateCreated: Date

        @Relationship(inverse: \Mint.wallet)
        var mints: [Mint]

        var proofs: [Proof]

        @Relationship(deleteRule: .cascade, inverse: \Event.wallet)
        var events: [Event]

        init(mnemonic: String, seed: String) {
            self.walletID = UUID()
            self.mnemonic = mnemonic
            self.seed = seed
            self.active = true
            self.dateCreated = Date()
            self.mints = []
            self.proofs = []
            self.events = []
        }
    }

    @Model
    final class Mint {
        @Attribute(.unique) var mintID: UUID
        var url: URL
        var keysets: [CashuSwift.Keyset]
        var dateAdded: Date
        var hidden: Bool = false
        var wallet: Wallet?
        var proofs: [Proof]?
        var events: [Event]?

        init(url: URL) {
            self.mintID = UUID()
            self.url = url
            self.keysets = []
            self.dateAdded = Date()
            self.proofs = []
        }
    }

    @Model
    final class Proof {
        @Attribute(.unique) var proofID: UUID
        var keysetID: String
        var C: String
        var secret: String
        var amount: Int
        var state: AppSchemaV1.Proof.State
        var inputFeePPK: Int
        var dateCreated: Date

        @Relationship(inverse: \Mint.proofs)
        var mint: Mint?

        @Relationship(inverse: \Wallet.proofs)
        var wallet: Wallet?

        init(C: String, mint: Mint, wallet: Wallet) {
            self.proofID = UUID()
            self.keysetID = "009a1f293253e41e"
            self.C = C
            self.secret = "secret-\(C)"
            self.amount = 21
            self.state = .pending
            self.inputFeePPK = 0
            self.dateCreated = Date()
            self.mint = mint
            self.wallet = wallet
        }
    }

    @Model
    final class Event {
        @Attribute(.unique) var eventID: UUID
        var date: Date
        var shortDescription: String
        var visible: Bool
        var kind: AppSchemaV1.Event.Kind
        var amount: Int?
        var wallet: Wallet?
        var proofs: [Proof]?

        @Relationship(deleteRule: .noAction, inverse: \Mint.events)
        var mints: [Mint]?

        init(shortDescription: String,
             kind: AppSchemaV1.Event.Kind,
             wallet: Wallet,
             proofs: [Proof],
             mints: [Mint]) {
            self.eventID = UUID()
            self.date = Date()
            self.shortDescription = shortDescription
            self.visible = true
            self.kind = kind
            self.amount = 21
            self.wallet = wallet
            self.proofs = proofs
            self.mints = mints
        }
    }
}
