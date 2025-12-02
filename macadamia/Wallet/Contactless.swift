//
//  Contactless.swift
//  macadamia
//
//  Created by zm on 02.12.25.
//

import SwiftUI

struct Contactless: View {
    var body: some View {
        VStack {
            HStack {
                Image(systemName: "iphone.gen2.crop.circle")
                    .foregroundStyle(.primary.opacity(0.5))
                RadioWaveSymbol()
            }
            .font(.system(size: 60))
            .padding(20)
            Spacer()
        }
    }
}

#Preview {
    Contactless()
}


struct RadioWaveSymbol: View {
    @State private var isOn = false

    var body: some View {
        Image(systemName: "wave.3.right")
            .symbolRenderingMode(.palette)
            .foregroundStyle(
                .primary.opacity(0.5),   // inner
                .primary.opacity(0.6),   // middle
            )
            .symbolEffect(
                .variableColor.iterative.nonReversing,
                options: .repeating,
                value: isOn
            )
            .onAppear { isOn.toggle() }
    }
}
