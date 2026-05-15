//
//  Currency.swift
//  macadamia
//
//  Created by zm on 18.10.24.
//

import Foundation

enum Currency {
    struct Amount: Equatable {
        let absoluteValue: Double
        let unit: Unit
        let negate: Bool

        /// Number of decimal digits between the on-wire integer amount and
        /// the major display unit. Delegates to the unit, which is what
        /// actually determines this per NUT-01 / ISO 4217.
        var precision: Int { unit.minorUnit }
    }

    enum Unit: Hashable, Codable {
        case none

        // MARK: Ecash / Bitcoin
        case sat
        case msat

        // MARK: Fiat
        case usd, eur, jpy, gbp, aud, cad, chf, cny, hkd, nzd, sek, krw, sgd
        case nok, mxn, inr, brl, rub, try_, zar, php, thb, idr, myr, pln, dkk
        case czk, huf, ils, clp, ars, sar, aed, twd, vnd, pkr, egp, ngn, bdt
        case uah, ron, pen, kwd, cop, isk, mad, lkr, mmk

        // MARK: Extensible
        case other(String)

        enum Kind {
            case fiat
            case ecash
            case other
            case none
        }

        var kind: Kind {
            switch self {
            case .none: return .none
            case .sat, .msat: return .ecash
            case .other: return .other
            default: return .fiat
            }
        }

        /// Number of decimal digits between the on-wire integer amount and
        /// the major display unit, per NUT-01 (which defers to ISO 4217 for
        /// fiat and stablecoins pegged to fiat). Examples:
        /// - `.usd` → 2  (amount = 1 means 1 cent)
        /// - `.jpy` → 0  (amount = 1 means 1 yen)
        /// - `.kwd` → 3  (amount = 1 means 1 fils)
        /// - `.sat` / `.msat` → 0 (already the minor unit of themselves)
        /// - `.other` → 0 (undefined by the spec; treat as raw integer)
        var minorUnit: Int {
            switch self {
            case .none, .sat, .msat:
                return 0
            // ISO 4217 currencies with 0 minor-unit digits.
            case .jpy, .krw, .clp, .isk, .vnd:
                return 0
            // ISO 4217 currencies with 3 minor-unit digits.
            case .kwd:
                return 3
            case .other:
                // The spec doesn't define how to discover precision for a
                // custom unit, so the safest default is to treat the amount
                // as a raw integer count. Callers that know better should
                // gate on `unit.kind != .other`.
                return 0
            default:
                return 2
            }
        }

        /// Canonical short code. ISO 4217 uppercase for fiat, lowercase for ecash, original payload for `.other`.
        var currencyCode: String {
            switch self {
            case .none: return ""
            case .sat: return "sat"
            case .msat: return "msat"
            case .usd: return "USD"
            case .eur: return "EUR"
            case .jpy: return "JPY"
            case .gbp: return "GBP"
            case .aud: return "AUD"
            case .cad: return "CAD"
            case .chf: return "CHF"
            case .cny: return "CNY"
            case .hkd: return "HKD"
            case .nzd: return "NZD"
            case .sek: return "SEK"
            case .krw: return "KRW"
            case .sgd: return "SGD"
            case .nok: return "NOK"
            case .mxn: return "MXN"
            case .inr: return "INR"
            case .brl: return "BRL"
            case .rub: return "RUB"
            case .try_: return "TRY"
            case .zar: return "ZAR"
            case .php: return "PHP"
            case .thb: return "THB"
            case .idr: return "IDR"
            case .myr: return "MYR"
            case .pln: return "PLN"
            case .dkk: return "DKK"
            case .czk: return "CZK"
            case .huf: return "HUF"
            case .ils: return "ILS"
            case .clp: return "CLP"
            case .ars: return "ARS"
            case .sar: return "SAR"
            case .aed: return "AED"
            case .twd: return "TWD"
            case .vnd: return "VND"
            case .pkr: return "PKR"
            case .egp: return "EGP"
            case .ngn: return "NGN"
            case .bdt: return "BDT"
            case .uah: return "UAH"
            case .ron: return "RON"
            case .pen: return "PEN"
            case .kwd: return "KWD"
            case .cop: return "COP"
            case .isk: return "ISK"
            case .mad: return "MAD"
            case .lkr: return "LKR"
            case .mmk: return "MMK"
            case .other(let code): return code
            }
        }

        var displayName: String {
            switch self {
            case .none: return String(localized: "None")
            case .sat: return String(localized: "Satoshi")
            case .msat: return String(localized: "Millisatoshi")
            case .usd: return String(localized: "US Dollar")
            case .eur: return String(localized: "Euro")
            case .jpy: return String(localized: "Japanese Yen")
            case .gbp: return String(localized: "British Pound")
            case .aud: return String(localized: "Australian Dollar")
            case .cad: return String(localized: "Canadian Dollar")
            case .chf: return String(localized: "Swiss Franc")
            case .cny: return String(localized: "Chinese Yuan")
            case .hkd: return String(localized: "Hong Kong Dollar")
            case .nzd: return String(localized: "New Zealand Dollar")
            case .sek: return String(localized: "Swedish Krona")
            case .krw: return String(localized: "South Korean Won")
            case .sgd: return String(localized: "Singapore Dollar")
            case .nok: return String(localized: "Norwegian Krone")
            case .mxn: return String(localized: "Mexican Peso")
            case .inr: return String(localized: "Indian Rupee")
            case .brl: return String(localized: "Brazilian Real")
            case .rub: return String(localized: "Russian Ruble")
            case .try_: return String(localized: "Turkish Lira")
            case .zar: return String(localized: "South African Rand")
            case .php: return String(localized: "Philippine Peso")
            case .thb: return String(localized: "Thai Baht")
            case .idr: return String(localized: "Indonesian Rupiah")
            case .myr: return String(localized: "Malaysian Ringgit")
            case .pln: return String(localized: "Polish Złoty")
            case .dkk: return String(localized: "Danish Krone")
            case .czk: return String(localized: "Czech Koruna")
            case .huf: return String(localized: "Hungarian Forint")
            case .ils: return String(localized: "Israeli Shekel")
            case .clp: return String(localized: "Chilean Peso")
            case .ars: return String(localized: "Argentine Peso")
            case .sar: return String(localized: "Saudi Riyal")
            case .aed: return String(localized: "UAE Dirham")
            case .twd: return String(localized: "Taiwan Dollar")
            case .vnd: return String(localized: "Vietnamese Dong")
            case .pkr: return String(localized: "Pakistani Rupee")
            case .egp: return String(localized: "Egyptian Pound")
            case .ngn: return String(localized: "Nigerian Naira")
            case .bdt: return String(localized: "Bangladeshi Taka")
            case .uah: return String(localized: "Ukrainian Hryvnia")
            case .ron: return String(localized: "Romanian Leu")
            case .pen: return String(localized: "Peruvian Sol")
            case .kwd: return String(localized: "Kuwaiti Dinar")
            case .cop: return String(localized: "Colombian Peso")
            case .isk: return String(localized: "Icelandic Króna")
            case .mad: return String(localized: "Moroccan Dirham")
            case .lkr: return String(localized: "Sri Lankan Rupee")
            case .mmk: return String(localized: "Myanmar Kyat")
            case .other(let code): return code
            }
        }

        var symbol: String {
            switch self {
            case .none: return ""
            case .sat: return "sat"
            case .msat: return "msat"
            case .usd: return "$"
            case .eur: return "€"
            case .jpy: return "¥"
            case .gbp: return "£"
            case .aud: return "A$"
            case .cad: return "C$"
            case .chf: return "CHF"
            case .cny: return "¥"
            case .hkd: return "HK$"
            case .nzd: return "NZ$"
            case .sek: return "kr"
            case .krw: return "₩"
            case .sgd: return "S$"
            case .nok: return "kr"
            case .mxn: return "$"
            case .inr: return "₹"
            case .brl: return "R$"
            case .rub: return "₽"
            case .try_: return "₺"
            case .zar: return "R"
            case .php: return "₱"
            case .thb: return "฿"
            case .idr: return "Rp"
            case .myr: return "RM"
            case .pln: return "zł"
            case .dkk: return "kr"
            case .czk: return "Kč"
            case .huf: return "Ft"
            case .ils: return "₪"
            case .clp: return "$"
            case .ars: return "$"
            case .sar: return "﷼"
            case .aed: return "د.إ"
            case .twd: return "NT$"
            case .vnd: return "₫"
            case .pkr: return "₨"
            case .egp: return "E£"
            case .ngn: return "₦"
            case .bdt: return "৳"
            case .uah: return "₴"
            case .ron: return "lei"
            case .pen: return "S/"
            case .kwd: return "د.ك"
            case .cop: return "$"
            case .isk: return "kr"
            case .mad: return "د.م."
            case .lkr: return "Rs"
            case .mmk: return "K"
            case .other(let code): return code
            }
        }

        /// Parse a code into a `Unit`. Known codes map to predefined cases;
        /// unknown non-empty codes become `.other(code)`; empty string becomes `.none`.
        init(code: String) {
            if code.isEmpty {
                self = .none
                return
            }
            let lower = code.lowercased()
            if let match = Self.predefined.first(where: { $0.currencyCode.lowercased() == lower }) {
                self = match
            } else {
                self = .other(code)
            }
        }

        /// Convenience: returns nil only for nil input. Unknown non-nil strings become `.other(string)`.
        init?(_ string: String?) {
            guard let s = string else { return nil }
            self = Self(code: s)
        }

        /// All predefined cases (excludes the open-ended `.other`).
        static let predefined: [Unit] = [
            .none, .sat, .msat,
            .usd, .eur, .jpy, .gbp, .aud, .cad, .chf, .cny, .hkd, .nzd, .sek,
            .krw, .sgd, .nok, .mxn, .inr, .brl, .rub, .try_, .zar, .php, .thb,
            .idr, .myr, .pln, .dkk, .czk, .huf, .ils, .clp, .ars, .sar, .aed,
            .twd, .vnd, .pkr, .egp, .ngn, .bdt, .uah, .ron, .pen, .kwd, .cop,
            .isk, .mad, .lkr, .mmk
        ]

        /// Fiat cases for pickers and exchange-rate fetches.
        static let fiatCases: [Unit] = [
            .usd, .eur, .jpy, .gbp, .aud, .cad, .chf, .cny, .hkd, .nzd, .sek,
            .krw, .sgd, .nok, .mxn, .inr, .brl, .rub, .try_, .zar, .php, .thb,
            .idr, .myr, .pln, .dkk, .czk, .huf, .ils, .clp, .ars, .sar, .aed,
            .twd, .vnd, .pkr, .egp, .ngn, .bdt, .uah, .ron, .pen, .kwd, .cop,
            .isk, .mad, .lkr, .mmk
        ]

        // MARK: - Codable

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let code = try container.decode(String.self)
            self = Self(code: code)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(currencyCode)
        }

        /// Access the preferred conversion unit directly from UserDefaults without initializing AppState.
        static var preferred: Unit {
            let key = "PreferredCurrencyConversionUnit"
            if let code = UserDefaults.standard.string(forKey: key) {
                return Unit(code: code)
            }
            return .usd
        }
    }
}

func amountDisplayString(_ amount: Int, unit: Currency.Unit, negative: Bool = false) -> String {
    let prefix = (negative && amount != 0) ? "- " : ""

    switch unit.kind {
    case .none:
        return ""
    case .ecash, .other:
        return prefix + String(amount) + " " + unit.currencyCode
    case .fiat:
        let digits = unit.minorUnit
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = unit.currencyCode
        // Force the fraction-digit count to match the unit's minor-unit
        // value so the display always agrees with how we scaled the integer
        // amount (avoids ICU vs. ISO 4217 disagreements, e.g. on IDR).
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        let major = Double(amount) / pow(10.0, Double(digits))
        return prefix + (formatter.string(from: NSNumber(value: major)) ?? "")
    }
}
