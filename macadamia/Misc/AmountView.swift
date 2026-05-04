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
        let formatted = amountDisplayString(amount, unit: unit, negative: negative)
        let text = showUnit ? formatted : formatted.replacingUnitSuffix(unit)
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
}

private extension String {
    func replacingUnitSuffix(_ unit: Currency.Unit) -> String {
        guard unit != .none else { return self }

        let suffix = " " + unit.currencyCode
        if hasSuffix(suffix) {
            return String(dropLast(suffix.count))
        }

        return self
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
