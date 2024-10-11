import SwiftUI

struct MintDetailView: View {
    @Bindable var mint: Mint

    @ScaledMetric(relativeTo: .title) private var iconSize: CGFloat = 80

    var body: some View {
        List {
            if let info = mint.info {
                Section {
                    HStack {
                        Spacer()
                        ZStack {
                            Group {
                                Color.gray.opacity(0.3)
                                if let imageURL = info.imageURL {
                                    AsyncImage(url: imageURL) { phase in
                                        switch phase {
                                        case let .success(image):
                                            image
                                                .resizable()
                                                .aspectRatio(contentMode: .fit)
                                        case .failure:
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
            } else {
                Text("No mint Info available.")
            }
            Section {
                VStack(alignment: .leading) {
                    Text("URL")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text(mint.url.absoluteString)
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

// #Preview {
//    MintDetailView(mintInfo: mint1)
// }
