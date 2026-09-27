@testable import macadamia
import CashuSwift
import SwiftData
import SwiftUI
import XCTest

final class BOLT11MeltTests: XCTestCase {
    private func input(_ name: String = "10000") throws -> BOLT11InvoiceInput {
        try BOLT11InvoiceInput(XCTUnwrap(Self.invoices[name]))
    }

    private func candidate(_ balance: Int, id: UUID = UUID(), mpp: Bool = true) -> BOLT11PaymentPlan.Candidate {
        .init(mintID: id, balanceSat: balance, supportsMPP: mpp)
    }

    private func quote(_ amount: Int, id: String = "quote", fee: Int = 0, unit: String = "sat",
                       request: String? = nil, state: CashuSwift.QuoteState? = .unpaid,
                       expiry: Int? = nil) -> CashuSwift.Bolt11.MeltQuote {
        .init(quote: id, request: request, amount: amount, unit: unit, feeReserve: fee, state: state, expiry: expiry)
    }

    @MainActor
    private func fixture(_ balances: [Int], inputFee: Int = 0, urls: [URL]? = nil) throws -> (ModelContainer, [Mint]) {
        let container = try ModelContainer(for: Wallet.self, Mint.self, Proof.self, Event.self,
                                           NostrKeypair.self, NostrMessage.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let wallet = Wallet(mnemonic: "test", seed: "test")
        container.mainContext.insert(wallet)
        let keyset = try JSONDecoder().decode(CashuSwift.Keyset.self, from: Data(#"{"id":"009a1f293253e41e","unit":"sat","active":true,"keys":{},"derivationCounter":0}"#.utf8))
        let mints = balances.enumerated().map { index, balance in
            let mint = Mint(url: urls?[index] ?? URL(string: "https://mint-\(index).invalid")!, keysets: [keyset])
            mint.wallet = wallet
            container.mainContext.insert(mint)
            if balance > 0 {
                container.mainContext.insert(Proof(keysetID: keyset.keysetID, C: "02" + String(repeating: "11", count: 32),
                                                  secret: UUID().uuidString, unit: .sat, inputFeePPK: inputFee,
                                                  state: .valid, amount: balance, mint: mint, wallet: wallet))
            }
            return mint
        }
        try container.mainContext.save()
        return (container, mints)
    }

    @MainActor
    private func candidates(_ mints: [Mint]) -> [BOLT11PaymentPlan.Candidate] {
        mints.map { candidate($0.balance(for: .sat), id: $0.mintID) }
    }

    @MainActor
    private func assertUnspent(_ container: ModelContainer, _ mints: [Mint], file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<Event>()).isEmpty, file: file, line: line)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<Proof>()).allSatisfy { $0.state == .valid }, file: file, line: line)
        XCTAssertTrue(mints.flatMap(\.keysets).allSatisfy { $0.derivationCounter == 0 }, file: file, line: line)
    }

    func testIntegerParsingAndCeilingBoundaries() throws {
        for (msat, sat) in [(1, 1), (999, 1), (1000, 1), (1001, 2), (1999, 2), (2000, 2),
                            (100_000_000, 100_000), (100_000_001, 100_001), (9_223_372_036_854_775_000, 9_223_372_036_854_775)] {
            let parsed = try input(String(msat))
            XCTAssertEqual(parsed.amountMsat, msat)
            XCTAssertEqual(parsed.amountSat, sat)
            XCTAssertEqual(parsed.supportsWholeSatMPP, msat % 1000 == 0)
            XCTAssertEqual(try BOLT11InvoiceInput(parsed.request.uppercased()).amountMsat, msat)
        }
        for name in ["btc", "milli", "micro", "nano", "pico"] {
            XCTAssertEqual(try input(name).amountMsat, 100_000_000_000)
        }
    }

    func testInvalidAndExpiredInvoicesAreRejected() throws {
        for name in ["zero", "amountless", "submsat", "overflow", "intOverflow"] {
            XCTAssertThrowsError(try input(name), name)
        }
        let original = try input().request
        XCTAssertThrowsError(try BOLT11InvoiceInput(original.dropLast() + (original.last == "q" ? "p" : "q")))
        XCTAssertThrowsError(try BOLT11InvoiceInput("lnbc123"))
        XCTAssertThrowsError(try BOLT11InvoiceInput(original, now: Date(timeIntervalSince1970: 5_000_000_000)))
    }

    func testExactStableMPPAllocationsAndZeroLegs() throws {
        let mints = [candidate(10), candidate(10), candidate(10), candidate(0)]
        let plan = try BOLT11PaymentPlan(input: input(), candidates: mints)
        XCTAssertEqual(plan.legs.map(\.amountSat), [4, 3, 3])
        XCTAssertEqual(plan.legs.map(\.amountMsat), [4000, 3000, 3000])
        XCTAssertEqual(plan.legs.map(\.mintID), Array(mints.prefix(3)).map(\.mintID))
        XCTAssertTrue(plan.isMPP)
        XCTAssertEqual(try BOLT11PaymentPlan(input: input(), candidates: mints), plan)

        let small = try BOLT11PaymentPlan(input: input("1000"), candidates: [candidate(2), candidate(2), candidate(2)])
        XCTAssertEqual(small.legs.count, 1)
        XCTAssertFalse(small.isMPP)
        XCTAssertNil(small.request(for: small.legs[0]).extra)
        XCTAssertEqual(small.legs[0].amountMsat, 1000)

        let large = try BOLT11PaymentPlan(input: input("1000000000000000"),
                                         candidates: [candidate(9_000_000_000_000), candidate(3_000_000_000_000)])
        XCTAssertEqual(large.legs.map(\.amountSat), [750_000_000_000, 250_000_000_000])
        XCTAssertEqual(large.legs.reduce(0) { $0 + $1.amountMsat }, large.input.amountMsat)
        XCTAssertThrowsError(try BOLT11PaymentPlan(input: input(), candidates: [candidate(Int.max), candidate(Int.max)]))
        XCTAssertThrowsError(try BOLT11PaymentPlan(input: input(), candidates: [candidate(-1)]))
        XCTAssertThrowsError(try BOLT11PaymentPlan(input: input(), candidates: [candidate(6), candidate(4, mpp: false)]))
    }

    func testAutomaticSelectionAndFractionalMPPPolicy() throws {
        let whole = try input()
        let mints = [candidate(0), candidate(4), candidate(7), candidate(3, mpp: false)]
        XCTAssertEqual(try BOLT11PaymentPlan.automaticSelection(input: whole, candidates: mints).map(\.mintID), [mints[2].mintID, mints[1].mintID])
        XCTAssertThrowsError(try BOLT11PaymentPlan.automaticSelection(input: whole, candidates: [candidate(4), candidate(5)]))
        let fractional = try input("100000001")
        let insufficient = [candidate(100_000), candidate(100_000)]
        XCTAssertThrowsError(try BOLT11PaymentPlan.automaticSelection(input: fractional, candidates: insufficient)) {
            XCTAssertEqual($0 as? BOLT11PaymentError, .fractionalMPP)
        }
        let single = candidate(100_001, mpp: false)
        XCTAssertEqual(try BOLT11PaymentPlan.automaticSelection(input: fractional, candidates: insufficient + [single]), [single])
        XCTAssertThrowsError(try BOLT11PaymentPlan(input: fractional, candidates: [single, candidate(200_000)]))
        let plan = try BOLT11PaymentPlan(input: fractional, candidates: [single])
        XCTAssertEqual(plan.legs[0].amountMsat, 100_000_001)
        XCTAssertEqual(plan.legs[0].amountSat, 100_001)
        XCTAssertNil(plan.request(for: plan.legs[0]).extra)
    }

    func testFullQuoteRequiresExactCeilingAndPreservesInvoice() throws {
        let plan = try BOLT11PaymentPlan(input: input("100000001"), candidates: [candidate(200_000)])
        let leg = plan.legs[0]
        XCTAssertEqual(try plan.validate(quote(100_001), for: leg).request, plan.input.request)
        XCTAssertNoThrow(try plan.validate(quote(100_001, request: plan.input.request.uppercased(), state: nil), for: leg))
        for response in [quote(100_000), quote(100_002), quote(100_001, unit: "msat"),
                         quote(100_001, fee: -1), quote(100_001, fee: Int.max), quote(100_001, expiry: 1),
                         quote(100_001, request: try input().request), quote(100_001, state: .paid), quote(100_001, id: "")] {
            XCTAssertThrowsError(try plan.validate(response, for: leg))
        }
    }

    func testEachPartialQuoteMustMatchItsRequestedShare() throws {
        let plan = try BOLT11PaymentPlan(input: input(), candidates: [candidate(6), candidate(4)])
        XCTAssertEqual(plan.legs.map(\.amountSat), [6, 4])
        for (leg, badAmount) in zip(plan.legs, [7, 3]) {
            XCTAssertThrowsError(try plan.validate(quote(badAmount), for: leg)) {
                XCTAssertEqual($0 as? BOLT11PaymentError, .amountMismatch(expected: leg.amountSat, received: badAmount))
            }
            XCTAssertNoThrow(try plan.validate(quote(leg.amountSat), for: leg))
            XCTAssertThrowsError(try plan.validate(quote(10), for: leg))
        }
    }

    @MainActor
    func testFullAndPartialHTTPRequestsAndQuoteFunding() async throws {
        for partial in [false, true] {
            let input = try input(partial ? "10000" : "1001")
            let amounts = partial ? [6, 4] : [2]
            let stubs = try amounts.map { expected in
                try MintHTTPStub { request in
                    XCTAssertEqual(request.url?.path, "/v1/melt/quote/bolt11")
                    let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
                    XCTAssertEqual(body["request"] as? String, input.request)
                    XCTAssertEqual(body["unit"] as? String, "sat")
                    if partial {
                        let options = try XCTUnwrap(body["options"] as? [String: Any])
                        XCTAssertEqual((options["mpp"] as? [String: Int])?["amount"], expected * 1000)
                    } else { XCTAssertNil(body["options"]) }
                    return try JSONSerialization.data(withJSONObject: ["quote": "quote-\(expected)", "amount": expected,
                                                                      "unit": "sat", "fee_reserve": 1, "state": "UNPAID",
                                                                      "request": input.request.uppercased()])
                }
            }
            defer { stubs.forEach { $0.remove() } }
            let (container, mints) = try fixture(partial ? [8, 5] : [10], urls: stubs.map(\.url))
            let loader = BOLT11QuoteLoader()
            await loader.load(input: input, candidates: candidates(mints), automatic: false, mints: mints)
            guard case .ready(let bundles, let fees) = loader.state else { return XCTFail("Expected ready: \(loader.state)") }
            XCTAssertEqual(bundles.map(\.quote.amount), amounts)
            XCTAssertTrue(bundles.allSatisfy { $0.quote.request == input.request })
            XCTAssertEqual(fees, amounts.count)
            XCTAssertTrue(stubs.allSatisfy { $0.requests.count == 1 })
            try assertUnspent(container, mints)
        }
    }

    @MainActor
    func testMalformedPartialResponsesNeverEnablePayment() async throws {
        let input = try input()
        for mutation in ["method", "request", "fractionalAmount", "oversizedAmount", "fractionalFee", "unit", "mintError"] {
            let stub = try MintHTTPStub { _ in
                var body: [String: Any] = ["quote": "bad", "amount": 6, "unit": "sat", "fee_reserve": 0, "state": "UNPAID"]
                switch mutation {
                case "method": body["method"] = "bolt12"
                case "request": body["request"] = "different-invoice"
                case "fractionalAmount": body["amount"] = 6.5
                case "oversizedAmount": body["amount"] = 1e100
                case "fractionalFee": body["fee_reserve"] = 0.5
                case "mintError": body = ["code": 20000, "detail": "internal mpp not allowed"]
                default: body["unit"] = "msat"
                }
                return try JSONSerialization.data(withJSONObject: body)
            }
            let unused = try MintHTTPStub { _ in
                XCTFail("Must reject the first quote before fetching another")
                return Data()
            }
            defer { stub.remove(); unused.remove() }
            let (container, mints) = try fixture([6, 4], urls: [stub.url, unused.url])
            let loader = BOLT11QuoteLoader()
            await loader.load(input: input, candidates: candidates(mints), automatic: false, mints: mints)
            guard case .error(let message) = loader.state else { return XCTFail("Accepted \(mutation)") }
            if mutation == "mintError" { XCTAssertTrue(message.contains(String(localized: "Self-pay not possible"))) }
            XCTAssertEqual(stub.requests.count, 1)
            XCTAssertTrue(unused.requests.isEmpty)
            try assertUnspent(container, mints)
        }
    }

    @MainActor
    func testFractionalSplitsAreRejectedBeforeFetching() async throws {
        let (container, mints) = try fixture([1, 1])
        let fractional = try input("1001")
        for automatic in [false, true] {
            let loader = BOLT11QuoteLoader()
            await loader.load(input: fractional, candidates: candidates(mints), automatic: automatic, mints: mints) { _, _ in
                XCTFail("Must not request fractional MPP")
                throw CashuError.invalidAmount
            }
            guard case .error = loader.state else { return XCTFail("Expected actionable split error") }
            XCTAssertNil(loader.plan)
            try assertUnspent(container, mints)
        }
    }

    @MainActor
    func testFundingIsCheckedPerMintIncludingInputFees() async throws {
        let (container, mints) = try fixture([100, 50])
        let loader = BOLT11QuoteLoader()
        let first = quote(7), second = quote(3, fee: 49)
        let firstURL = mints[0].url
        await loader.load(input: try input(), candidates: candidates(mints), automatic: false, mints: mints) { _, mint in
            mint.url == firstURL ? first : second
        }
        XCTAssertEqual(loader.state, .insufficientBalance)
        try assertUnspent(container, mints)

        let (feeContainer, feeMints) = try fixture([2], inputFee: 1000)
        let response = quote(1, fee: 1)
        await loader.load(input: try input("1000"), candidates: candidates(feeMints), automatic: false, mints: feeMints) { _, _ in response }
        XCTAssertEqual(loader.state, .insufficientBalance)
        try assertUnspent(feeContainer, feeMints)
    }

    @MainActor
    func testViewPublishesFullAndPartialQuotesAndBlocksFractionalSplits() async throws {
        for scenario in ["full", "partial", "fractionalSplit"] {
            let input = try input(scenario == "partial" ? "10000" : "1001")
            let balances = scenario == "full" ? [3] : (scenario == "partial" ? [7, 4] : [1, 1])
            let expected = scenario == "full" ? [2] : [6, 4]
            let stubs = try balances.indices.map { index in
                try MintHTTPStub { _ in
                    XCTAssertNotEqual(scenario, "fractionalSplit", "Unsupported splits must not fetch quotes")
                    return try JSONSerialization.data(withJSONObject: ["quote": "quote-\(index)", "amount": expected[index],
                                                                      "unit": "sat", "fee_reserve": 0, "state": "UNPAID"])
                }
            }
            defer { stubs.forEach { $0.remove() } }
            let (container, mints) = try fixture(balances, urls: stubs.map(\.url))
            let info = try JSONDecoder().decode(CashuSwift.Mint.Info.self, from: Data(#"{"nuts":{"15":{"supported":true}}}"#.utf8))
            for (index, mint) in mints.enumerated() {
                mint.userIndex = index
                try mint.setPreviewInfo(info)
            }
            let settled = expectation(description: "View settles for \(scenario)")
            let probe = BOLT11SourceProbe()
            probe.settled = settled
            let controller = UIHostingController(rootView: BOLT11SourceProbeView(probe: probe, invoice: input.request)
                .modelContainer(container)
                .environmentObject(AppState(preview: true, preferredUnit: .usd)))
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
            window.rootViewController = controller
            window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil }
            await fulfillment(of: [settled], timeout: 5)
            if scenario == "fractionalSplit" {
                guard case .error(let message) = probe.state else { return XCTFail("Expected unsupported split") }
                XCTAssertEqual(message, BOLT11PaymentError.fractionalMPP.localizedDescription)
                XCTAssertTrue(stubs.allSatisfy { $0.requests.isEmpty })
            } else {
                guard case .ready(let bundles, _) = probe.state else { return XCTFail("View stayed in \(probe.state)") }
                XCTAssertEqual(bundles.map(\.quote.amount), expected)
                try assertUnspent(container, mints)

                // A balance change must invalidate the payable snapshot in the view.
                let changed = expectation(description: "Balance change clears ready state")
                probe.settled = changed
                mints.flatMap { $0.proofs ?? [] }.forEach { $0.state = .pending }
                await fulfillment(of: [changed], timeout: 5)
                if case .ready = probe.state { XCTFail("Kept obsolete payable quotes") }
                XCTAssertTrue(stubs.allSatisfy { $0.requests.count == 1 })
            }
        }
    }

    @MainActor
    func testObsoleteSuccessAndErrorCannotReplaceCurrentPlan() async throws {
        let (container, mints) = try fixture([100, 100])
        let oldInput = try input()
        for scenario in ["reset", "invoice", "selection", "allocation", "samePlan", "error", "cancel"] {
            let loader = BOLT11QuoteLoader()
            let started = expectation(description: scenario)
            let delayed = DelayedQuote()
            let oldCandidates = candidates([mints[0]])
            let oldTask = Task { @MainActor in
                await loader.load(input: oldInput, candidates: oldCandidates, automatic: false, mints: mints) { _, _ in
                    try await delayed.wait(started: started)
                }
            }
            await fulfillment(of: [started], timeout: 2)
            if scenario == "reset" || scenario == "cancel" {
                loader.reset()
                if scenario == "cancel" { oldTask.cancel() }
            } else {
                let newInput = try scenario == "invoice" ? input("1001") : oldInput
                let selected = scenario == "selection" ? [mints[1]] : (scenario == "allocation" ? mints : [mints[0]])
                let newCandidates = candidates(selected)
                let newPlan = try BOLT11PaymentPlan(input: newInput, candidates: newCandidates)
                let responses = Dictionary(uniqueKeysWithValues: zip(selected.map(\.url), newPlan.legs).map { ($0.0, quote($0.1.amountSat, id: "new")) })
                await loader.load(input: newInput, candidates: newCandidates, automatic: false, mints: mints) { _, mint in
                    try XCTUnwrap(responses[mint.url])
                }
            }
            await delayed.finish(scenario == "error" ? .failure(CashuError.networkError) : .success(quote(10, id: "old")))
            await oldTask.value
            if scenario == "reset" || scenario == "cancel" {
                XCTAssertEqual(loader.state, .awaitingInput)
                XCTAssertTrue(loader.entries.isEmpty)
            } else {
                guard case .ready(let bundles, _) = loader.state else { return XCTFail("Lost new plan for \(scenario)") }
                XCTAssertTrue(bundles.allSatisfy { $0.quote.quote == "new" })
                XCTAssertEqual(loader.entries.count, bundles.count)
            }
        }
        try assertUnspent(container, mints)
    }

    private actor DelayedQuote {
        private var continuation: CheckedContinuation<CashuSwift.Bolt11.MeltQuote, Error>?
        func wait(started: XCTestExpectation) async throws -> CashuSwift.Bolt11.MeltQuote {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                started.fulfill()
            }
        }
        func finish(_ result: Result<CashuSwift.Bolt11.MeltQuote, Error>) { continuation?.resume(with: result) }
    }

    // Signed, non-payable fixtures generated with bolt11 2.1.0, test signing key 0101…01,
    // timestamp 1790000000 and expiry 3153600000. No runtime/network fixture generation.
    private static let invoices: [String: String] = [
        "1": "lnbc10p1p4tzwuqpp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygssp5yg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3qdpgg9kk7atwwss8yet8wfjhxumfdahzqenf0p682un9xq8zals8sqw8x4rkx4vlkeqcxwtnqtjpkzddc52q36zvwqwqm23h64xl9qnsw9nqwqdr2vdezs7qrucn782tkvc04pxh4xn7qte7dkeyy7alkpcmqp0qyp55",
        "999": "lnbc9990p1p4tzwuqpp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygssp5yg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3qdpgg9kk7atwwss8yet8wfjhxumfdahzqenf0p682un9xq8zals8sqlvu3g53wwx538r3rk6edmpwl3uhz2s7pn87rlly0j003avt2qvqrrl33qy3l6j6dfjadmwfsuv2nrspjmf8sqs4ek9aystmfdr3c9yqqn6wknz",
        "1000": "lnbc10n1p4tzwuqpp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygssp5yg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3qdpgg9kk7atwwss8yet8wfjhxumfdahzqenf0p682un9xq8zals8sqsh9qzmpyz5gqknj4720j7z9ht7wdr9hg9wmgqs8awrxwpt7mn2lz0s82y3758teqqrddk7z94x8dndzah6ukmgsj9hu6m5vauxvn5lgpdsktr9",
        "1001": "lnbc10010p1p4tzwuqpp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygssp5yg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3qdpgg9kk7atwwss8yet8wfjhxumfdahzqenf0p682un9xq8zals8sql285p5c62w9ttljkcxjmut62ftxqgmx52ft5x2crvr9n76e0qky5akk4gznhrf3s4rpewjf3l9rht3ejk65ldamgh7x033rvkzsplpsq2yta0r",
        "1999": "lnbc19990p1p4tzwuqpp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygssp5yg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3qdpgg9kk7atwwss8yet8wfjhxumfdahzqenf0p682un9xq8zals8sq4fuzljwy7anhjvq9lqpl28pnfvyvrqkps4u03g0akzw65vqvchk5mwxa49fy24ezer53xx37gg3ltv42a2gasj2se3az5vlxq7j3j4cp2ujh37",
        "2000": "lnbc20n1p4tzwuqpp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygssp5yg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3qdpgg9kk7atwwss8yet8wfjhxumfdahzqenf0p682un9xq8zals8sq894dqpsvew9rqclct2tl2c5yydl9hc2rccya6hn45rfks030yd74mte7e5zaqpfftk4xdxx83j0j4yj49tr6ya5dvd3fr3kxs6fy6rsprt47vn",
        "10000": "lnbc100n1p4tzwuqpp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygssp5yg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3qdpgg9kk7atwwss8yet8wfjhxumfdahzqenf0p682un9xq8zals8sqwnce9a7h4n39hnhfyrmafwy856c5kgaz95lm6pcmj4wmmmr6xefskev2lmsex94y9qvjvmfgfp7ffgmze5yue2ajksg4e4jsk95vyksphr7t25",
        "100000000": "lnbc1m1p4tzwuqpp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygssp5yg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3qdpgg9kk7atwwss8yet8wfjhxumfdahzqenf0p682un9xq8zals8sqw56xky0zx8slf9xz3wsvd48d23sxqcnn7892kehnrfda8g2g58hskr4s3meczdzkjj8jp933hgd72v0r8hclqy9329u6y45a7r5988gqn5lag6",
        "100000001": "lnbc1000000010p1p4tzwuqpp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygssp5yg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3qdpgg9kk7atwwss8yet8wfjhxumfdahzqenf0p682un9xq8zals8sqmevdjywaxl89h8ssjlzqpm7vjky7megzg9wp94d5wexvdd9chwqzk09y6jj3czk2sajud9lrxeg0fypph0pllvhwnwq7fn4pu0cu0gcqnyd5nr",
        "1000000000000000": "lnbc100001p4tzwuqpp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygssp5yg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3qdpgg9kk7atwwss8yet8wfjhxumfdahzqenf0p682un9xq8zals8sq2k6nxeudt5u4ne9ggepzhhk3ygjyp2p7a5xjlccdeaa8v7h580lzwhtz0ka8e3cx0g3gjwhsw0n22q92fqs58kuctcql3zhqj5jftvgpzz3u62",
        "9223372036854775000": "lnbc92233720368547750n1p4tzwuqpp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygssp5yg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3qdpgg9kk7atwwss8yet8wfjhxumfdahzqenf0p682un9xq8zals8sqvzumn89n3s23p39qx6w0ms35ln7e0p8mve86qahpy5k8r5avalayzu2njg38x3sv4yt3sdep8h6s6jl8x9drds8gexs4mfp23268cgspnw84ld",
        "btc": "lnbc11p4tzwuqpp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygssp5yg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3qdpgg9kk7atwwss8yet8wfjhxumfdahzqenf0p682un9xq8zals8sqeh62z6qlrrfj83kqr326njchkzeay2q4z59n32unxka2aucurtshgy63muemhx80lwljw7qe3wr0g967ducgf76dc6zr7vjsrx3jergqruv923",
        "milli": "lnbc1000m1p4tzwuqpp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygssp5yg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3qdpgg9kk7atwwss8yet8wfjhxumfdahzqenf0p682un9xq8zals8squsq7wkez03nuelmm82tklqj6u0nvyxsjzsfp2jwd0a4cy77mq9zkmnvq8d6ukzrxc8slvpur8s3g8nclxy3pe76c03y5f4gta46kt3cp94fyn9",
        "micro": "lnbc1000000u1p4tzwuqpp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygssp5yg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3qdpgg9kk7atwwss8yet8wfjhxumfdahzqenf0p682un9xq8zals8sqxh0qgfz9yx0hjw8hds8jcs8sajuyrv0l9ht8geuhkgemtvcq7nmssgh45s4emdet73c6tlmp5rnlhhzqa0kcrlm4vtg0zdcj79fqhqqprnfl9x",
        "nano": "lnbc1000000000n1p4tzwuqpp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygssp5yg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3qdpgg9kk7atwwss8yet8wfjhxumfdahzqenf0p682un9xq8zals8sqn5v32fvnvvqslj5n3269hqs6y38an9fva5d7aqfanccsfve6ss6z57e2k4hkpsrtsq6lcw3am44k0ysdgun5w876akc2jw6mhtteunqpcz0xw7",
        "pico": "lnbc1000000000000p1p4tzwuqpp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygssp5yg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3qdpgg9kk7atwwss8yet8wfjhxumfdahzqenf0p682un9xq8zals8sqquxprt8kcjel33062ka2vwsg2wacy6p3h8rfunzazr49ct5jhkj36lfrztk7jcnkuu7xx5g6jur6sflprr2g65sew2d5kdycz6dtyvcpt78wxl",
        "zero": "lnbc01p4tzwuqpp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygssp5yg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3qdpgg9kk7atwwss8yet8wfjhxumfdahzqenf0p682un9xq8zals8sq77pl65dexhfzymvnxr4e3wn3tfzpsxnk8cgmpn9h5tnrdsljza7z5shnyhgy948fwjj5r6rqxd7dq4sh8l7fwll66q7ksfzwmu9qcfgqkjr8t0",
        "submsat": "lnbc1p1p4tzwuqpp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygssp5yg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3qdpgg9kk7atwwss8yet8wfjhxumfdahzqenf0p682un9xq8zals8sq7var2pvxj5jl4ayt23wcsjkt3xstq37glxvvcskfd5ygp4fnfzepusx67jm6cyytlklxjvsv4gdscjqjl2u7x4letccuvg3klnx62qqpwud0rh",
        "overflow": "lnbc184467440737095516151p4tzwuqpp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygssp5yg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3qdpgg9kk7atwwss8yet8wfjhxumfdahzqenf0p682un9xq8zals8sq47lha5gfgg6w8luhss2003kwe65ge3qeunrqnee9rz77raves2gzwwml475axpg4vzeantxtswk4d5mx2k5jq2gd0z6q3sttzrf40ccqn6wzgx",
        "intOverflow": "lnbc92233720368547759n1p4tzwuqpp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygssp5yg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3qdpgg9kk7atwwss8yet8wfjhxumfdahzqenf0p682un9xq8zals8sqr8sxh73a4zqpj6ur5q5y8g2e5yd78r3huqk982mzanejkpx82z3svmkm8u4uau7hexphkgps5umarlsjv2y8nyxg0r5c9l56m5fuq2qpp4lnxd",
        "amountless": "lnbc1p4tzwuqpp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygssp5yg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3qdpgg9kk7atwwss8yet8wfjhxumfdahzqenf0p682un9xq8zals8sqq3tx6cuj6nsqu43vk6p0a7cjrhzxmaxf55t63ppj7y0qt8ccnwa42uzlv4xqwxeqfdf6xlfea5mj7np8phmfu5z7dzq20s60r4046ssqfddems",
    ]
}

@MainActor
private final class BOLT11SourceProbe: ObservableObject {
    @Published var state: MeltSourceState = .awaitingInput
    var settled: XCTestExpectation?
}

private struct BOLT11SourceProbeView: View {
    @ObservedObject var probe: BOLT11SourceProbe
    let invoice: String

    var body: some View {
        BOLT11MeltQuoteSource(initialInvoice: invoice, state: $probe.state)
            .onChange(of: probe.state) { _, state in
                switch state {
                case .ready, .error, .insufficientBalance:
                    probe.settled?.fulfill()
                    probe.settled = nil
                default: break
                }
            }
    }
}
