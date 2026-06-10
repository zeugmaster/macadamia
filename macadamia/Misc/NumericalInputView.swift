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
    /// Unit the `output` integer is denominated in (the on-wire minor unit
    /// per NUT-01). Callers update this to retarget the input — e.g. the
    /// mint view switches it when the user picks a non-sat mint unit.
    let baseUnit: Currency.Unit

    /// Optional exchange rates - if nil, conversion features are disabled.
    let exchangeRates: AppState.ExchangeRate?
    let onReturn: () -> Void

    @State private var input: String = ""
    @State private var inputIsFiat = false
    @FocusState private var isInputFocused: Bool

    private var conversionUnit: Currency.Unit {
        Currency.Unit.preferred
    }

    /// True when there's a useful conversion to display — i.e. the user has
    /// a preferred conversion unit AND it differs from the input unit.
    private var showsConversion: Bool {
        conversionUnit != .none && conversionUnit != baseUnit
    }

    private var placeholder: String {
        return "Enter amount"
    }

    private var keyboardType: UIKeyboardType {
        .decimalPad // Always use decimal pad, validation will filter decimals when minor unit is 0.
    }

    /// Unit the user is currently typing in. Toggled by the swap button.
    private var activeInputUnit: Currency.Unit {
        inputIsFiat ? conversionUnit : baseUnit
    }

    private var inputUnitLabel: String {
        activeInputUnit.currencyCode
    }

    private var toggleButtonDisabled: Bool {
        exchangeRates == nil || !showsConversion
    }

    private var conversionText: String {
        guard showsConversion else { return "" }

        if inputIsFiat {
            // Typing in conversion unit; show the equivalent in base unit.
            if input.isEmpty {
                return amountDisplayString(0, unit: baseUnit)
            } else if let baseMinor = convertConversionInputToBase() {
                return amountDisplayString(baseMinor, unit: baseUnit)
            } else {
                return "Conversion unavailable"
            }
        } else {
            // Typing in base unit; show the equivalent in conversion unit.
            if input.isEmpty {
                if exchangeRates != nil {
                    return amountDisplayString(0, unit: conversionUnit)
                } else {
                    return "Conversion unavailable"
                }
            } else if let baseMinor = parseBaseInput(),
                      let convMinor = convertBaseToConversion(baseMinor) {
                return amountDisplayString(convMinor, unit: conversionUnit)
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
                        .onSubmit {
                            onReturn()
                        }

                    Text(inputUnitLabel)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .monospaced()
                }

                if showsConversion {
                    Text(conversionText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .animation(.default, value: conversionText)
                }
            }
            if showsConversion {
                Spacer(minLength: 30)
                Button {
                    toggleInputMode()
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .foregroundColor(toggleButtonDisabled ? .gray : .accentColor)
                }
                .disabled(toggleButtonDisabled)
            }
        }
        .onAppear {
            // Only sync if input is empty and we have an initial value
            if input.isEmpty && output > 0 {
                input = formatAsInput(output, in: baseUnit)
            }
            updateOutput()
            isInputFocused = true
        }
        .onChange(of: baseUnit) { _, _ in
            // The unit changed under us — drop any previously-typed value
            // since its scale no longer matches. Drop fiat-input mode too,
            // both for safety and to handle the new-unit-matches-preferred
            // case where the toggle no longer exists.
            input = ""
            output = 0
            inputIsFiat = false
        }
    }

    // MARK: - Conversion math

    /// Convert an integer amount in `baseUnit` minor units into a BTC value.
    /// Returns nil for `.other` or when rates are missing.
    private func toBTC(_ baseMinor: Int) -> Double? {
        switch baseUnit {
        case .sat:
            return Double(baseMinor) / 100_000_000.0
        case .msat:
            return Double(baseMinor) / 100_000_000_000.0
        default:
            guard baseUnit.kind == .fiat,
                  let rates = exchangeRates,
                  let rate = rates.rate(for: baseUnit) else { return nil }
            let major = Double(baseMinor) / pow(10.0, Double(baseUnit.minorUnit))
            return major / rate
        }
    }

    /// Convert a BTC value to an integer in `unit`'s minor units.
    private func fromBTC(_ btc: Double, to unit: Currency.Unit) -> Int? {
        switch unit {
        case .sat:
            return Int(round(btc * 100_000_000.0))
        case .msat:
            return Int(round(btc * 100_000_000_000.0))
        default:
            guard unit.kind == .fiat,
                  let rates = exchangeRates,
                  let rate = rates.rate(for: unit) else { return nil }
            let major = btc * rate
            return Int(round(major * pow(10.0, Double(unit.minorUnit))))
        }
    }

    private func convertBaseToConversion(_ baseMinor: Int) -> Int? {
        guard let btc = toBTC(baseMinor) else { return nil }
        return fromBTC(btc, to: conversionUnit)
    }

    /// Convert the user's `input` (typed in `conversionUnit` major form)
    /// into the base unit's on-wire minor integer.
    private func convertConversionInputToBase() -> Int? {
        let normalized = input.replacingOccurrences(of: ",", with: ".")
        guard let majorValue = Double(normalized),
              let rates = exchangeRates,
              let rate = rates.rate(for: conversionUnit) else { return nil }
        let btc = majorValue / rate
        return fromBTC(btc, to: baseUnit)
    }

    /// Parse `input` as an amount in `baseUnit`'s major form and return its
    /// integer minor-unit representation. Returns nil on parse failure.
    private func parseBaseInput() -> Int? {
        let normalized = input.replacingOccurrences(of: ",", with: ".")
        let digits = baseUnit.minorUnit
        if digits == 0 {
            return Int(normalized)
        }
        guard let major = Double(normalized) else { return nil }
        return Int(round(major * pow(10.0, Double(digits))))
    }

    // MARK: - Validation and output

    private func validateInput(_ value: String) -> String {
        let maxFractionDigits = activeInputUnit.minorUnit

        // Always start by stripping non-numerics (allow . , as separators).
        let filtered = value.filter { $0.isNumber || $0 == "." || $0 == "," }

        if maxFractionDigits == 0 {
            return filtered.filter { $0 != "." && $0 != "," }
        }

        // Disallow more than one decimal separator
        let decimalCount = filtered.filter { $0 == "." || $0 == "," }.count
        if decimalCount > 1 {
            return input // keep previous valid input
        }

        // Split on whichever separator is present
        var components: [String] = []
        if filtered.contains(".") {
            components = filtered.components(separatedBy: ".")
        } else if filtered.contains(",") {
            components = filtered.components(separatedBy: ",")
        } else {
            components = [filtered]
        }

        // Clamp the fractional part to the unit's minor-unit precision
        if components.count == 2 && components[1].count > maxFractionDigits {
            let separator = filtered.contains(".") ? "." : ","
            return String(components[0] + separator + String(components[1].prefix(maxFractionDigits)))
        }

        return filtered
    }

    private func updateOutput() {
        if inputIsFiat {
            output = convertConversionInputToBase() ?? 0
        } else {
            output = parseBaseInput() ?? 0
        }
    }

    private func toggleInputMode() {
        guard !toggleButtonDisabled else { return }

        withAnimation(.easeInOut(duration: 0.2)) {
            if inputIsFiat {
                // Conversion-unit text -> base-unit text
                if let baseMinor = convertConversionInputToBase() {
                    input = formatAsInput(baseMinor, in: baseUnit)
                }
            } else {
                // Base-unit text -> conversion-unit text
                if let baseMinor = parseBaseInput(),
                   let convMinor = convertBaseToConversion(baseMinor) {
                    input = formatAsInput(convMinor, in: conversionUnit)
                }
            }
            inputIsFiat.toggle()
        }
    }

    /// Render an integer minor-unit amount as a string suitable for the
    /// input text field, scaled to `unit`'s precision and using the user's
    /// locale decimal separator.
    private func formatAsInput(_ minorAmount: Int, in unit: Currency.Unit) -> String {
        let digits = unit.minorUnit
        if digits == 0 {
            return String(minorAmount)
        }
        let value = Double(minorAmount) / pow(10.0, Double(digits))
        let decimalSeparator = NumberFormatter().decimalSeparator ?? "."
        return String(format: "%.\(digits)f", value)
            .replacingOccurrences(of: ".", with: decimalSeparator)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State private var amount = 100000

        var body: some View {
            VStack {
                HStack(spacing: 4) {
                    Text("Amount:")
                    AmountView(amount: amount, unit: .sat)
                }
                    .font(.headline)
                    .padding()

                NumericalInputView(
                    output: $amount,
                    baseUnit: .sat,
                    exchangeRates: nil,
                    onReturn: {
                        print("user hit return")
                    }
                )
                .padding()

                Spacer()
            }
        }
    }

    return PreviewWrapper()
}
