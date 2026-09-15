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
                .foregroundStyle(.background)
                .fontWeight(.semibold)
                .padding(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.primary.opacity(0.9))
                }
            }
            Text(description)
                .padding(.top)
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.primary.opacity(0.05))
                .stroke(.primary.opacity(0.2).shadow(.drop(color: .primary, radius: 4)), lineWidth: 0.5)
        }
    }
}

#Preview {
    PaymentMethodCard(name: "Bolt12",
                      icon: Image(systemName: "bolt.fill"),
                      description: "Pay using a Bolt12 offer",
                      numberOfSupportingMints: 2)
    .padding()
}

#Preview {
    PaymentMethods()
}
