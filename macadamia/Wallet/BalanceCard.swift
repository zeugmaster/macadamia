//
//  BalanceCard.swift
//  macadamia
//
//  Created by zm on 30.11.24.
//

import SwiftUI

struct BalanceCard: View {
    
    @EnvironmentObject private var appState: AppState
    
    var balance: Int
    var unit: Unit
        
    @State private var convertedBalance: String = ""
    
    var body: some View {
        
        let cardWidth = 330.0
        let cardHeight = 150.0

        VStack {
            ZStack {
                // Card background with gradient and border
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [Color(white: 0.12), Color.black]),
                            center: .topTrailing,
                            startRadius: 0,
                            endRadius: cardWidth * 3
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.gray.opacity(0.6), lineWidth: 1)
                    )
                    .frame(width: cardWidth, height: cardHeight)

                // Content inside the card
                VStack {
                    HStack {
                        Text(balanceString)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Spacer()
                        Text(unit.rawValue)
                            .font(.title)
                            .foregroundColor(Color.gray)
                    }
                    Spacer()
                    switch appState.preferredConversionUnit {
                    case .usd, .eur:
                        HStack {
                            Text(convertedBalance)
                            Spacer()
                        }
                        .opacity(0.7)
                        .animation(.default, value: convertedBalance)
                    default:
                        EmptyView()
                    }
                }
                .padding(24)
                .frame(width: cardWidth, height: cardHeight)
            }
            .frame(width: cardWidth, height: cardHeight)
        }
        .background(Color.black.edgesIgnoringSafeArea(.all))
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

    private var balanceString: String {
        if balance == 0 {
            return "-"
        } else {
            return balance.formatted(.number)
        }
    }
    
    @MainActor
    private func convert() {
        
        convertedBalance = "..."

        guard let prices = appState.exchangeRates else {
            return
        }
                
        let bitcoinPrice:Int
        switch appState.preferredConversionUnit {
        case .usd: bitcoinPrice = prices.usd
        case .eur: bitcoinPrice = prices.eur
        default: convertedBalance = "?"; return
        }
                
        let bitcoinAmount = Double(balance) / 100_000_000.0
        let fiatValue = bitcoinAmount * Double(bitcoinPrice)
        var cents = Int(round(fiatValue * 100.0))
        
        var prefix = ""
        if cents == 0 && balance > 0 {
            cents = 1
            prefix = "~ "
        }
        
        convertedBalance = prefix + amountDisplayString(cents, unit: appState.preferredConversionUnit)
    }
}



#Preview {
    BalanceCard(balance: 500, unit: .sat)
}
