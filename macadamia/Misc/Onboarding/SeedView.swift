//
//  SeedView.swift
//  macadamia
//
//  Created by zm on 01.04.26.
//

import SwiftUI

struct SeedPage: View {
    let seed: [String]
    
    @State private var copied = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Write down your seed phrase")
                .font(.title2.bold())

            Text("Store this somewhere safe. It is the only way to recover your wallet.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                
            Spacer(minLength: 0)
            VStack(spacing: 14) {
                SeedView(seed: seed)
                Button {
                    if copied { return }
                    UIPasteboard.general.string = seed.joined(separator: " ")
                    withAnimation {
                        copied = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation {
                            copied = false
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: copied ? "clipboard.fill" : "clipboard")
                        Text("Copy")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10)
                        .fill(Color.primary.gradient.opacity(0.8))
                        .stroke(.primary, style: StrokeStyle())
                        .opacity(0.15))
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity)
            Spacer()
            Spacer()
            Spacer() // dirty hack to save alignment on different type size settings
        }
        .frame(maxWidth: .infinity)
    }
}

struct SeedView: View {
    let seed: [String]
    
    private func seedEntry(index: Int, word: String) -> some View {
        HStack {
            // hidden text sets minimum width for consistent sizing
            Text("00")
                .font(.caption.monospacedDigit())
                .fontWeight(.heavy)
                .hidden()
                .overlay {
                    Text(String(index))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.background)
                        .fontWeight(.heavy)
                }
                .padding(2)
                .background {
                    Color.primary
                        .aspectRatio(1, contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .fixedSize()
            Text(word)
                .fontWeight(.semibold)
        }
    }
    
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 44, verticalSpacing: 18) {
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
        .padding(20)
        .background(RoundedRectangle(cornerRadius: 10)
            .fill(Color.primary.opacity(0.8))
            .stroke(.primary, style: StrokeStyle())
            .opacity(0.15))
    }
}

#Preview {
    ZStack(alignment: .topLeading) {
        Rectangle().fill(Color.black.gradient)
        SeedPage(seed: dummySeed)
            .padding(10)
    }
}
