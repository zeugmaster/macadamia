//
//  NumericalInputView.swift
//  macadamia
//
//  Created by zm on 08.09.25.
//

import SwiftUI
import Foundation
import UIKit

struct NumericalInputView: View {
    
    @Binding var output: Int
    let baseUnit: AppSchemaV1.Unit
    
    // Optional exchange rates - if nil, conversion features are disabled
    let exchangeRates: AppState.ExchangeRate?
    
    @State private var input: String = ""
    @State private var inputIsFiat = false
    @FocusState private var isInputFocused: Bool
    
    private var conversionUnit: ConversionUnit {
        ConversionUnit.preferred
    }
    
    private var placeholder: String {
        return "Enter amount"
    }
    
    private var keyboardType: UIKeyboardType {
        .decimalPad // Always use decimal pad, validation will filter decimals in sats mode
    }
    
    private var inputUnit: String {
        if inputIsFiat {
            return conversionUnit.rawValue
        } else {
            return "sats"
        }
    }
    
    private var toggleButtonDisabled: Bool {
        exchangeRates == nil || conversionUnit == .none
    }
    
    private var conversionText: String {
        guard conversionUnit != .none else { return "" }
        
        if inputIsFiat {
            // Input is fiat, show sats conversion
            if input.isEmpty {
                return "0 sats"
            } else if let sats = convertFiatToSats() {
                return "\(sats.formatted(.number)) sats"
            } else {
                return "Conversion unavailable"
            }
        } else {
            // Input is sats, show fiat conversion
            if input.isEmpty {
                if exchangeRates != nil {
                    return amountDisplayString(0, unit: conversionUnit)
                } else {
                    return "Conversion unavailable"
                }
            } else if let sats = Int(input), let fiatAmount = convertSatsToFiat(sats) {
                return amountDisplayString(fiatAmount, unit: conversionUnit)
            } else {
                return "Conversion unavailable"
            }
        }
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField(placeholder, text: $input)
                        .keyboardType(keyboardType)
                        .focused($isInputFocused)
                        .font(.title3)
                            .onChange(of: input) { _, newValue in
                                input = validateInput(newValue)
                                updateOutput()
                            }
                    
                    Text(inputUnit)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .monospaced()
                    
                }
                
                if conversionUnit != .none {
                    Text(conversionText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .animation(.default, value: conversionText)
                }
            }
            if conversionUnit != .none {
                Spacer(minLength: 30)
                Button {
                    toggleInputMode()
                } label: {
                    Image(systemName: "arrow.trianglehead.2.clockwise")
                        .foregroundColor(toggleButtonDisabled ? .gray : .accentColor)
                }
                .disabled(toggleButtonDisabled)
            }
        }
        .onAppear {
            updateOutput()
            isInputFocused = true
        }
    }
    
    private func convertFiatToSats() -> Int? {
        guard let rates = exchangeRates,
              let bitcoinPrice = rates.rate(for: conversionUnit) else {
            return nil
        }
        
        // Normalize decimal separator (replace comma with period for Double conversion)
        let normalizedInput = input.replacingOccurrences(of: ",", with: ".")
        
        guard let fiatValue = Double(normalizedInput) else {
            return nil
        }
        
        let bitcoinAmount = fiatValue / bitcoinPrice
        return Int(round(bitcoinAmount * 100_000_000.0))
    }
    
    private func convertSatsToFiat(_ sats: Int) -> Int? {
        guard let rates = exchangeRates,
              let bitcoinPrice = rates.rate(for: conversionUnit) else {
            return nil
        }
        
        let bitcoinAmount = Double(sats) / 100_000_000.0
        let fiatValue = bitcoinAmount * bitcoinPrice
        return Int(round(fiatValue * 100.0)) // Convert to cents
    }
    
    private func validateInput(_ value: String) -> String {
        if inputIsFiat {
            // Fiat mode: allow digits and up to 2 decimal places (support both . and , as decimal separators)
            
            // Remove any non-numeric characters except decimal separators
            let filtered = value.filter { $0.isNumber || $0 == "." || $0 == "," }
            
            // Count total decimal separators (both . and ,)
            let decimalCount = filtered.filter { $0 == "." || $0 == "," }.count
            
            // Only allow one decimal separator
            if decimalCount > 1 {
                return input // Return previous valid input
            }
            
            // Find the decimal separator (. or ,) and split on it
            var components: [String] = []
            if filtered.contains(".") {
                components = filtered.components(separatedBy: ".")
            } else if filtered.contains(",") {
                components = filtered.components(separatedBy: ",")
            } else {
                components = [filtered]
            }
            
            // Limit to 2 decimal places
            if components.count == 2 && components[1].count > 2 {
                let separator = filtered.contains(".") ? "." : ","
                return String(components[0] + separator + String(components[1].prefix(2)))
            }
            
            return filtered
        } else {
            // Sats mode: only allow digits (integers only)
            return value.filter { $0.isNumber }
        }
    }
    
    private func updateOutput() {
        if inputIsFiat {
            output = convertFiatToSats() ?? 0
        } else {
            output = Int(input) ?? 0
        }
    }
    
    private func toggleInputMode() {
        guard !toggleButtonDisabled else { return }
        
        withAnimation(.easeInOut(duration: 0.2)) {
            if inputIsFiat {
                // Convert current fiat input to sats
                if let sats = convertFiatToSats() {
                    input = String(sats)
                }
            } else {
                // Convert current sats input to fiat
                if let sats = Int(input), let fiatCents = convertSatsToFiat(sats) {
                    let fiatValue = Double(fiatCents) / 100.0
                    // Use the locale's preferred decimal separator, but default to period
                    let decimalSeparator = NumberFormatter().decimalSeparator ?? "."
                    input = String(format: "%.2f", fiatValue).replacingOccurrences(of: ".", with: decimalSeparator)
                }
            }
            
            inputIsFiat.toggle()
        }
    }
}

// Convenience initializer for use with AppState
extension NumericalInputView {
    init(output: Binding<Int>, baseUnit: AppSchemaV1.Unit, appState: AppState) {
        self._output = output
        self.baseUnit = baseUnit
        self.exchangeRates = appState.exchangeRates
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var amount = 100000
        
        var body: some View {
            VStack {
                Text("Amount: \(amount) sats")
                    .font(.headline)
                    .padding()
                
                NumericalInputView(
                    output: $amount,
                    baseUnit: .sat,
                    exchangeRates: nil
                )
                .padding()
                
                Spacer()
            }
        }
    }
    
    return PreviewWrapper()
}
