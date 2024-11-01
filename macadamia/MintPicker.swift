//
//  MintPicker.swift
//  macadamia
//
//  Created by zm on 01.11.24.
//

import SwiftUI
import SwiftData

struct MintPicker: View {
    @Query private var mints: [Mint]
    
    @Binding var selectedMint:Mint?
    
    @State private var mintNamesAndIDs = [(name: String, id: UUID)]()
    @State private var selectedID = UUID()
        
    var body: some View {
        Group {
            if mintNamesAndIDs.isEmpty {
                Text("No mints yet.")
            } else {
                Picker("Mint", selection: $selectedID) {
                    ForEach(mintNamesAndIDs, id: \.id) { entry in
                        Text(entry.name)
                    }
                }
            }
        }
        .onAppear {
            populate()
        }
        .onChange(of: selectedID) { oldValue, newValue in
            selectedMint = mints.first(where: { $0.mintID == newValue })
        }
    }
    
    func populate() {
        mintNamesAndIDs = mints.map( { mint in
            let displayName = mint.nickName ?? mint.url.host() ?? mint.url.absoluteString
            return (displayName, mint.mintID)
        })
        if let first = mintNamesAndIDs.first {
            selectedID = first.id
        }
    }
}

//#Preview {
//    MintPicker()
//}
