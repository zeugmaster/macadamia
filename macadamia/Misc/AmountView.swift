//
//  Amount.swift
//  macadamia
//
//  Created by zm on 15.04.26.
//

import SwiftUI

struct AmountView: View {
    private let visibleText: String
    private let hideAmountOverride: Bool?

    @AppStorage(AmountConcealment.userDefaultsKey, store: AmountConcealment.userDefaults)
    private var storedHideAmount = false

    @State private var concealedText: String
    @State private var displayedText: String?
    @State private var transitionTask: Task<Void, Never>?

    init(amount: Int,
         unit: Currency.Unit,
         negative: Bool = false,
         showUnit: Bool = true,
         hideAmount: Bool? = nil) {
        let text = showUnit
            ? amountDisplayString(amount, unit: unit, negative: negative)
            : AmountView.unitlessAmountString(amount, unit: unit, negative: negative)
        visibleText = text
        hideAmountOverride = hideAmount
        _concealedText = State(initialValue: AmountConcealment.concealedString(for: text))
    }

    init(text: String, hideAmount: Bool? = nil) {
        visibleText = text
        hideAmountOverride = hideAmount
        _concealedText = State(initialValue: AmountConcealment.concealedString(for: text))
    }

    init(amount: Double, hideAmount: Bool) {
        let text = AmountView.doubleDisplayString(amount)
        visibleText = text
        hideAmountOverride = hideAmount
        _concealedText = State(initialValue: AmountConcealment.concealedString(for: text))
    }

    var body: some View {
        let hidden = hideAmountOverride ?? storedHideAmount
        let targetText = hidden ? concealedText : visibleText

        Text(displayedText ?? targetText)
            .accessibilityLabel(hidden ? Text("Amount hidden") : Text(visibleText))
            .onAppear {
                setDisplayedText(targetText)
            }
            .onChange(of: hidden) { _, isHidden in
                startCypherTransition(isHidden: isHidden)
            }
            .onChange(of: visibleText) { _, newValue in
                if hidden {
                    startCypherTransition(isHidden: true)
                } else {
                    setDisplayedText(newValue)
                }
            }
            .onDisappear {
                transitionTask?.cancel()
            }
    }

    private func startCypherTransition(isHidden: Bool) {
        transitionTask?.cancel()

        let finalText: String
        if isHidden {
            let newConcealedText = AmountConcealment.concealedString(for: visibleText)
            concealedText = newConcealedText
            finalText = newConcealedText
        } else {
            finalText = visibleText
        }

        let previousFrameCount = Int.random(in: 3...4)
        let frameCount = previousFrameCount - 1
        let frameDuration = 38 * previousFrameCount / frameCount
        transitionTask = Task { @MainActor in
            for _ in 0..<frameCount {
                guard !Task.isCancelled else { return }
                setDisplayedText(AmountConcealment.randomDigitString(matching: finalText))
                try? await Task.sleep(for: .milliseconds(frameDuration))
            }

            guard !Task.isCancelled else { return }
            setDisplayedText(finalText)
        }
    }

    @MainActor
    private func setDisplayedText(_ text: String) {
        var transaction = Transaction()
        transaction.animation = nil

        withTransaction(transaction) {
            displayedText = text
        }
    }

    private static func doubleDisplayString(_ amount: Double) -> String {
        if amount.rounded() == amount {
            return String(Int(amount))
        } else {
            return String(amount)
        }
    }

    /// Format an amount without any unit indicator. Use when the caller
    /// renders the unit code/symbol separately (e.g. the balance card,
    /// where the unit sits to the right of the number).
    fileprivate static func unitlessAmountString(_ amount: Int,
                                                 unit: Currency.Unit,
                                                 negative: Bool) -> String {
        let prefix = (negative && amount != 0) ? "- " : ""

        switch unit.kind {
        case .none:
            return ""
        case .ecash, .other:
            return prefix + String(amount)
        case .fiat:
            // Format the number with fiat's two-decimal convention but no
            // currency symbol or code — locale-aware separators preserved.
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
            let fiat = Double(amount) / 100.0
            let body = formatter.string(from: NSNumber(value: fiat))
                ?? String(format: "%.2f", fiat)
            return prefix + body
        }
    }
}

struct AmountPreview: View {
    @State private var hide = false
    @State private var amountString = ""

    var body: some View {
        VStack {
            Toggle("Toggle", isOn: $hide)
            TextField("input", text: $amountString)
                .textFieldStyle(.roundedBorder)
            AmountView(amount: Int(amountString) ?? 69, unit: .sat, hideAmount: hide)
            AmountView(amount: 123456, unit: .usd, hideAmount: hide)
        }
        .padding()
        .background(Color.black.gradient)
    }
}

#Preview {
    AmountPreview()
}
