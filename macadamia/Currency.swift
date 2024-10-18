//
//  Currency.swift
//  macadamia
//
//  Created by zm on 18.10.24.
//

import Foundation

func balanceString(_ amount:Int, unit:Unit) -> String {
    let numberFormatter = NumberFormatter()
    switch unit {
    case .sat:
        return String(amount) + " sat"
    case .usd:
        numberFormatter.numberStyle = .currency
        numberFormatter.currencyCode = "USD"
        let fiat = Double(amount) / 100.0
        return numberFormatter.string(from: NSNumber(value: fiat)) ?? ""
    case .eur:
        numberFormatter.numberStyle = .currency
        numberFormatter.currencyCode = "EUR"
        let fiat = Double(amount) / 100.0
        return numberFormatter.string(from: NSNumber(value: fiat)) ?? ""
    case .other:
        return String(amount) + "other"
    }
}
