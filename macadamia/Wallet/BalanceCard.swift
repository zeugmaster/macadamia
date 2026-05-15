//
//  BalanceCard.swift
//  macadamia
//
//  Created by zm on 30.11.24.
//

import SwiftUI
import SwiftData

/// Paged container that renders one `BalanceCard` per currency unit present
/// in the active wallet's valid proofs. Falls back to a single `.sat` card
/// when the wallet has no proofs yet.
struct BalanceCarousel: View {

    @Query private var wallets: [Wallet]
    @Query(animation: .default) private var allProofs: [Proof]

    @State private var selectedIndex: Int = 0

    private var activeWallet: Wallet? {
        wallets.first(where: \.active)
    }

    /// Distinct units the active wallet currently holds (sat pinned first,
    /// the rest alphabetical by code). Always returns at least `[.sat]`.
    private var units: [Unit] {
        guard let wallet = activeWallet else { return [.sat] }

        var seen = Set<Unit>()
        var ordered: [Unit] = []
        for proof in allProofs
            where proof.state == .valid
            && proof.wallet == wallet
            && proof.mint?.hidden != true {
            if seen.insert(proof.currencyUnit).inserted {
                ordered.append(proof.currencyUnit)
            }
        }
        ordered.sort { lhs, rhs in
            if lhs == rhs { return false }
            if lhs == .sat { return true }
            if rhs == .sat { return false }
            return lhs.currencyCode < rhs.currencyCode
        }
        return ordered.isEmpty ? [.sat] : ordered
    }

    var body: some View {
        let units = units
        let cardHeight: CGFloat = 150

        VStack(spacing: 10) {
            TabView(selection: $selectedIndex) {
                ForEach(Array(units.enumerated()), id: \.element) { index, unit in
                    // Pad inside the page so the swipe gesture still covers the
                    // full width while the visible card has a screen-edge margin.
                    BalanceCard(unit: unit)
                        .padding(.horizontal, 24)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: cardHeight)

            // Page indicator. Reserve the same vertical slot when there's
            // only one unit so the carousel keeps a stable footprint.
            HStack(spacing: 6) {
                if units.count > 1 {
                    ForEach(0..<units.count, id: \.self) { i in
                        Circle()
                            .fill(i == selectedIndex ? Color.white : Color.gray.opacity(0.4))
                            .frame(width: 6, height: 6)
                    }
                }
            }
            .frame(height: 6)
            .animation(.snappy, value: selectedIndex)
        }
        .onChange(of: units) { _, newUnits in
            if selectedIndex >= newUnits.count {
                selectedIndex = max(0, newUnits.count - 1)
            }
        }
    }
}

struct BalanceCard: View {

    @EnvironmentObject private var appState: AppState
    @Query private var wallets: [Wallet]

    // Query proofs directly to trigger updates when proofs change
    @Query(animation: .default) private var allProofs: [Proof]

    private var activeWallet: Wallet? {
        wallets.first(where: \.active)
    }

    // Store balance in @State like MintManagerView does
    @State private var balance: Int = 0

    var unit: Unit

    @State private var convertedBalance: String = ""

    /// Whether the conversion subtitle should be shown for this card.
    /// Hidden when no preferred conversion unit is set, or when this card's
    /// unit already matches the preferred unit (no useful conversion).
    private var showsConversion: Bool {
        appState.preferredConversionUnit != .none
            && appState.preferredConversionUnit != unit
    }

    var body: some View {

        let cardHeight: CGFloat = 150

        ZStack {
            // Card background with gradient and border
            if #available(iOS 26.0, *) {
                // Pass the same rounded shape to both the foreground fill
                // and `glassEffect(in:)`. Using `.containerRelative` here
                // drops the corners when the card is hosted inside a
                // TabView page (the container shape becomes rectangular).
                let shape = ConcentricRectangle(corners: .concentric(minimum: 20),
                                                isUniform: true)
                shape
                    .fill(Color.clear)
                    .glassEffect(.regular, in: shape)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [Color.white.opacity(0.03), Color.black.opacity(0.3)]),
                            center: .topTrailing,
                            startRadius: 0,
                            endRadius: 500
                        )
                    )
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.gray.opacity(0.6), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.5), radius: 20)
            }

            // Content inside the card
            VStack {
                HStack {
                    Group {
                        if balance == 0 {
                            Text("-")
                        } else {
                            AmountView(amount: balance, unit: unit, showUnit: false)
                        }
                    }
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    Spacer()
                    Text(unit.currencyCode)
                        .font(.title)
                        .foregroundColor(Color.gray)
                }
                Spacer()
                if showsConversion {
                    HStack {
                        AmountView(text: convertedBalance)
                        Spacer()
                    }
                    .opacity(0.7)
                    .animation(.default, value: convertedBalance)
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, minHeight: cardHeight, maxHeight: cardHeight)
        .onTapGesture {
            withAnimation(.snappy(duration: 0.28, extraBounce: 0.05)) {
                appState.toggleConcealAmounts()
            }
        }
        .onAppear {
            calculateBalance()
        }
        .onChange(of: allProofs) { _, _ in
            calculateBalance()
        }
        .onChange(of: unit) { _, _ in
            calculateBalance()
            convert()
        }
        .task(id: balance) {
            convert()
        }
        .onChange(of: appState.preferredConversionUnit) { _, _ in
            convert()
        }
        .onChange(of: appState.exchangeRates) { _, _ in
            convert()
        }
    }

    private func calculateBalance() {
        guard let wallet = activeWallet else {
            balance = 0
            return
        }

        // Sum only the proofs that belong to this card's unit.
        let newBalance = allProofs
            .filter { $0.state == .valid
                && $0.wallet == wallet
                && $0.mint?.hidden != true
                && $0.currencyUnit == unit }
            .reduce(0) { $0 + $1.amount }

//        logger.info("calculateBalance() for \(unit.currencyCode) result: \(newBalance)")

        withAnimation {
            balance = newBalance
        }
    }

    @MainActor
    private func convert() {
        guard showsConversion else {
            convertedBalance = ""
            return
        }

        convertedBalance = "..."

        guard let prices = appState.exchangeRates,
              let preferredRate = prices.rate(for: appState.preferredConversionUnit) else {
            convertedBalance = "?"
            return
        }

        // Convert this card's balance into a BTC quantity so we can express
        // it through the BTC-denominated exchange rate table.
        let bitcoinAmount: Double
        switch unit {
        case .sat:
            bitcoinAmount = Double(balance) / 100_000_000.0
        case .msat:
            bitcoinAmount = Double(balance) / 100_000_000_000.0
        default:
            // Fiat-denominated ecash: balance is an integer in this unit's
            // minor unit (cents for USD, yen for JPY, fils for KWD, …).
            guard unit.kind == .fiat, let unitRate = prices.rate(for: unit) else {
                convertedBalance = "?"
                return
            }
            let major = Double(balance) / pow(10.0, Double(unit.minorUnit))
            bitcoinAmount = major / unitRate
        }

        // Express the result in the preferred unit's minor unit so we can
        // hand it to `amountDisplayString`, which expects on-wire integers.
        let preferred = appState.preferredConversionUnit
        let preferredMajor = bitcoinAmount * preferredRate
        var preferredMinor = Int(round(preferredMajor * pow(10.0, Double(preferred.minorUnit))))

        var prefix = ""
        if preferredMinor == 0 && balance > 0 {
            preferredMinor = 1
            prefix = "~ "
        }

        convertedBalance = prefix + amountDisplayString(preferredMinor, unit: preferred)
    }
}

#if DEBUG
#Preview("Carousel") {
    ZStack {
        Color.black.ignoresSafeArea()
        BalanceCarousel()
    }
    .previewEnvironment()
}

#Preview("Single Card") {
    ZStack {
        Color.black.ignoresSafeArea()
        BalanceCard(unit: .sat)
            .padding(.horizontal, 24)
    }
    .previewEnvironment()
}
#endif
