//
//  SeedView.swift
//  macadamia
//
//  Created by zm on 01.04.26.
//

import SwiftUI

struct SeedView: View {
    let seed: [String]
    
    private func seedEntry(index: Int, word: String) -> some View {
        HStack {
            // hidden text sets minimum width for consistent sizing
            Text("00")
                .font(.caption.monospacedDigit())
                .bold()
                .hidden()
                .overlay {
                    Text(String(index))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.background)
                        .bold()
                }
                .padding(2)
                .background {
                    Color.primary
                        .aspectRatio(1, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            Text(word)
                .fontWeight(.semibold)
        }
    }
    
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 30, verticalSpacing: 12) {
            ForEach(Array(seed.enumerated()), id: \.offset) { o, s in
                if o % 2 == 0 {
                    GridRow {
                        seedEntry(index: o + 1, word: s)
                        if o + 1 < seed.count {
                            seedEntry(index: o + 2, word: seed[o + 1])
                        }
                    }
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.1)))
    }
}

#Preview {
    SeedView(seed: dummySeed)
}
