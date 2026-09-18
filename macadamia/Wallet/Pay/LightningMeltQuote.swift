import Foundation
import CashuSwift

/// A `(Mint, MeltQuote)` pair that's been validated and is ready for execution.
///
/// Produced by a quote-source view and consumed by `MeltView` to run the
/// actual melt operation while preserving the payment method.
struct MeltQuoteBundle: Equatable {
    let mint: Mint
    let quote: LightningMeltQuote

    static func == (lhs: MeltQuoteBundle, rhs: MeltQuoteBundle) -> Bool {
        lhs.mint.mintID == rhs.mint.mintID &&
        lhs.quote.quote == rhs.quote.quote &&
        lhs.quote.method == rhs.quote.method &&
        lhs.quote.amount == rhs.quote.amount &&
        lhs.quote.feeReserve == rhs.quote.feeReserve &&
        lhs.quote.expiry == rhs.quote.expiry
    }
}

/// What a quote-source view publishes back to its host so the host can
/// drive its action button and decide when to invoke execution.
enum MeltSourceState: Equatable {
    case awaitingInput
    case needsAmount(canContinue: Bool)
    case loading
    case insufficientBalance
    case error(String)
    case ready(bundles: [MeltQuoteBundle], totalFee: Int)
}

/// The two Lightning methods share accounting and UI, but retain their own
/// endpoints and persisted representations. Only BOLT11 payments can span mints.
enum LightningMeltQuote: Codable, Sendable {
    case bolt11(CashuSwift.Bolt11.MeltQuote)
    case bolt12(CashuSwift.Bolt12.MeltQuote)

    private var fields: any CashuSwift.MeltQuoteResponse {
        switch self {
        case .bolt11(let quote): quote
        case .bolt12(let quote): quote
        }
    }

    var method: CashuSwift.PaymentMethodID { fields.method }
    var quote: String { fields.quote }
    var amount: Int { fields.amount }
    var unit: String { fields.unit }
    var state: CashuSwift.QuoteState? { fields.state }
    var expiry: Int? { fields.expiry }
    var change: [CashuSwift.Promise]? { fields.change }

    var request: String? {
        switch self {
        case .bolt11(let quote): quote.request
        case .bolt12(let quote): quote.request
        }
    }

    var feeReserve: Int {
        switch self {
        case .bolt11(let quote): quote.feeReserve
        case .bolt12(let quote): quote.feeReserve
        }
    }

    var paymentPreimage: String? {
        switch self {
        case .bolt11(let quote): quote.paymentPreimage
        case .bolt12(let quote): quote.paymentPreimage
        }
    }

    var requestLabel: String {
        method == .bolt12 ? String(localized: "BOLT12 OFFER") : String(localized: "BOLT11 INVOICE")
    }

    func requiredInputAmount(inputFee: Int) throws -> Int {
        let (total, overflow) = amount.addingReportingOverflow(feeReserve)
        let (withFee, feeOverflow) = total.addingReportingOverflow(inputFee)
        guard amount > 0, feeReserve >= 0, inputFee >= 0, !overflow, !feeOverflow else {
            throw CashuError.invalidAmount
        }
        return withFee
    }

    static func validatePayment(_ quotes: [LightningMeltQuote], now: Date = Date()) throws {
        guard !quotes.isEmpty,
              quotes.allSatisfy({ $0.method == quotes[0].method }),
              quotes.count == 1 || quotes[0].method == .bolt11 else {
            throw CashuError.inputError(String(localized: "BOLT12 payments must be paid in full from one mint."))
        }
        for quote in quotes {
            guard quote.unit == "sat" else { throw CashuError.unitError(String(localized: "Unsupported Lightning payment unit.")) }
            _ = try quote.requiredInputAmount(inputFee: 0)
            if let expiry = quote.expiry, TimeInterval(expiry) <= now.timeIntervalSince1970 {
                throw CashuError.quoteIsExpired
            }
        }
    }

    typealias BlankOutputs = (outputs: [CashuSwift.Output], blindingFactors: [String], secrets: [String])

    struct Result: Sendable {
        let quote: LightningMeltQuote
        let change: [CashuSwift.Proof]
    }

    func melt(from mint: CashuSwift.Mint, proofs: [CashuSwift.Proof], blankOutputs: BlankOutputs?) async throws -> Result {
        switch self {
        case .bolt11(let quote):
            let result = try await CashuSwift.Bolt11.melt(quote: quote, from: mint, proofs: proofs, blankOutputs: blankOutputs)
            return Result(quote: try validatedResponse(.bolt11(result.quote)), change: result.change ?? [])
        case .bolt12(let quote):
            let result = try await CashuSwift.Bolt12.melt(quote: quote, from: mint, proofs: proofs, blankOutputs: blankOutputs)
            return Result(quote: try validatedResponse(.bolt12(result.quote)), change: result.change ?? [])
        }
    }

    func checkState(from mint: CashuSwift.Mint, blankOutputs: BlankOutputs?) async throws -> Result {
        switch self {
        case .bolt11:
            let result = try await CashuSwift.Bolt11.meltState(quote, from: mint, blankOutputs: blankOutputs)
            return Result(quote: try validatedResponse(.bolt11(result.quote)), change: result.change ?? [])
        case .bolt12:
            let result = try await CashuSwift.Bolt12.meltState(quote, from: mint, blankOutputs: blankOutputs)
            return Result(quote: try validatedResponse(.bolt12(result.quote)), change: result.change ?? [])
        }
    }

    private func validatedResponse(_ response: LightningMeltQuote) throws -> LightningMeltQuote {
        guard response.quote == quote, response.unit == unit, response.amount == amount else {
            throw CashuError.inputError(String(localized: "The mint's response does not match the saved payment."))
        }
        _ = try response.requiredInputAmount(inputFee: 0)
        return response.preservingRequest(from: self)
    }

    /// Mints may omit the original request from execution and state responses.
    func preservingRequest(from original: LightningMeltQuote) -> LightningMeltQuote {
        let request = original.request ?? request
        switch self {
        case .bolt11(let q):
            return .bolt11(.init(quote: q.quote, request: request, amount: q.amount, unit: q.unit,
                                 feeReserve: q.feeReserve, state: q.state, expiry: q.expiry,
                                 paymentPreimage: q.paymentPreimage, change: q.change))
        case .bolt12(let q):
            return .bolt12(.init(quote: q.quote, request: request, amount: q.amount, unit: q.unit,
                                 feeReserve: q.feeReserve, state: q.state, expiry: q.expiry,
                                 paymentPreimage: q.paymentPreimage, change: q.change))
        }
    }
}

extension LightningMeltQuote: CashuSwift.MeltQuoteResponse {}

extension AppSchemaV1.Event {
    var lightningMeltQuote: LightningMeltQuote? {
        get {
            if let quote = bolt11MeltQuote { return .bolt11(quote) }
            guard let quote = genericMeltQuote, quote.method == .bolt12 else { return nil }
            let request: String?
            if case .string(let value) = quote.raw["request"] { request = value } else { request = nil }
            return .bolt12(.init(quote: quote.quote, request: request, amount: quote.amount,
                                 unit: quote.unit, feeReserve: quote.feeReserve, state: quote.state,
                                 expiry: quote.expiry, paymentPreimage: quote.paymentPreimage, change: quote.change))
        }
        set {
            switch newValue {
            case .bolt11(let quote):
                bolt11MeltQuote = quote
            case .bolt12(let quote):
                // The existing Data column needs a method discriminator so these
                // otherwise identical JSON shapes never decode as BOLT11.
                genericMeltQuote = (try? JSONDecoder().decode(CashuSwift.Generic.MeltQuote.self,
                                                             from: JSONEncoder().encode(quote)))?.settingMethod(.bolt12)
            case nil:
                genericMeltQuote = nil
            }
        }
    }
}
