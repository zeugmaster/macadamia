//
//  Currency.swift
//  macadamia
//
//  Created by zm on 18.10.24.
//

import Foundation

enum ConversionUnit: String, Codable, CaseIterable {
    case none = "NONE"
    case usd = "USD"
    case eur = "EUR"
    case jpy = "JPY"
    case gbp = "GBP"
    case aud = "AUD"
    case cad = "CAD"
    case chf = "CHF"
    case cny = "CNY"
    case hkd = "HKD"
    case nzd = "NZD"
    case sek = "SEK"
    case krw = "KRW"
    case sgd = "SGD"
    case nok = "NOK"
    case mxn = "MXN"
    case inr = "INR"
    case brl = "BRL"
    case rub = "RUB"
    case try_ = "TRY"
    case zar = "ZAR"
    case php = "PHP"
    case thb = "THB"
    case idr = "IDR"
    case myr = "MYR"
    case pln = "PLN"
    case dkk = "DKK"
    case czk = "CZK"
    case huf = "HUF"
    case ils = "ILS"
    case clp = "CLP"
    case ars = "ARS"
    case sar = "SAR"
    case aed = "AED"
    case twd = "TWD"
    case vnd = "VND"
    case pkr = "PKR"
    case egp = "EGP"
    case ngn = "NGN"
    case bdt = "BDT"
    case uah = "UAH"
    case ron = "RON"
    case pen = "PEN"
    case kwd = "KWD"
    case cop = "COP"
    case isk = "ISK"
    case mad = "MAD"
    case lkr = "LKR"
    case mmk = "MMK"
    
    var displayName: String {
        switch self {
        case .none: return String(localized: "None")
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
        }
    }
    
    var symbol: String {
        switch self {
        case .none: return ""
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
        }
    }
    
    init?(_ string: String?) {
        if let match = ConversionUnit.allCases.first(where: { $0.rawValue.lowercased() == string?.lowercased() }) {
            self = match
        } else {
            return nil
        }
    }
    
    /// Access the preferred conversion unit directly from UserDefaults without initializing AppState
    static var preferred: ConversionUnit {
        let key = "PreferredCurrencyConversionUnit"
        if let unitString = UserDefaults.standard.string(forKey: key),
           let unit = ConversionUnit(unitString) {
            return unit
        } else {
            return .usd // Default fallback
        }
    }
}

func amountDisplayString(_ amount: Int, unit: ConversionUnit, negative: Bool = false) -> String {
    guard unit != .none else { return "" }
    
    let numberFormatter = NumberFormatter()
    
    let prefix = (negative && amount != 0) ? "- " : ""
    
    numberFormatter.numberStyle = .currency
    numberFormatter.currencyCode = unit.rawValue // ConversionUnit uses ISO currency codes
    let fiat = Double(amount) / 100.0
    return prefix + (numberFormatter.string(from: NSNumber(value: fiat)) ?? "")
}

func amountDisplayString(_ amount: Int, unit: AppSchemaV1.Unit, negative: Bool = false) -> String {
    let numberFormatter = NumberFormatter()
    
    let prefix = (negative && amount != 0) ? "- " : ""
    
    switch unit {
    case .sat, .other:
        return prefix + String(amount) + " " + unit.rawValue
        
    case .usd, .eur:
        numberFormatter.numberStyle = .currency
        numberFormatter.currencyCode = unit.rawValue.uppercased() // corresponds to official currency codes
        let fiat = Double(amount) / 100.0
        return prefix + (numberFormatter.string(from: NSNumber(value: fiat)) ?? "")
        
    default:
        return String(amount)
    }
}
