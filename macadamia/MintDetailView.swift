//
//  MintDetailView.swift
//  macadamia
//
//  Created by zm on 18.07.24.
//

import SwiftUI

struct MintDetailView: View {
    @State var mintInfo: MintInfo
    
    var body: some View {
        List {
            Section {
                HStack {
                    Spacer()
                    AsyncImage(url: mintInfo.imageURL) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: UIScreen.main.bounds.width / 4)
                    } placeholder: {
                        ProgressView()
                            .frame(width: UIScreen.main.bounds.width / 4, height: UIScreen.main.bounds.width / 4)
                    }
                    Spacer()
                }
            }
            .listRowBackground(Color.clear)
            
            Section {
                ForEach(0..<4) { index in
                    Text("Item \(index + 1)")
                }
            }
            Section {
                Button(role: .destructive) {
                    
                } label: {
                    HStack {
                        Text("Remove this mint")
                        Spacer()
                        Image(systemName: "trash")
                    }
                }

            }
        }
    }
}

#Preview {
    MintDetailView(mintInfo: mint1)
}
