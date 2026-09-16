//
//  DepositQuoteRequestView.swift
//  macadamia
//
//  Created by zm on 15.09.26.
//

import SwiftUI
import CashuSwift

struct DepositQuoteRequestView: View {
    
    let paymentMethod: CashuSwift.Mint.Info.PaymentMethod
    
    @State private var numericalInput: Int = 0
    @State private var selectedMint: Mint? = nil
    @State private var selectedUnit: Unit?
    @State private var availableUnits = [Unit]()
    
    var body: some View {
        List {
            Section {
                NumericalInputView(output: $numericalInput,
                                   baseUnit: selectedUnit ?? Unit(code: paymentMethod.unit),
                                   exchangeRates: AppState.shared.exchangeRates,
                                   onReturn: {
                    print(numericalInput)
                })
            }
            Section {
                MintPicker(label: "Mint",
                           selectedMint: $selectedMint,
                           paymentMethod: PaymentMethodKind(paymentMethod.method))
                if availableUnits.count > 1 {
                    Picker("Unit", selection: $selectedUnit) {
                        ForEach(availableUnits, id: \.self) { unit in
                            Text(unit.displayName).tag(Optional(unit))
                        }
                    }
                }
            }
        }
        .task(id: "\(selectedMint?.mintID.uuidString ?? "")|\(paymentMethod.method.rawValue)") {
            await refreshUnits()
        }
    }

    @MainActor
    private func refreshUnits() async {
        availableUnits = []
        guard let selectedMint else {
            selectedUnit = nil
            return
        }

        let options = await selectedMint.supportedPaymentOptions(direction: .deposit)
        guard !Task.isCancelled, self.selectedMint?.mintID == selectedMint.mintID else { return }

        var seen = Set<Unit>()
        let units = options
            .filter { $0.method == PaymentMethodKind(paymentMethod.method) }
            .map(\.unit)
            .filter { seen.insert($0).inserted }
        let preferredUnit = selectedUnit ?? Unit(code: paymentMethod.unit.lowercased())
        selectedUnit = units.first(where: { $0 == preferredUnit }) ?? units.first
        availableUnits = units
    }
}

#if DEBUG
#Preview {
    DepositQuoteRequestView(paymentMethod: CashuSwift.Mint.Info.PaymentMethod(method: "branch",
                                                                              unit: "sat"))
    .previewEnvironment()
}
#endif
