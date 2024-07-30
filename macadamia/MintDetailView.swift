//
//  MintDetailView.swift
//  macadamia
//
//  Created by zm on 18.07.24.
//

import SwiftUI

struct MintDetailView: View {
    @State var mintInfo: MintInfo
    
    @ScaledMetric(relativeTo: .title) private var iconSize: CGFloat = 80
    
    var body: some View {
        List {
            Section {
                HStack {
                    Spacer()
                    ZStack {
                        Group {
                            Color.gray.opacity(0.3)
                            if let imageURL = mintInfo.imageURL {
                                AsyncImage(url: imageURL) { phase in
                                    switch phase {
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                    case .failure(_):
                                        Image(systemName: "photo")
                                    case .empty:
                                        ProgressView()
                                    @unknown default:
                                        EmptyView()
                                    }
                                }
                            } else {
                                Image(systemName: "building.columns")
                                    .foregroundColor(.white)
                                    .font(.title)
                            }
                        }
                        .frame(width: iconSize, height: iconSize) // Use a relative size or GeometryReader for more flexibility
                        .clipShape(Circle())
                    }
                    Spacer()
                }
            }
            .listRowBackground(Color.clear)
            
            Section {
                VStack(alignment:.leading) {
                    Text("URL")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text(mintInfo.url.absoluteString)
                }
            }
            Section {
                Button(role: .destructive) {
                    print("delete mint button pressed")
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
