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
    @State private var selectedOption: PaymentOption?
    
    var body: some View {
        List {
            Section {
                NumericalInputView(output: $numericalInput,
                                   baseUnit: selectedOption?.unit ?? Unit(code: paymentMethod.unit),
                                   exchangeRates: AppState.shared.exchangeRates,
                                   onReturn: {
                    print(numericalInput)
                })
            }
            Section {
                MintPicker(label: "Mint", selectedMint: $selectedMint)
                PaymentOptionPicker(direction: .deposit,
                                    label: String(localized: "Unit"),
                                    selectedMint: $selectedMint,
                                    selectedOption: $selectedOption,
                                    allowedMethods: [PaymentMethodKind(paymentMethod.method)])
            }
        }
    }
}

#if DEBUG
#Preview {
    DepositQuoteRequestView(paymentMethod: CashuSwift.Mint.Info.PaymentMethod(method: "bolt11",
                                                                              unit: "sat"))
    .previewEnvironment()
}
#endif
