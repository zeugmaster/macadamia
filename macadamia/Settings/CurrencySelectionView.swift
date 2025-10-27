//
//  CurrencySelectionView.swift
//  macadamia
//
//  Created by macadamia on 27.10.24.
//

import SwiftUI

struct CurrencySelectionView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    let conversionUnits = ConversionUnit.allCases
    
    var body: some View {
        List {
            ForEach(conversionUnits, id: \.self) { unit in
                Button(action: {
                    appState.preferredConversionUnit = unit
                    dismiss()
                }) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(unit.displayName)
                                .foregroundColor(.primary)
                            if unit != .none {
                                Text(unit.rawValue)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        if appState.preferredConversionUnit == unit {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Fiat Currency")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        CurrencySelectionView()
            .environmentObject(AppState(preview: true, preferredUnit: .usd))
    }
}

