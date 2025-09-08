//
//  Currency.swift
//  macadamia
//
//  Created by zm on 18.10.24.
//

import Foundation

enum ConversionUnit: String, Codable, CaseIterable {
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
    
    var displayName: String {
        switch self {
        case .usd: return "US Dollar"
        case .eur: return "Euro"
        case .jpy: return "Japanese Yen"
        case .gbp: return "British Pound"
        case .aud: return "Australian Dollar"
        case .cad: return "Canadian Dollar"
        case .chf: return "Swiss Franc"
        case .cny: return "Chinese Yuan"
        case .hkd: return "Hong Kong Dollar"
        case .nzd: return "New Zealand Dollar"
        case .sek: return "Swedish Krona"
        case .krw: return "South Korean Won"
        case .sgd: return "Singapore Dollar"
        case .nok: return "Norwegian Krone"
        case .mxn: return "Mexican Peso"
        }
    }
    
    var symbol: String {
        switch self {
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
