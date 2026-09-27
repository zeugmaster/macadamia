import Foundation
import Combine
import Bolt11
import CashuSwift

enum BOLT11PaymentError: LocalizedError, Equatable {
    case missingAmount
    case fractionalMPP
    case unsupportedMPP
    case insufficientBalance
    case amountMismatch(expected: Int, received: Int)

    var errorDescription: String? {
        switch self {
        case .missingAmount:
            String(localized: "Use a BOLT11 invoice with an amount.")
        case .fractionalMPP:
            String(localized: "This invoice includes a fraction of a satoshi. Pay it from one mint with enough balance, or request a whole-satoshi invoice to split the payment.")
        case .unsupportedMPP:
            String(localized: "The selected mints must support partial payments.")
        case .insufficientBalance:
            String(localized: "Insufficient balance (including fees)")
        case .amountMismatch(let expected, let received):
            String(localized: "Quote amount mismatch: expected \(expected) sats, received \(received) sats.")
        }
    }
}

/// The Lightning amount remains exact; only its cost in sat-denominated ecash is rounded.
struct BOLT11InvoiceInput: Equatable, Sendable {
    let request: String
    let amountMsat: Int
    let expiry: UInt64

    var amountSat: Int { amountMsat / 1_000 + (amountMsat % 1_000 == 0 ? 0 : 1) }
    var supportsWholeSatMPP: Bool { amountMsat % 1_000 == 0 }

    init(_ request: String, now: Date = Date()) throws {
        let invoice = try Bolt11Decoder.decode(request)
        guard let amount = invoice.amount else { throw BOLT11PaymentError.missingAmount }
        // Avoid both the CashuSwift helper's truncation and the decoder's unchecked
        // UInt64 multiplication when converting very large invoice amounts.
        let factor: UInt64
        switch amount.multiplier {
        case nil: factor = 100_000_000_000
        case .milli: factor = 100_000_000
        case .micro: factor = 100_000
        case .nano: factor = 100
        case .pico: factor = 1
        }
        if amount.multiplier == .pico, amount.value % 10 != 0 { throw CashuError.invalidAmount }
        let value = amount.multiplier == .pico ? amount.value / 10 : amount.value
        let (msat, overflow) = value.multipliedReportingOverflow(by: factor)
        guard !overflow, let amountMsat = Int(exactly: msat), amountMsat > 0 else {
            throw CashuError.invalidAmount
        }
        let (expiry, expiryOverflow) = invoice.timestamp.addingReportingOverflow(invoice.expiryTime)
        guard !expiryOverflow else { throw CashuError.invalidAmount }
        self.request = request
        self.amountMsat = amountMsat
        self.expiry = expiry
        try validateExpiry(now: now)
    }

    func validateExpiry(now: Date = Date()) throws {
        guard TimeInterval(expiry) > now.timeIntervalSince1970 else { throw CashuError.quoteIsExpired }
    }
}

struct BOLT11PaymentPlan: Equatable, Sendable {
    struct Candidate: Equatable, Sendable {
        let mintID: UUID
        let balanceSat: Int
        let supportsMPP: Bool

        @MainActor init(_ mint: Mint) {
            self.init(mintID: mint.mintID, balanceSat: mint.balance(for: .sat), supportsMPP: mint.supportsMPP)
        }

        init(mintID: UUID, balanceSat: Int, supportsMPP: Bool) {
            self.mintID = mintID
            self.balanceSat = balanceSat
            self.supportsMPP = supportsMPP
        }
    }

    struct Leg: Equatable, Sendable {
        let mintID: UUID
        let amountMsat: Int
        let amountSat: Int
    }

    let input: BOLT11InvoiceInput
    let legs: [Leg]
    var isMPP: Bool { legs.count > 1 }

    /// Preserve the user's mint ordering; use the largest balances only when splitting.
    static func automaticSelection(input: BOLT11InvoiceInput, candidates: [Candidate]) throws -> [Candidate] {
        guard candidates.allSatisfy({ $0.balanceSat >= 0 }) else { throw CashuError.invalidAmount }
        if let single = candidates.first(where: { $0.balanceSat >= input.amountSat }) { return [single] }
        guard input.supportsWholeSatMPP else { throw BOLT11PaymentError.fractionalMPP }
        let ranked = candidates.enumerated().filter { $0.element.supportsMPP && $0.element.balanceSat > 0 }
            .sorted { lhs, rhs in
                lhs.element.balanceSat == rhs.element.balanceSat
                    ? lhs.offset < rhs.offset : lhs.element.balanceSat > rhs.element.balanceSat
            }
        var remaining = input.amountSat
        var chosen: [Candidate] = []
        for (_, mint) in ranked where remaining > 0 {
            chosen.append(mint)
            remaining -= min(remaining, mint.balanceSat)
        }
        guard remaining == 0 else { throw BOLT11PaymentError.insufficientBalance }
        return chosen
    }

    init(input: BOLT11InvoiceInput, candidates: [Candidate]) throws {
        guard !candidates.isEmpty,
              Set(candidates.map(\.mintID)).count == candidates.count,
              candidates.allSatisfy({ $0.balanceSat >= 0 }) else { throw CashuError.invalidAmount }
        self.input = input
        let funded = candidates.filter { $0.balanceSat > 0 }
        guard !funded.isEmpty else { throw BOLT11PaymentError.insufficientBalance }
        if funded.count == 1, let mint = funded.first {
            guard mint.balanceSat >= input.amountSat else { throw BOLT11PaymentError.insufficientBalance }
            legs = [.init(mintID: mint.mintID, amountMsat: input.amountMsat, amountSat: input.amountSat)]
            return
        }
        guard input.supportsWholeSatMPP else { throw BOLT11PaymentError.fractionalMPP }
        let totalBalance = try funded.reduce(0) { try Self.add($0, $1.balanceSat) }
        guard totalBalance >= input.amountSat else { throw BOLT11PaymentError.insufficientBalance }

        // Exact largest-remainder allocation in sats. Full-width arithmetic avoids
        // overflowing balance * invoice amount, even when both fit individually.
        var shares: [(mint: Candidate, sats: Int, remainder: UInt64)] = funded.map { mint in
            let product = UInt64(input.amountSat).multipliedFullWidth(by: UInt64(mint.balanceSat))
            let division = UInt64(totalBalance).dividingFullWidth(product)
            return (mint, Int(division.quotient), division.remainder)
        }
        let assigned = try shares.reduce(0) { try Self.add($0, $1.sats) }
        let ranking = shares.indices.sorted { lhs, rhs in
            if shares[lhs].remainder != shares[rhs].remainder { return shares[lhs].remainder > shares[rhs].remainder }
            if shares[lhs].mint.balanceSat != shares[rhs].mint.balanceSat { return shares[lhs].mint.balanceSat > shares[rhs].mint.balanceSat }
            return lhs < rhs
        }
        for index in ranking.prefix(input.amountSat - assigned) { shares[index].sats += 1 }
        let active = shares.filter { $0.sats > 0 }
        guard active.count == 1 || active.allSatisfy({ $0.mint.supportsMPP }) else {
            throw BOLT11PaymentError.unsupportedMPP
        }
        legs = try active.map { share in
            let (msat, overflow) = share.sats.multipliedReportingOverflow(by: 1_000)
            guard !overflow, share.sats <= share.mint.balanceSat else { throw CashuError.invalidAmount }
            return Leg(mintID: share.mint.mintID, amountMsat: msat, amountSat: share.sats)
        }
        guard try legs.reduce(0, { try Self.add($0, $1.amountMsat) }) == input.amountMsat else {
            throw CashuError.invalidAmount
        }
    }

    static func add(_ lhs: Int, _ rhs: Int) throws -> Int {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        guard lhs >= 0, rhs >= 0, !overflow else { throw CashuError.invalidAmount }
        return sum
    }

    func request(for leg: Leg) -> CashuSwift.Generic.MeltQuoteRequest {
        .init(method: .bolt11, unit: "sat", request: input.request,
              extra: isMPP ? ["options": .object(["mpp": .object(["amount": .integer(Int64(leg.amountMsat))])])] : nil)
    }

    func validate(_ response: CashuSwift.Bolt11.MeltQuote, for leg: Leg, now: Date = Date()) throws -> CashuSwift.Bolt11.MeltQuote {
        try input.validateExpiry(now: now)
        guard response.amount == leg.amountSat else {
            throw BOLT11PaymentError.amountMismatch(expected: leg.amountSat, received: response.amount)
        }
        guard !response.quote.isEmpty, response.unit == "sat",
              response.state == nil || response.state == .unpaid else {
            throw CashuError.inputError(String(localized: "The mint's quote does not match this payment."))
        }
        // These fields may be omitted by older mints. Check any echo before
        // restoring the original invoice to the persisted BOLT11 quote.
        if let request = response.request, request.lowercased() != input.request.lowercased() {
            throw CashuError.inputError(String(localized: "The mint's quote does not match this payment."))
        }
        let quote = CashuSwift.Bolt11.MeltQuote(quote: response.quote, request: input.request,
                                               amount: response.amount, unit: response.unit, feeReserve: response.feeReserve,
                                               state: response.state, expiry: response.expiry,
                                               paymentPreimage: response.paymentPreimage, change: response.change)
        try LightningMeltQuote.validatePayment([.bolt11(quote)], now: now)
        return quote
    }
}

/// A response can publish only while its complete invoice/selection plan is current.
@MainActor
final class BOLT11QuoteLoader: ObservableObject {
    enum Entry {
        case quote(CashuSwift.Bolt11.MeltQuote)
        case error(String)
    }

    @Published private(set) var state: MeltSourceState = .awaitingInput
    @Published private(set) var plan: BOLT11PaymentPlan?
    @Published private(set) var entries: [UUID: Entry] = [:]
    private var generation = UUID()

    typealias FetchQuote = @Sendable (CashuSwift.Generic.MeltQuoteRequest, CashuSwift.Mint) async throws -> CashuSwift.Bolt11.MeltQuote
    nonisolated static let fetchFromMint: FetchQuote = { request, mint in
        if request.extra == nil {
            return try await CashuSwift.Bolt11.requestMeltQuote(.init(unit: request.unit, request: request.request, options: nil), from: mint)
        }
        // CashuSwift's typed request cannot encode MPP yet. Its generic response
        // decoder truncates fractional numbers and replaces the method echo, so
        // send the same request body and decode the original response directly.
        guard mint.keysets.contains(where: { $0.unit == request.unit }) else {
            throw CashuError.unitIsNotSupported(request.unit)
        }
        var httpRequest = URLRequest(url: mint.url.appending(path: "/v1/melt/quote/bolt11"), timeoutInterval: 10)
        httpRequest.httpMethod = "POST"
        httpRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        httpRequest.httpBody = try JSONEncoder().encode(request)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: httpRequest)
        } catch {
            throw CashuError.networkError
        }
        struct Metadata: Decodable {
            let method: String?
            let detail: String?
        }
        let decoder = JSONDecoder()
        let metadata = try decoder.decode(Metadata.self, from: data)
        if let detail = metadata.detail { throw CashuError.unknownError(detail) }
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              metadata.method == nil || metadata.method == "bolt11" else {
            throw CashuError.inputError(String(localized: "The mint's quote does not match this payment."))
        }
        return try decoder.decode(CashuSwift.Bolt11.MeltQuote.self, from: data)
    }

    func reset(state: MeltSourceState = .awaitingInput) {
        generation = UUID()
        plan = nil
        entries = [:]
        self.state = state
    }

    func load(input: BOLT11InvoiceInput, candidates: [BOLT11PaymentPlan.Candidate], automatic: Bool,
              mints: [Mint], fetch: FetchQuote = fetchFromMint) async {
        guard !Task.isCancelled else { return }
        reset(state: .loading)
        let currentGeneration = generation
        var results: [UUID: Entry] = [:]
        var currentMint: Mint?
        do {
            let selected = try automatic ? BOLT11PaymentPlan.automaticSelection(input: input, candidates: candidates) : candidates
            guard !selected.isEmpty else { state = .awaitingInput; return }
            let plan = try BOLT11PaymentPlan(input: input, candidates: selected)
            try input.validateExpiry()
            self.plan = plan
            var bundles: [MeltQuoteBundle] = []
            var totalFee = 0
            for leg in plan.legs {
                guard let mint = mints.first(where: { $0.mintID == leg.mintID }) else { throw CashuError.invalidAmount }
                currentMint = mint
                let response = try await fetch(plan.request(for: leg), CashuSwift.Mint(mint))
                guard generation == currentGeneration, !Task.isCancelled else { return }
                let quote = try plan.validate(response, for: leg)
                results[leg.mintID] = .quote(quote)
                totalFee = try BOLT11PaymentPlan.add(totalFee, quote.feeReserve)
                bundles.append(.init(mint: mint, quote: .bolt11(quote)))
            }
            // Recheck expiry and funding after all network waits, without reserving proofs.
            try input.validateExpiry()
            try LightningMeltQuote.validatePayment(bundles.map(\.quote))
            for bundle in bundles {
                let required = try bundle.quote.requiredInputAmount(inputFee: 0)
                guard bundle.mint.select(amount: required, unit: .sat) != nil else {
                    entries = results
                    state = .insufficientBalance
                    return
                }
            }
            entries = results
            state = .ready(bundles: bundles, totalFee: totalFee)
        } catch {
            guard generation == currentGeneration, !Task.isCancelled else { return }
            if let paymentError = error as? BOLT11PaymentError, paymentError == .insufficientBalance {
                state = .insufficientBalance
                return
            }
            let message: String
            switch error {
            case CashuError.networkError:
                message = String(localized: "Network error")
            case CashuError.unknownError(let detail) where detail.contains("internal mpp not allowed"):
                message = String(localized: "Self-pay not possible")
            default:
                message = error.localizedDescription
            }
            if let currentMint { results[currentMint.mintID] = .error(message) }
            entries = results
            state = .error(currentMint.map { "\($0.displayName): \(message)" } ?? message)
        }
    }
}
