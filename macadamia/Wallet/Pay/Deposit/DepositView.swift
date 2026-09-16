//
//  DepositView.swift
//  macadamia
//
//  Created by zm on 15.09.26.
//

import SwiftUI
import CashuSwift

struct DepositView: View {
    
    let paymentMethod: CashuSwift.Mint.Info.PaymentMethod
    
    // state: quoterequest
    // state: quote
    
    @State private var actionButtonState: ActionButtonState = .idle("")
    
    var body: some View {
        ZStack {
            // content
            
            VStack {
                Spacer()
                ActionButton(state: $actionButtonState, hideShadow: true)
            }
        }
    }
}

#Preview {
    DepositView(paymentMethod: CashuSwift.Mint.Info.PaymentMethod(method: "bolt11", unit: "sat"))
}

