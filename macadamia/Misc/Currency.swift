//
//  Currency.swift
//  macadamia
//
//  Created by zm on 18.10.24.
//

import Foundation

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
