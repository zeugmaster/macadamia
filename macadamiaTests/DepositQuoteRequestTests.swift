@testable import macadamia
import CashuSwift
import SwiftData
import XCTest

final class DepositQuoteRequestTests: XCTestCase {
    private let seed = "aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899"

    @MainActor
    private func fixture(url: URL) throws -> (ModelContainer, Mint, Wallet) {
        let container = try ModelContainer(for: Wallet.self, Mint.self, Proof.self, Event.self,
                                           NostrKeypair.self, NostrMessage.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let wallet = Wallet(mnemonic: "test", seed: seed)
        let keyset = try JSONDecoder().decode(CashuSwift.Keyset.self, from: Data(#"{"id":"009a1f293253e41e","unit":"sat","active":true,"keys":{},"derivationCounter":0}"#.utf8))
        let mint = Mint(url: url, keysets: [keyset])
        mint.wallet = wallet
        container.mainContext.insert(wallet)
        container.mainContext.insert(mint)
        try container.mainContext.save()
        return (container, mint, wallet)
    }

    @MainActor
    func testRequestBodiesAndNavigationValuesForEveryMethod() async throws {
        for (method, amount): (CashuSwift.PaymentMethodID, Int?) in [
            (.bolt11, 123), (.bolt12, nil), (.bolt12, 123), ("onchain", nil), ("branch", 123)
        ] {
            let key = try CashuSwift.Generic.quoteLockingKey(seed: seed, counter: 0)
            let stub = try DepositHTTPStub { request in
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.url?.path, "/v1/mint/quote/\(method.rawValue)")
                let data = try XCTUnwrap(request.httpBody)
                let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                XCTAssertEqual(body["unit"] as? String, "sat")
                XCTAssertEqual(body["amount"] as? Int, amount)
                if amount == nil { XCTAssertNil(body["amount"], "Omit amount instead of sending zero or null") }
                XCTAssertEqual(body["pubkey"] as? String, method == .bolt11 ? nil : key.publicKey)
                var expectedKeys: Set<String> = ["unit"]
                if amount != nil { expectedKeys.insert("amount") }
                if method != .bolt11 { expectedKeys.insert("pubkey") }
                XCTAssertEqual(Set(body.keys), expectedKeys)
                var response = body
                response["quote"] = "test-quote"
                response["request"] = "test-payment-request"
                response["method"] = method.rawValue
                response["amount_paid"] = 0
                response["amount_issued"] = 0
                response["updated_at"] = 1_800_000_000
                return try JSONSerialization.data(withJSONObject: response)
            }
            defer { stub.remove() }
            let (container, mint, wallet) = try fixture(url: stub.url)
            let option = PaymentOption(mintID: mint.mintID, direction: .deposit, unit: .sat, method: method)
            let quote = try await DepositQuoteRequestView.loadQuote(from: mint, option: option, amount: amount,
                                                                     in: container.mainContext)
            XCTAssertEqual(quote.method, method)
            XCTAssertEqual(quote.paymentMethodKind, method.kind)
            XCTAssertEqual(quote.unit, .sat)
            XCTAssertEqual(quote.amount, amount)
            XCTAssertEqual(quote.request, "test-payment-request")
            XCTAssertEqual(quote.mint.mintID, mint.mintID)
            XCTAssertEqual(quote.lockingKeyCounter, method == .bolt11 ? nil : 0)
            XCTAssertEqual(wallet.mintQuoteCounter, method == .bolt11 ? nil : 1)
            XCTAssertEqual(stub.requests.count, 1)
            XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<Event>()).isEmpty)
        }
    }

    @MainActor
    func testRejectsMissingOrMismatchedLocksAndWrongUnitOrAmount() async throws {
        for mutation in ["missing-key", "wrong-key", "wrong-unit", "wrong-amount"] {
            let stub = try DepositHTTPStub { request in
                let data = try XCTUnwrap(request.httpBody)
                var response = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
                response["quote"] = "test-quote"
                response["request"] = "payment-request"
                switch mutation {
                case "missing-key": response.removeValue(forKey: "pubkey")
                case "wrong-key": response["pubkey"] = String(repeating: "0", count: 66)
                case "wrong-unit": response["unit"] = "usd"
                default: response["amount"] = 124
                }
                return try JSONSerialization.data(withJSONObject: response)
            }
            defer { stub.remove() }
            let (container, mint, wallet) = try fixture(url: stub.url)
            let option = PaymentOption(mintID: mint.mintID, direction: .deposit, unit: .sat, method: "branch")
            do {
                _ = try await DepositQuoteRequestView.loadQuote(from: mint, option: option, amount: 123,
                                                                 in: container.mainContext)
                XCTFail("Accepted \(mutation)")
            } catch let error as CashuError {
                switch (mutation, error) {
                case ("missing-key", .invalidKey), ("wrong-key", .invalidKey),
                     ("wrong-unit", .inputError), ("wrong-amount", .inputError): break
                default: XCTFail("Unexpected error: \(error)")
                }
            }
            XCTAssertEqual(wallet.mintQuoteCounter, 1, "Failed requests must not reuse the key")
            XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<Event>()).isEmpty)
        }
    }

    @MainActor
    func testAmountRequirementsAndMintLimits() throws {
        for method: CashuSwift.PaymentMethodID in [.bolt11, .bolt12, "onchain", "branch"] {
            let option = PaymentOption(mintID: UUID(), direction: .deposit, unit: .sat, method: method,
                                       minAmount: 100, maxAmount: 200)
            if method.kind == .bolt12 || method.kind == .onchain {
                XCTAssertNoThrow(try DepositQuoteRequestView.validateAmount(nil, for: option))
            } else {
                XCTAssertThrowsError(try DepositQuoteRequestView.validateAmount(nil, for: option))
            }
            for invalid in [-1, 0, 99, 201] {
                XCTAssertThrowsError(try DepositQuoteRequestView.validateAmount(invalid, for: option))
            }
            for valid in [100, 200] {
                if method.kind == .onchain {
                    XCTAssertThrowsError(try DepositQuoteRequestView.validateAmount(valid, for: option))
                } else {
                    XCTAssertNoThrow(try DepositQuoteRequestView.validateAmount(valid, for: option))
                }
            }
        }
    }

    @MainActor
    func testCounterIsSavedAndNeverWraps() throws {
        let (container, _, wallet) = try fixture(url: XCTUnwrap(URL(string: "https://unused.invalid")))
        XCTAssertNil(wallet.mintQuoteCounter)
        XCTAssertEqual(try DepositQuoteRequestView.reserveQuoteCounter(for: wallet, in: container.mainContext), 0)
        let anotherContext = ModelContext(container)
        let restored = try XCTUnwrap(try anotherContext.fetch(FetchDescriptor<Wallet>()).first)
        XCTAssertEqual(restored.mintQuoteCounter, 1)
        XCTAssertEqual(try DepositQuoteRequestView.reserveQuoteCounter(for: restored, in: anotherContext), 1)
        restored.mintQuoteCounter = 0x7fffffff
        XCTAssertEqual(try DepositQuoteRequestView.reserveQuoteCounter(for: restored, in: anotherContext), 0x7fffffff)
        XCTAssertThrowsError(try DepositQuoteRequestView.reserveQuoteCounter(for: restored, in: anotherContext))
        XCTAssertEqual(restored.mintQuoteCounter, 0x80000000)
    }

    func testAmountlessAndPartiallyIssuedQuotesUseUnissuedBalance() throws {
        for method: CashuSwift.PaymentMethodID in [.bolt12, "onchain", "branch"] {
            for requestedAmount: Int? in [nil, 100] {
                let response = accountingQuote(method: method, amount: requestedAmount, paid: 250, issued: 100)
                XCTAssertEqual(try DepositQuoteView.amountToIssue(for: response, requestedAmount: requestedAmount), 150)
            }
            for (paid, issued) in [(0, 0), (100, 100)] {
                let response = accountingQuote(method: method, paid: paid, issued: issued)
                XCTAssertNil(try DepositQuoteView.amountToIssue(for: response, requestedAmount: nil))
            }
        }
    }

    func testInvalidAccountingAndTerminalStatesCannotIssue() throws {
        for (paid, issued) in [(-1, 0), (1, -1), (100, 101)] {
            let response = accountingQuote(paid: paid, issued: issued)
            XCTAssertThrowsError(try DepositQuoteView.amountToIssue(for: response, requestedAmount: nil)) {
                XCTAssertEqual($0 as? CashuError, .invalidQuoteAccounting)
            }
        }
        for state in ["ISSUED", "EXPIRED", "FAILED"] {
            let response = accountingQuote(paid: 100, issued: 0, state: state)
            XCTAssertThrowsError(try DepositQuoteView.amountToIssue(for: response, requestedAmount: nil))
        }
    }

    func testBolt11PaidnessAndExpiry() throws {
        func response(_ state: CashuSwift.QuoteState, expiry: Int? = nil) -> CashuSwift.Bolt11.MintQuote {
            .init(quote: "quote", request: "invoice", amount: 100, unit: "sat", state: state, expiry: expiry)
        }
        XCTAssertNil(try DepositQuoteView.amountToIssue(for: response(.unpaid), requestedAmount: 100))
        XCTAssertNil(try DepositQuoteView.amountToIssue(for: response(.pending, expiry: 1), requestedAmount: 100))
        XCTAssertEqual(try DepositQuoteView.amountToIssue(for: response(.paid, expiry: 1), requestedAmount: 100), 100)
        XCTAssertThrowsError(try DepositQuoteView.amountToIssue(for: response(.unpaid, expiry: 1), requestedAmount: 100)) {
            XCTAssertEqual($0 as? CashuError, .quoteIsExpired)
        }
        XCTAssertThrowsError(try DepositQuoteView.amountToIssue(for: response(.issued), requestedAmount: 100)) {
            XCTAssertEqual($0 as? CashuError, .proofsAlreadyIssuedForQuote)
        }
        let stateOnly = CashuSwift.Generic.MintQuote(method: "branch", quote: "quote", request: "request",
                                                    unit: "sat", amount: nil, state: nil, expiry: nil,
                                                    raw: ["state": .string("paid")])
        XCTAssertEqual(try DepositQuoteView.amountToIssue(for: stateOnly, requestedAmount: 100), 100)
        XCTAssertThrowsError(try DepositQuoteView.amountToIssue(for: stateOnly, requestedAmount: nil))
    }

    @MainActor
    func testIssuancePersistsProofsCountersAndEventsForEveryMethod() async throws {
        for (method, requestedAmount): (CashuSwift.PaymentMethodID, Int?) in [
            (.bolt11, 3), (.bolt12, nil), (.bolt12, 3), ("onchain", nil), ("branch", 3)
        ] {
            let key = try CashuSwift.Generic.quoteLockingKey(seed: seed, counter: 7)
            let stub = try DepositHTTPStub { request in
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.url?.path, "/v1/mint/\(method.rawValue)")
                let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
                XCTAssertEqual(body["quote"] as? String, "test-quote")
                XCTAssertNil(body[CashuSwift.Generic.MintQuote.nut20CounterKey])
                if method == .bolt11 {
                    XCTAssertNil(body["signature"])
                } else {
                    XCTAssertEqual((body["signature"] as? String)?.count, 128)
                }
                let outputs = try XCTUnwrap(body["outputs"] as? [[String: Any]])
                XCTAssertEqual(outputs.compactMap { $0["amount"] as? Int }.reduce(0, +), 3)
                // Test mint uses private key 1, so signing preserves each blinded point.
                let signatures = try outputs.map { output in
                    ["id": try XCTUnwrap(output["id"]), "amount": try XCTUnwrap(output["amount"]),
                     "C_": try XCTUnwrap(output["B_"])]
                }
                return try JSONSerialization.data(withJSONObject: ["signatures": signatures])
            }
            defer { stub.remove() }
            let (container, mint, wallet) = try fixture(url: stub.url)
            let generator = "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
            mint.keysets[0].keys = ["1": generator, "2": generator]

            let response: any CashuSwift.MintQuoteResponse
            if method == .bolt11 {
                response = CashuSwift.Bolt11.MintQuote(quote: "test-quote", request: "invoice", amount: 3,
                                                      unit: "sat", state: .unpaid, expiry: nil)
            } else {
                response = accountingQuote(method: method, amount: requestedAmount, paid: 0, issued: 0,
                                           pubkey: key.publicKey)
            }
            let quote = DepositQuote(response: response, mint: mint,
                                     option: .init(mintID: mint.mintID, direction: .deposit, unit: .sat, method: method),
                                     requestedAmount: requestedAmount, lockingKeyCounter: method == .bolt11 ? nil : 7)
            try await DepositQuoteView.issueEcash(for: quote, amount: 3, in: container.mainContext)

            let restored = ModelContext(container)
            let proofs = try restored.fetch(FetchDescriptor<Proof>())
            XCTAssertEqual(proofs.reduce(0) { $0 + $1.amount }, 3)
            XCTAssertEqual(proofs.count, 2)
            XCTAssertTrue(proofs.allSatisfy { $0.wallet?.id == wallet.id && $0.state == .valid })
            let savedMint = try XCTUnwrap(try restored.fetch(FetchDescriptor<Mint>()).first)
            XCTAssertEqual(savedMint.keysets[0].derivationCounter, 2)
            let events = try restored.fetch(FetchDescriptor<Event>())
            XCTAssertEqual(events.count, 1)
            let event = try XCTUnwrap(events.first)
            XCTAssertEqual(event.kind, .mint)
            XCTAssertEqual(event.amount, 3)
            if method == .bolt11 {
                XCTAssertEqual(event.mintQuote?.quote, quote.quoteID)
            } else {
                XCTAssertEqual(event.genericMintQuote?.method, method)
                XCTAssertEqual(event.genericMintQuote?.nut20Counter, 7)
                XCTAssertEqual(event.genericMintQuote?.lockingPubkey, key.publicKey)
            }
            XCTAssertEqual(stub.requests.count, 1)
        }
    }

    @MainActor
    func testIssuanceRejectsMissingCounterOrWrongSigningKeyBeforeNetworking() async throws {
        let stub = try DepositHTTPStub { _ in
            XCTFail("Invalid quote authorization must not reach the mint")
            return Data()
        }
        defer { stub.remove() }
        let (container, mint, _) = try fixture(url: stub.url)
        let key = try CashuSwift.Generic.quoteLockingKey(seed: seed, counter: 7)
        let response = accountingQuote(paid: 3, issued: 0, pubkey: key.publicKey)
        for counter: UInt32? in [nil, 8] {
            let quote = DepositQuote(response: response, mint: mint,
                                     option: .init(mintID: mint.mintID, direction: .deposit, unit: .sat, method: .bolt12),
                                     requestedAmount: nil, lockingKeyCounter: counter)
            do {
                try await DepositQuoteView.issueEcash(for: quote, amount: 3, in: container.mainContext)
                XCTFail("Accepted invalid quote authorization")
            } catch let error as CashuError {
                switch error {
                case .inputError, .invalidKey: break
                default: XCTFail("Unexpected error: \(error)")
                }
            }
        }
        XCTAssertTrue(stub.requests.isEmpty)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<Proof>()).isEmpty)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<Event>()).isEmpty)
        XCTAssertEqual(mint.keysets[0].derivationCounter, 0)
    }

    private func accountingQuote(method: CashuSwift.PaymentMethodID = .bolt12, amount: Int? = nil,
                                  paid: Int, issued: Int, state: String? = nil,
                                  pubkey: String? = nil) -> CashuSwift.Generic.MintQuote {
        var raw: CashuSwift.JSONObject = [
            "quote": .string("test-quote"), "request": .string("request"), "unit": .string("sat"),
            "method": .string(method.rawValue), "amount_paid": .integer(Int64(paid)),
            "amount_issued": .integer(Int64(issued))
        ]
        if let amount { raw["amount"] = .integer(Int64(amount)) }
        if let state { raw["state"] = .string(state) }
        if let pubkey { raw["pubkey"] = .string(pubkey) }
        return .init(method: method, quote: "test-quote", request: "request", unit: "sat", amount: amount,
                     state: nil, expiry: nil, raw: raw)
    }
}

private final class DepositHTTPStub: @unchecked Sendable {
    private final class Registry: @unchecked Sendable {
        let lock = NSLock()
        var stubs: [String: DepositHTTPStub] = [:]
        let registered = URLProtocol.registerClass(DepositURLProtocol.self)
    }
    private static let registry = Registry()
    let url: URL
    private let host: String
    private let lock = NSLock()
    private var captured: [URLRequest] = []
    private let handler: (URLRequest) throws -> Data

    init(handler: @escaping (URLRequest) throws -> Data) throws {
        host = UUID().uuidString.lowercased() + ".deposit-tests.invalid"
        url = try XCTUnwrap(URL(string: "https://" + host))
        self.handler = handler
        Self.registry.lock.lock()
        defer { Self.registry.lock.unlock() }
        Self.registry.stubs[host] = self
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return captured
    }

    func remove() {
        Self.registry.lock.lock()
        defer { Self.registry.lock.unlock() }
        Self.registry.stubs.removeValue(forKey: host)
    }

    static func response(to request: URLRequest) throws -> Data {
        registry.lock.lock()
        let stub = registry.stubs[request.url?.host ?? ""]
        registry.lock.unlock()
        let fixture = try XCTUnwrap(stub)
        fixture.lock.lock()
        fixture.captured.append(request)
        fixture.lock.unlock()
        return try fixture.handler(request)
    }
}

private final class DepositURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host?.hasSuffix(".deposit-tests.invalid") == true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            var captured = request
            if captured.httpBody == nil, let stream = captured.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var bytes = [UInt8](repeating: 0, count: 4096)
                var data = Data()
                while true {
                    let count = stream.read(&bytes, maxLength: bytes.count)
                    if count == 0 { break }
                    guard count > 0 else { throw stream.streamError ?? URLError(.cannotDecodeRawData) }
                    data.append(contentsOf: bytes.prefix(count))
                }
                captured.httpBody = data
            }
            let data = try DepositHTTPStub.response(to: captured)
            let url = try XCTUnwrap(request.url)
            let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                                       headerFields: ["Content-Type": "application/json"]))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
