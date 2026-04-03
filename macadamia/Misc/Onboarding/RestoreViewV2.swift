//
//  RestoreView.swift
//  macadamia
//
//  Created by zm on 03.04.26.
//

import SwiftUI

let dummyMintUrls = [
    URL(string: "https://testmint.macadamia.cash")!,
    URL(string: "https://testnut.cashu.space")!,
    URL(string: "https://success.fake.macadamia.cash")!
]

struct RestoreViewV2: View {
    let seed: [String]
    
    @State private var mintUrls = [URL]()
    @State private var selectedMintUrls = Set<URL>()
    @State private var mintUrlInput = ""
    
    var body: some View {
        Group {
            if mintUrls.isEmpty {
                VStack {
                    Text("No mints yet...")
                    ProgressView()
                    Spacer()
                }
                .padding()
            } else {
                List {
                    ForEach(mintUrls, id: \.absoluteString) { url in
                        Button {
                            toggle(url)
                        } label: {
                            HStack {
                                Image(systemName: selectedMintUrls.contains(url) ? "checkmark.circle.fill" : "circle")
                                Text(url.host() ?? url.absoluteString)
                            }
                        }
                        .listRowBackground(Color.primary.opacity(0.08))
                    }
                    HStack {
                        Image(systemName: "plus")
                        TextField("", text: $mintUrlInput, prompt: Text("mint.example.com"))
                            .keyboardType(.URL)
                    }
                    .listRowBackground(Color.primary.opacity(0.08))
                }
                .scrollContentBackground(.hidden)
            }
        }
        .task {
            try? await loadMintUrls()
        }
    }
    
    private func toggle(_ url: URL) {
        if selectedMintUrls.contains(url) {
            selectedMintUrls.remove(url)
        } else {
            selectedMintUrls.insert(url)
        }
    }
    
    private func loadMintUrls() async throws {
        try await Task.sleep(for: .seconds(2))
        self.mintUrls = dummyMintUrls
        self.selectedMintUrls = Set(mintUrls)
    }
}

#Preview {
    ZStack {
        Rectangle().fill(Color.black.gradient)
        RestoreViewV2(seed: dummySeed)
    }
}
