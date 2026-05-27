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
