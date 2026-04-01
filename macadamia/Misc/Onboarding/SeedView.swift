//
//  SeedView.swift
//  macadamia
//
//  Created by zm on 01.04.26.
//

import SwiftUI

struct SeedView: View {
    let seed: [String]
    
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 12) {
            ForEach(Array(seed.enumerated()), id: \.offset) { o, s in
                HStack {
                    Text(String(o+1))
                        .font(.callout)
                    Text(s)
                }
                .fontWeight(.semibold)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.1)))
    }
}

#Preview {
    SeedView(seed: dummySeed)
        .padding(30)
}
