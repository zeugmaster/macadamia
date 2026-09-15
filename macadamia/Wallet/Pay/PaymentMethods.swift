//
//  PaymentMethods.swift
//  macadamia
//
//  Created by zm on 15.09.26.
//

import SwiftUI
import CashuSwift

struct PaymentMethods: View {
    var body: some View {
        Text(/*@START_MENU_TOKEN@*/"Hello, World!"/*@END_MENU_TOKEN@*/)
    }
}

struct PaymentMethodCard: View {
    let name: String
    let icon: Image
    let description: String
    let numberOfSupportingMints: Int
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                icon
                Text(name)
                    .bold()
                Spacer()
                HStack(alignment: .center, spacing: 2) {
                    Text(String(numberOfSupportingMints))
                        .font(.callout)
                    Image(systemName: "building.columns")
                        .font(.caption)
                }
                .fontWeight(.regular)
                .padding(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.primary.opacity(0.1))
                        .stroke(.primary.opacity(0.1))
                }
            }
            Text(description)
                .font(.callout)
                .padding(.top)
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.primary.opacity(0.05))
                .stroke(.primary.opacity(0.2), lineWidth: 0.5)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        PaymentMethodCard(name: "Bolt11",
                          icon: Image(systemName: "bolt.fill"),
                          description: "Pay using a BOLT11",
                          numberOfSupportingMints: 3)
        PaymentMethodCard(name: "Bolt12",
                          icon: Image(systemName: "bolt.fill"),
                          description: "Pay using a BOLT12 offer",
                          numberOfSupportingMints: 1)
        PaymentMethodCard(name: "On-Chain",
                          icon: Image(systemName: "link"),
                          description: "Make a payment on the blockchain",
                          numberOfSupportingMints: 2)
        PaymentMethodCard(name: "Branch",
                          icon: Image(systemName: "arrow.down.to.line.compact"),
                          description: "Make a payment using the method \"branch\" ",
                          numberOfSupportingMints: 1)
    }
    .padding()
    Spacer()
}

#Preview {
    PaymentMethods()
}
