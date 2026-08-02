import CashuSwift
import Foundation

enum PaymentDirection: String, Codable, Hashable, Sendable {
    case mint
    case melt
}

struct PaymentMethodKind: Codable, Hashable, Sendable {
    let rawValue: String

    init(_ id: CashuSwift.PaymentMethodID) {
        self.rawValue = id.rawValue
    }

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    var id: CashuSwift.PaymentMethodID {
        CashuSwift.PaymentMethodID(rawValue: rawValue)
    }

    static let bolt11 = PaymentMethodKind(rawValue: "bolt11")
    static let bolt12 = PaymentMethodKind(rawValue: "bolt12")
    static let onchain = PaymentMethodKind(rawValue: "onchain")
    static let generic = PaymentMethodKind(rawValue: "generic")

    var displayName: String {
        switch rawValue {
        case Self.bolt11.rawValue:
            return "BOLT11"
        case Self.bolt12.rawValue:
            return "BOLT12"
        case Self.onchain.rawValue:
            return String(localized: "On-chain")
        case Self.generic.rawValue:
            return String(localized: "Generic")
        default:
            return rawValue.uppercased()
        }
    }
}

struct PaymentOption: Identifiable, Codable, Hashable, Sendable {
    let mintID: UUID
    let direction: PaymentDirection
    let unitCode: String
    let method: PaymentMethodKind
    let minAmount: Int?
    let maxAmount: Int?
    let options: CashuSwift.JSONObject?
    let commands: [String]?

    var id: String {
        "\(mintID.uuidString)|\(direction.rawValue)|\(unitCode)|\(method.rawValue)"
    }

    var unit: Unit {
        Unit(code: unitCode)
    }

    var displayName: String {
        "\(unit.displayName) - \(method.displayName)"
    }

    var shortDisplayName: String {
        "\(unit.currencyCode.uppercased()) - \(method.displayName)"
    }

    init(mintID: UUID,
         direction: PaymentDirection,
         unit: Unit,
         method: PaymentMethodKind,
         minAmount: Int? = nil,
         maxAmount: Int? = nil,
         options: CashuSwift.JSONObject? = nil,
         commands: [String]? = nil) {
        self.mintID = mintID
        self.direction = direction
        self.unitCode = unit.currencyCode.lowercased()
        self.method = method
        self.minAmount = minAmount
        self.maxAmount = maxAmount
        self.options = options
        self.commands = commands
    }

    init(mintID: UUID,
         direction: PaymentDirection,
         methodSetting: CashuSwift.Mint.Info.PaymentMethod) {
        self.init(mintID: mintID,
                  direction: direction,
                  unit: Unit(code: methodSetting.unit),
                  method: PaymentMethodKind(methodSetting.method),
                  minAmount: methodSetting.minAmount,
                  maxAmount: methodSetting.maxAmount,
                  options: methodSetting.options,
                  commands: methodSetting.commands)
    }
}

extension AppSchemaV1.Mint {
    @MainActor
    func supportedPaymentOptions(direction: PaymentDirection) async -> [PaymentOption] {
        do {
            guard let info = try await loadInfo() else {
                return legacyBolt11PaymentOptions(direction: direction)
            }

            let nutInfo: CashuSwift.Mint.Info.NutInfo?
            switch direction {
            case .mint:
                nutInfo = info.nuts?.nut04
            case .melt:
                nutInfo = info.nuts?.nut05
            }

            if nutInfo?.disabled == true {
                return []
            }

            let advertisedMethods = paymentMethods(from: nutInfo)
            guard !advertisedMethods.isEmpty else {
                return legacyBolt11PaymentOptions(direction: direction)
            }

            return advertisedMethods
                .map { PaymentOption(mintID: mintID, direction: direction, methodSetting: $0) }
                .sortedForDisplay()
        } catch {
            return legacyBolt11PaymentOptions(direction: direction)
        }
    }

    func legacyBolt11PaymentOptions(direction: PaymentDirection) -> [PaymentOption] {
        supportedUnits
            .map {
                PaymentOption(mintID: mintID,
                              direction: direction,
                              unit: $0,
                              method: .bolt11)
            }
            .sortedForDisplay()
    }

    private func paymentMethods(from nutInfo: CashuSwift.Mint.Info.NutInfo?) -> [CashuSwift.Mint.Info.PaymentMethod] {
        if let methods = nutInfo?.methods {
            return methods
        }
        if case .methods(let methods) = nutInfo?.supported {
            return methods
        }
        return []
    }
}

extension Array where Element == PaymentOption {
    func sortedForDisplay() -> [PaymentOption] {
        sorted {
            if $0.unitCode != $1.unitCode {
                return $0.unitCode < $1.unitCode
            }
            if $0.method == .bolt11 && $1.method != .bolt11 {
                return true
            }
            if $0.method != .bolt11 && $1.method == .bolt11 {
                return false
            }
            return $0.method.displayName < $1.method.displayName
        }
    }

    func preferredOption(preserving previous: PaymentOption?) -> PaymentOption? {
        if let previous,
           let match = first(where: { $0.unitCode == previous.unitCode && $0.method == previous.method }) {
            return match
        }
        if let satBolt11 = first(where: { $0.unit == .sat && $0.method == .bolt11 }) {
            return satBolt11
        }
        if let bolt11 = first(where: { $0.method == .bolt11 }) {
            return bolt11
        }
        return first
    }
}

/// A mint quote in either its first-class BOLT11 shape or the method-agnostic
/// generic shape used for every other advertised payment method (e.g. "branch").
enum MintQuoteVariant {
    case bolt11(CashuSwift.Bolt11.MintQuote)
    case generic(CashuSwift.Generic.MintQuote)

    var quoteID: String {
        switch self {
        case .bolt11(let quote): return quote.quote
        case .generic(let quote): return quote.quote
        }
    }

    var request: String {
        switch self {
        case .bolt11(let quote): return quote.request
        case .generic(let quote): return quote.request
        }
    }

    var unitCode: String {
        switch self {
        case .bolt11(let quote): return quote.unit
        case .generic(let quote): return quote.unit
        }
    }

    var amount: Int? {
        switch self {
        case .bolt11(let quote): return quote.amount
        case .generic(let quote): return quote.amount
        }
    }

    var expiry: Int? {
        switch self {
        case .bolt11(let quote): return quote.expiry
        case .generic(let quote): return quote.expiry
        }
    }

    var method: PaymentMethodKind {
        switch self {
        case .bolt11: return .bolt11
        case .generic(let quote): return PaymentMethodKind(quote.method)
        }
    }

    var bolt11Quote: CashuSwift.Bolt11.MintQuote? {
        if case .bolt11(let quote) = self { return quote }
        return nil
    }

    var genericQuote: CashuSwift.Generic.MintQuote? {
        if case .generic(let quote) = self { return quote }
        return nil
    }
}

extension CashuSwift.Generic.MintQuote {
    /// Key under which the wallet stores the NUT-20 locking-key counter inside
    /// the quote's raw JSON so it round-trips through local persistence. Never
    /// sent to the mint: execution bodies are built from quote ID and outputs
    /// only, and `encode(to:)` is used solely for local storage.
    static let nut20CounterKey = "macadamia_nut20_counter"

    var nut20Counter: UInt32? {
        if case let .integer(value) = raw[Self.nut20CounterKey] ?? .null {
            return UInt32(exactly: value)
        }
        return nil
    }

    /// A copy with the locking-key counter grafted into `raw`. Must be applied
    /// before the quote is persisted or held in view state.
    func addingNut20Counter(_ counter: UInt32) -> CashuSwift.Generic.MintQuote {
        var newRaw = raw
        newRaw[Self.nut20CounterKey] = .integer(Int64(counter))
        return CashuSwift.Generic.MintQuote(method: method,
                                            quote: quote,
                                            request: request,
                                            unit: unit,
                                            amount: amount,
                                            state: state,
                                            expiry: expiry,
                                            raw: newRaw)
    }

    /// The NUT-20 pubkey the mint echoed in the quote — its presence means the
    /// quote is locked and issuance must be signed.
    var lockingPubkey: String? {
        if case let .string(pubkey) = raw["pubkey"] ?? .null { return pubkey }
        return nil
    }

    var amountPaid: Int? {
        switch raw["amount_paid"] {
        case .integer(let value): return Int(value)
        case .double(let value): return Int(value)
        default: return nil
        }
    }

    var amountIssued: Int? {
        switch raw["amount_issued"] {
        case .integer(let value): return Int(value)
        case .double(let value): return Int(value)
        default: return nil
        }
    }

    /// Whether the mint reports this quote as payable into ecash. Methods
    /// without a typed state (e.g. "branch") express progress through
    /// `amount_paid` instead.
    var indicatesPaid: Bool {
        if state == .paid { return true }
        if case let .string(stateString) = raw["state"] ?? .null, stateString.uppercased() == "PAID" { return true }
        if let amountPaid, let amount { return amountPaid >= amount }
        return false
    }

    var indicatesIssued: Bool {
        if state == .issued { return true }
        if case let .string(stateString) = raw["state"] ?? .null, stateString.uppercased() == "ISSUED" { return true }
        if let amountIssued, let amount { return amountIssued >= amount }
        return false
    }
}

extension CashuSwift.Generic.MeltQuote {
    /// Raw state string from the mint. `QuoteState` models only
    /// UNPAID/PENDING/PAID/ISSUED; custom backends also emit e.g. FAILED or
    /// UNKNOWN, which decode to `state == nil` but stay readable here.
    var rawStateString: String? {
        if case let .string(stateString) = raw["state"] ?? .null { return stateString }
        return nil
    }

    var isFailed: Bool { rawStateString?.uppercased() == "FAILED" }

    /// A copy with `method` set and grafted into `raw`. Results from
    /// `Generic.melt` / `Generic.meltState` carry no method (the mint does not
    /// echo it and the library only injects it on quote creation), so quotes
    /// must pass through this before being persisted.
    func settingMethod(_ method: CashuSwift.PaymentMethodID) -> CashuSwift.Generic.MeltQuote {
        var newRaw = raw
        newRaw["method"] = .string(method.rawValue)
        return CashuSwift.Generic.MeltQuote(method: method,
                                            quote: quote,
                                            amount: amount,
                                            unit: unit,
                                            feeReserve: feeReserve,
                                            state: state,
                                            expiry: expiry,
                                            paymentPreimage: paymentPreimage,
                                            change: change,
                                            raw: newRaw)
    }
}
