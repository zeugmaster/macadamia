import SwiftUI
import MarkdownUI

struct WalletMarkdownImages: ImageProvider, InlineImageProvider {
    func makeImage(url: URL?) -> some View { MarkdownImage(url: url) }

    func image(with url: URL, label: String) async throws -> Image {
        let (data, _) = try await NetworkController.shared.data(from: url)
        guard let image = UIImage(data: data), let pixels = image.cgImage else { throw URLError(.cannotDecodeContentData) }
        return Image(pixels, scale: image.scale, label: Text(label))
    }

    private struct MarkdownImage: View {
        let url: URL?
        @ObservedObject private var network = NetworkController.shared
        @State private var image: Image?

        var body: some View {
            Group {
                if let image { image.resizable().scaledToFit() }
                else { Image(systemName: "photo").foregroundStyle(.secondary) }
            }
            .task(id: "\(url?.absoluteString ?? "")-\(network.torOnly)") {
                guard let url else { return }
                image = try? await WalletMarkdownImages().image(with: url, label: "")
            }
        }
    }
}
