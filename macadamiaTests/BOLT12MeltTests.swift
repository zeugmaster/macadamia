@testable import macadamia
import CashuSwift
import SwiftData
import SwiftUI
import XCTest

final class BOLT12MeltTests: XCTestCase {
    // Small BOLT12 TLV fixtures, encoded without the BOLT11 Bech32 checksum.
    private func offer(amount: UInt64? = nil, currency: String? = nil, expiry: UInt64? = nil,
                       quantity: UInt64? = nil) -> String {
        func integer(_ value: UInt64) -> [UInt8] {
            var bytes = withUnsafeBytes(of: value.bigEndian, Array.init)
            while bytes.first == 0 { bytes.removeFirst() }
            return bytes
        }
        var records: [(UInt8, [UInt8])] = []
        if let currency { records.append((6, Array(currency.utf8))) }
        if let amount { records.append((8, integer(amount))) }
        records.append((10, Array("Coffee".utf8)))
        if let expiry { records.append((14, integer(expiry))) }
        if let quantity { records.append((20, integer(quantity))) }
        records.append((22, [2] + Array(repeating: 0x11, count: 32)))
        let bytes = records.flatMap { [$0.0, UInt8($0.1.count)] + $0.1 }
        let alphabet = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
        var accumulator = 0, bits = 0
        var result = "lno1"
        for byte in bytes {
            accumulator = ((accumulator << 8) | Int(byte)) & 0xffff
            bits += 8
            while bits >= 5 {
                bits -= 5
                result.append(alphabet[(accumulator >> bits) & 31])
            }
        }
        if bits > 0 { result.append(alphabet[(accumulator << (5 - bits)) & 31]) }
        return result
    }

    @MainActor
    private func fixture(balance: Int = 128, inputFee: Int = 0, url: URL? = nil) throws -> (ModelContainer, Mint, Wallet) {
        let container = try ModelContainer(for: Wallet.self, Mint.self, Proof.self, Event.self,
                                           NostrKeypair.self, NostrMessage.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let wallet = Wallet(mnemonic: "test", seed: "test")
        let keyset = try JSONDecoder().decode(CashuSwift.Keyset.self, from: Data(#"{"id":"009a1f293253e41e","unit":"sat","active":true,"keys":{},"derivationCounter":0}"#.utf8))
        let mint = Mint(url: url ?? URL(string: "https://unused.invalid")!, keysets: [keyset])
        mint.wallet = wallet
        container.mainContext.insert(wallet)
        container.mainContext.insert(mint)
        if balance > 0 {
            container.mainContext.insert(Proof(keysetID: keyset.keysetID, C: "02" + String(repeating: "11", count: 32),
                                                secret: UUID().uuidString, unit: .sat, inputFeePPK: inputFee,
                                                state: .valid, amount: balance, mint: mint, wallet: wallet))
        }
        try container.mainContext.save()
        return (container, mint, wallet)
    }

    private func quote(id: String = "quote", amount: Int = 100, fee: Int = 1, unit: String = "sat",
                       state: CashuSwift.QuoteState? = .unpaid, expiry: Int? = nil,
                       request: String? = nil) -> CashuSwift.Bolt12.MeltQuote {
        .init(quote: id, request: request, amount: amount, unit: unit, feeReserve: fee, state: state,
              expiry: expiry, paymentPreimage: state == .paid ? "preimage" : nil)
    }

    func testFixedAndAmountlessRequestEncodingAndRounding() throws {
        let fixed = try BOLT12OfferInput(offer(amount: 100_001))
        XCTAssertEqual(try fixed.paymentAmountSat(enteredSats: 999), 101)
        XCTAssertEqual(try fixed.paymentAmountMsat(enteredSats: 999), 100_001)
        let fixedJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(fixed.quoteRequest(enteredSats: 0))) as? [String: Any])
        XCTAssertNil(fixedJSON["options"])
        XCTAssertEqual(fixedJSON["request"] as? String, fixed.request)
        XCTAssertEqual(fixedJSON["unit"] as? String, "sat")

        let amountless = try BOLT12OfferInput(offer())
        let request = try amountless.quoteRequest(enteredSats: 123)
        XCTAssertEqual(request.options?.amountless?.amountMsat, 123_000)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        let options = try XCTUnwrap(json["options"] as? [String: Any])
        XCTAssertEqual(Set(options.keys), ["amountless"])
        XCTAssertEqual((options["amountless"] as? [String: Int])?["amount_msat"], 123_000)
        for value in [0, -1, Int.max] { XCTAssertThrowsError(try amountless.quoteRequest(enteredSats: value)) }
        XCTAssertNoThrow(try amountless.paymentAmountMsat(enteredSats: Int.max / 1_000))
        XCTAssertThrowsError(try BOLT12OfferInput(offer(amount: UInt64.max)))
        XCTAssertThrowsError(try BOLT12OfferInput(offer(amount: 0)))
    }

    func testInputRoutesOffersAndPreservesExistingURIPriority() throws {
        let payload = offer()
        let split = payload.index(payload.startIndex, offsetBy: 20)
        let continued = String(payload[..<split]) + "+\n " + String(payload[split...])
        let types: [InputView.InputType] = [.bolt12Offer, .bolt11Invoice, .creq]
        for input in [payload, payload.uppercased(), "lightning:" + payload, " \nLIGHTNING://" + payload + " \n",
                      continued, "bitcoin:?lno=" + payload] {
            guard case .valid(let result) = InputValidator.validate(input, supportedTypes: types) else {
                return XCTFail("Expected valid offer: \(input)")
            }
            XCTAssertEqual(result.type, .bolt12Offer)
            XCTAssertEqual(result.payload, payload)
        }
        for (query, expected): (String, InputView.InputType) in [
            ("creq=creq123&lightning=lnbc123", .creq), ("lightning=lnbc123", .bolt11Invoice)
        ] {
            guard case .valid(let result) = BIP321.resolve("bitcoin:?\(query)&lno=\(payload)", supportedTypes: types) else {
                return XCTFail("Expected existing priority")
            }
            XCTAssertEqual(result.type, expected)
        }
        if case .valid = BIP321.resolve("bitcoin:?lno=\(payload)", supportedTypes: [.bolt11Invoice]) {
            XCTFail("Must respect supported input types")
        }
    }

    func testInvalidExpiredAndUnsupportedOffersAreRejected() throws {
        for input in ["lno1invalid", offer(expiry: 1), offer(currency: "USD"), offer(quantity: 2), offer() + "+"] {
            XCTAssertThrowsError(try BOLT12OfferInput(input))
            if case .valid = InputValidator.validate(input, supportedTypes: [.bolt12Offer]) {
                XCTFail("Invalid offer was accepted")
            }
        }
        let future = UInt64(Date().timeIntervalSince1970) + 100
        let input = try BOLT12OfferInput(offer(expiry: future))
        XCTAssertThrowsError(try input.validateExpiry(now: Date(timeIntervalSince1970: TimeInterval(future))))
    }

    func testBOLT12CannotBeSplitAndQuoteTotalsCannotOverflow() throws {
        let bolt12 = LightningMeltQuote.bolt12(quote())
        let bolt11 = LightningMeltQuote.bolt11(.init(quote: "b11", amount: 100, unit: "sat",
                                                    feeReserve: 1, state: .unpaid, expiry: nil))
        XCTAssertNoThrow(try LightningMeltQuote.validatePayment([bolt12]))
        XCTAssertNoThrow(try LightningMeltQuote.validatePayment([bolt11, bolt11]))
        XCTAssertThrowsError(try LightningMeltQuote.validatePayment([bolt12, bolt12]))
        XCTAssertThrowsError(try LightningMeltQuote.validatePayment([bolt11, bolt12]))
        XCTAssertThrowsError(try LightningMeltQuote.validatePayment([]))
        XCTAssertThrowsError(try LightningMeltQuote.validatePayment([.bolt12(quote(amount: Int.max, fee: 1))]))
        XCTAssertThrowsError(try LightningMeltQuote.validatePayment([.bolt12(quote(fee: -1))]))
        XCTAssertThrowsError(try LightningMeltQuote.validatePayment([.bolt12(quote(expiry: 1))]))
    }

    @MainActor
    func testLoaderPublishesOneMintAndChecksFeeCoverage() async throws {
        let input = try BOLT12OfferInput(offer())
        for (balance, inputFee, expectedReady) in [(128, 0, true), (100, 0, false), (101, 1000, false)] {
            let (container, mint, _) = try fixture(balance: balance, inputFee: inputFee)
            let loader = BOLT12QuoteLoader()
            let response = quote()
            await loader.load(offer: input, amount: 100, mint: mint,
                              option: .init(mintID: mint.mintID, direction: .withdraw, unit: .sat, method: .bolt12)) { request, _ in
                XCTAssertEqual(request.options?.amountless?.amountMsat, 100_000)
                return response
            }
            if expectedReady {
                guard case .ready(let bundles, let fee) = loader.state else { return XCTFail("Expected payable quote") }
                XCTAssertEqual(bundles.count, 1)
                XCTAssertEqual(bundles.first?.quote.method, .bolt12)
                XCTAssertEqual(bundles.first?.quote.request, input.request)
                XCTAssertEqual(fee, 1)
            } else {
                XCTAssertEqual(loader.state, .insufficientBalance)
            }
            XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<Proof>()).first?.state, .valid)
        }
    }

    @MainActor
    func testUnsupportedMintsAndAmountsNeverRequestAQuote() async throws {
        let (container, mint, _) = try fixture(balance: 99)
        let input = try BOLT12OfferInput(offer())
        let loader = BOLT12QuoteLoader()
        let response = quote()
        for option in [
            PaymentOption(mintID: mint.mintID, direction: .withdraw, unit: .sat, method: .bolt11),
            PaymentOption(mintID: mint.mintID, direction: .deposit, unit: .sat, method: .bolt12),
            PaymentOption(mintID: mint.mintID, direction: .withdraw, unit: .usd, method: .bolt12),
            PaymentOption(mintID: mint.mintID, direction: .withdraw, unit: .sat, method: .bolt12, minAmount: 101),
            PaymentOption(mintID: mint.mintID, direction: .withdraw, unit: .sat, method: .bolt12, maxAmount: 99),
            PaymentOption(mintID: mint.mintID, direction: .withdraw, unit: .sat, method: .bolt12)
        ] {
            await loader.load(offer: input, amount: 100, mint: mint, option: option) { _, _ in
                XCTFail("Must validate capability, limits and balance before contacting mint")
                return response
            }
            if case .ready = loader.state { XCTFail("Invalid selection became payable") }
        }
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<Proof>()).count, 1)
    }

    @MainActor
    func testMalformedOrExpiredQuoteCannotEnablePayment() async throws {
        let (container, mint, _) = try fixture()
        let input = try BOLT12OfferInput(offer())
        for response in [quote(amount: 99), quote(unit: "usd"), quote(fee: -1), quote(expiry: 1),
                         quote(state: .pending), quote(request: offer(amount: 200_000)), quote(fee: Int.max)] {
            let loader = BOLT12QuoteLoader()
            await loader.load(offer: input, amount: 100, mint: mint,
                              option: .init(mintID: mint.mintID, direction: .withdraw, unit: .sat, method: .bolt12)) { _, _ in response }
            guard case .error = loader.state else { return XCTFail("Invalid quote became payable") }
        }
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<Event>()).count, 0)
    }

    @MainActor
    func testLateQuoteCannotOverwriteNewAmountOrReset() async throws {
        let (container, mint, _) = try fixture()
        let input = try BOLT12OfferInput(offer())
        let option = PaymentOption(mintID: mint.mintID, direction: .withdraw, unit: .sat, method: .bolt12)
        for resetOnly in [false, true] {
            let loader = BOLT12QuoteLoader()
            let started = expectation(description: "First request is in flight")
            let delayed = DelayedQuote()
            let oldTask = Task { @MainActor in
                await loader.load(offer: input, amount: 100, mint: mint, option: option) { _, _ in
                    await delayed.wait(started: started)
                }
            }
            await fulfillment(of: [started], timeout: 2)
            if resetOnly { loader.reset() }
            else {
                let response = quote(id: "new", amount: 110)
                await loader.load(offer: input, amount: 110, mint: mint, option: option) { _, _ in response }
            }
            await delayed.finish(quote(id: "old"))
            await oldTask.value
            if resetOnly { XCTAssertEqual(loader.state, .awaitingInput) }
            else {
                guard case .ready(let bundles, _) = loader.state else { return XCTFail("Expected current quote") }
                XCTAssertEqual(bundles.first?.quote.quote, "new")
                XCTAssertEqual(bundles.first?.quote.amount, 110)
            }
        }
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<Event>()).count, 0)
    }

    @MainActor
    func testBOLT12PendingAndPaidQuotesSurvivePersistenceWithoutBecomingBOLT11() throws {
        let (container, mint, wallet) = try fixture()
        let original = LightningMeltQuote.bolt12(quote(request: offer()))
        let event = Event(date: Date(), unit: .sat, shortDescription: "Payment", visible: true,
                          kind: .pendingMelt, wallet: wallet, amount: 100, mints: [mint])
        event.lightningMeltQuote = original
        container.mainContext.insert(event)
        try container.mainContext.save()
        let restored = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<Event>()).first)
        XCTAssertNil(restored.bolt11MeltQuote)
        XCTAssertEqual(restored.genericMeltQuote?.method, .bolt12)
        XCTAssertEqual(restored.lightningMeltQuote?.request, original.request)
        XCTAssertEqual(restored.lightningMeltQuote?.feeReserve, 1)

        let paid = LightningMeltQuote.bolt12(quote(state: .paid)).preservingRequest(from: original)
        event.lightningMeltQuote = paid
        try container.mainContext.save()
        let completed = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<Event>()).first?.lightningMeltQuote)
        XCTAssertEqual(completed.method, .bolt12)
        XCTAssertEqual(completed.request, original.request)
        XCTAssertEqual(completed.state, .paid)
        XCTAssertEqual(completed.paymentPreimage, "preimage")

        event.lightningMeltQuote = .bolt11(.init(quote: "legacy", request: "lnbc123", amount: 100,
                                                unit: "sat", feeReserve: 1, state: .unpaid, expiry: nil))
        try container.mainContext.save()
        let legacy = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<Event>()).first)
        XCTAssertEqual(legacy.bolt11MeltQuote?.request, "lnbc123")
        XCTAssertNil(legacy.genericMeltQuote)
    }

    @MainActor
    func testQuoteExecutionAndRecoveryUseTheCorrectEndpoints() async throws {
        for method: CashuSwift.PaymentMethodID in [.bolt11, .bolt12] {
            let response = quote(state: .paid)
            let stub = try MintHTTPStub { request in
                let path = try XCTUnwrap(request.url?.path)
                if request.httpMethod == "POST" {
                    let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
                    if path == "/v1/melt/quote/bolt12" {
                        let options = try XCTUnwrap(body["options"] as? [String: Any])
                        XCTAssertEqual((options["amountless"] as? [String: Int])?["amount_msat"], 100_000)
                        XCTAssertNil(options["mpp"])
                        return try JSONEncoder().encode(self.quote())
                    }
                    XCTAssertEqual(path, "/v1/melt/\(method.rawValue)")
                    XCTAssertEqual(body["quote"] as? String, "quote")
                    XCTAssertNotNil(body["inputs"])
                } else {
                    XCTAssertEqual(path, "/v1/melt/quote/\(method.rawValue)/quote")
                }
                return try JSONEncoder().encode(response)
            }
            defer { stub.remove() }
            let (container, mint, _) = try fixture(url: stub.url)
            let payment: LightningMeltQuote
            if method == .bolt12 {
                let input = try BOLT12OfferInput(offer())
                let loader = BOLT12QuoteLoader()
                await loader.load(offer: input, amount: 100, mint: mint,
                                  option: .init(mintID: mint.mintID, direction: .withdraw, unit: .sat, method: .bolt12))
                guard case .ready(let bundles, _) = loader.state, let quote = bundles.first?.quote else {
                    return XCTFail("Expected a real BOLT12 quote request to the HTTP stub")
                }
                payment = quote
            } else {
                payment = .bolt11(.init(quote: "quote", request: "lnbc123", amount: 100, unit: "sat",
                                        feeReserve: 1, state: .unpaid, expiry: nil))
            }
            let proofs = try container.mainContext.fetch(FetchDescriptor<Proof>()).sendable()
            let result = try await payment.melt(from: CashuSwift.Mint(mint), proofs: proofs, blankOutputs: nil)
            XCTAssertEqual(result.quote.method, method)
            XCTAssertEqual(result.quote.state, .paid)
            XCTAssertEqual(result.quote.request, payment.request)
            let recovered = try await payment.checkState(from: CashuSwift.Mint(mint), blankOutputs: nil)
            XCTAssertEqual(recovered.quote.method, method)
            XCTAssertEqual(recovered.quote.paymentPreimage, "preimage")
            XCTAssertEqual(recovered.quote.request, payment.request)
            XCTAssertEqual(stub.requests.count, method == .bolt12 ? 3 : 2)
        }
    }

    @MainActor
    func testRecoveryPreservesPendingAndUnpaidStatesAndRejectsWrongQuote() async throws {
        let payment = LightningMeltQuote.bolt12(quote(request: offer()))
        for state: CashuSwift.QuoteState in [.unpaid, .pending, .paid] {
            let response = quote(state: state)
            let stub = try MintHTTPStub { _ in try JSONEncoder().encode(response) }
            defer { stub.remove() }
            let result = try await payment.checkState(from: .init(url: stub.url, keysets: []), blankOutputs: nil)
            XCTAssertEqual(result.quote.state, state)
            XCTAssertEqual(result.quote.request, payment.request)
        }
        for response in [quote(id: "another-payment", state: .paid), quote(amount: 101, state: .paid),
                         quote(unit: "usd", state: .paid)] {
            let stub = try MintHTTPStub { _ in try JSONEncoder().encode(response) }
            defer { stub.remove() }
            do {
                _ = try await payment.checkState(from: .init(url: stub.url, keysets: []), blankOutputs: nil)
                XCTFail("Must not settle a different payment")
            } catch { }
        }
    }

    @MainActor
    func testFixedOfferViewReachesPaymentReview() async throws {
        let (container, mint, _) = try fixture()
        let info = try JSONDecoder().decode(CashuSwift.Mint.Info.self, from: Data(#"{"nuts":{"5":{"methods":[{"method":"bolt12","unit":"sat"}],"disabled":false}}}"#.utf8))
        try mint.setPreviewInfo(info)
        let ready = expectation(description: "View publishes a payable quote")
        let response = quote()
        let probe = MeltSourceProbe()
        let controller = UIHostingController(rootView: MeltSourceProbeView(probe: probe, offer: offer(amount: 100_000),
                                                                          fetch: { _, _ in response }, ready: ready)
            .modelContainer(container)
            .environmentObject(AppState(preview: true, preferredUnit: .usd)))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        await fulfillment(of: [ready], timeout: 5)
        guard case .ready(let bundles, _) = probe.state else { return XCTFail("View stayed in \(probe.state)") }
        XCTAssertEqual(bundles.count, 1)
        XCTAssertEqual(bundles.first?.quote.amount, 100)
    }
}

@MainActor
private final class MeltSourceProbe: ObservableObject {
    @Published var state: MeltSourceState = .awaitingInput
    @Published var confirmed = false
}

private struct MeltSourceProbeView: View {
    @ObservedObject var probe: MeltSourceProbe
    let offer: String
    let fetch: BOLT12QuoteLoader.FetchQuote
    let ready: XCTestExpectation

    var body: some View {
        BOLT12MeltQuoteSource(offer: offer, amountConfirmed: $probe.confirmed, state: $probe.state, fetchQuote: fetch)
            .onChange(of: probe.state) { _, state in
                if case .ready = state { ready.fulfill() }
            }
    }
}

private actor DelayedQuote {
    private var continuation: CheckedContinuation<CashuSwift.Bolt12.MeltQuote, Never>?

    func wait(started: XCTestExpectation) async -> CashuSwift.Bolt12.MeltQuote {
        await withCheckedContinuation {
            continuation = $0
            started.fulfill()
        }
    }

    func finish(_ quote: CashuSwift.Bolt12.MeltQuote) {
        continuation?.resume(returning: quote)
        continuation = nil
    }
}
