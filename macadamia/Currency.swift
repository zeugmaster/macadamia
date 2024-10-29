//
//  Currency.swift
//  macadamia
//
//  Created by zm on 18.10.24.
//

import Foundation

func amountDisplayString(_ amount: Int, unit: Unit, negative: Bool = false) -> String {
    let numberFormatter = NumberFormatter()
    
    switch unit {
    case .sat:
        var signedAmount = amount
        if negative && amount > 0 {
            if let negated = safeNegate(amount) {
                signedAmount = negated
            }
        }
        return String(signedAmount) + " sat"
        
    case .usd:
        numberFormatter.numberStyle = .currency
        numberFormatter.currencyCode = "USD"
        let fiat = Double(amount) / 100.0 * (negative ? -1.0 : 1.0)
        return numberFormatter.string(from: NSNumber(value: fiat)) ?? ""
        
    case .eur:
        numberFormatter.numberStyle = .currency
        numberFormatter.currencyCode = "EUR"
        let fiat = Double(amount) / 100.0 * (negative ? -1.0 : 1.0)
        return numberFormatter.string(from: NSNumber(value: fiat)) ?? ""
        
    case .other:
        var signedAmount = amount
        if negative && amount != 0 {
            if let negated = safeNegate(amount) {
                signedAmount = negated
            }
        }
        return String(signedAmount) + "other"
    }
}

fileprivate func safeNegate(_ value: Int) -> Int? {
    let (result, didOverflow) = value.multipliedReportingOverflow(by: -1)
    return didOverflow ? nil : result
}

