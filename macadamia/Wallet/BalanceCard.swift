//
//  BalanceCard.swift
//  macadamia
//
//  Created by zm on 30.11.24.
//

import SwiftUI
import SwiftData

struct BalanceCard: View {
    
    @EnvironmentObject private var appState: AppState
    @Query private var wallets: [Wallet]
    
    // Query proofs directly to trigger updates when proofs change
    @Query(animation: .default) private var allProofs: [Proof]
    
    private var activeWallet: Wallet? {
        wallets.first
    }
    
    // Store balance in @State like MintManagerView does
    @State private var balance: Int = 0
    
    var unit: Unit
        
    @State private var convertedBalance: String = ""
    
    var body: some View {
        
        let cardWidth = 330.0
        let cardHeight = 150.0

        VStack {
            ZStack {
                // Card background with gradient and border
                if #available(iOS 26.0, *) {
                    ConcentricRectangle(corners: .concentric(minimum: 20), isUniform: true)
                        .fill(Color.clear)
                        .glassEffect(.regular, in: .containerRelative)
                } else {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [Color.white.opacity(0.03), Color.black.opacity(0.3)]),
                                center: .topTrailing,
                                startRadius: 0,
                                endRadius: cardWidth * 1.5
                            )
                        )
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.gray.opacity(0.6), lineWidth: 1)
                        )
                        .frame(width: cardWidth, height: cardHeight)
                        .shadow(color: .black.opacity(0.5), radius: 20)
                }

                // Content inside the card
                VStack {
                    HStack {
                        Group {
                            if balance == 0 {
                                Text("-")
                            } else {
                                Text(balance.formatted(.number))
                                    .lineLimit(1)
                                    .contentTransition(.numericText(value: Double(balance)))
                                    .animation(.snappy, value: balance)
                            }
                        }
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        Spacer()
                        Text(unit.rawValue)
                            .font(.title)
                            .foregroundColor(Color.gray)
                    }
                    Spacer()
                    if appState.preferredConversionUnit != .none {
                        HStack {
                            Text(convertedBalance)
                            Spacer()
                        }
                        .opacity(0.7)
                        .animation(.default, value: convertedBalance)
                    }
                }
                .padding(24)
                .frame(width: cardWidth, height: cardHeight)
            }
            .frame(width: cardWidth, height: cardHeight)
            .onTapGesture {
                calculateBalance()
            }
        }
        .onAppear {
            calculateBalance()
        }
        .onChange(of: allProofs) { _, _ in
            calculateBalance()
        }
        .task(id: balance) {
            convert()
        }
        .onChange(of: appState.preferredConversionUnit) { oldValue, newValue in
            convert()
        }
        .onChange(of: appState.exchangeRates) { oldValue, newValue in
            convert()
        }
    }
    
    private func calculateBalance() {
        guard let wallet = activeWallet else {
            balance = 0
            return
        }
        
        // Calculate from proofs query like MintManagerView does
        let newBalance = allProofs
            .filter { $0.state == .valid && $0.wallet == wallet && $0.mint?.hidden != true }
            .reduce(0) { $0 + $1.amount }
        
        withAnimation {
            balance = newBalance
        }
    }
    
    @MainActor
    private func convert() {
        guard appState.preferredConversionUnit != .none else {
            convertedBalance = ""
            return
        }
        
        convertedBalance = "..."

        guard let prices = appState.exchangeRates else {
            return
        }
                
        guard let bitcoinPrice = prices.rate(for: appState.preferredConversionUnit) else {
            convertedBalance = "?"
            return
        }
                
        let bitcoinAmount = Double(balance) / 100_000_000.0
        let fiatValue = bitcoinAmount * bitcoinPrice
        var cents = Int(round(fiatValue * 100.0))
        
        var prefix = ""
        if cents == 0 && balance > 0 {
            cents = 1
            prefix = "~ "
        }
        
        convertedBalance = prefix + amountDisplayString(cents, unit: appState.preferredConversionUnit)
    }
}

//#Preview {
//    ZStack(alignment: .top) {
//        List {
//            ForEach(0..<10) { _ in
//                Text("Hello, World!")
//            }
//        }
//        .safeAreaPadding(.top, 100)
//        BalanceCard(balance: 500, unit: .sat)
//            .environmentObject(AppState(preview: true, preferredUnit: .usd))
//            .padding()
//    }
//}
