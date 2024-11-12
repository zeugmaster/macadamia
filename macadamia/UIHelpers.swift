import Foundation
import SwiftUI
import UIKit


struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]

    func makeUIViewController(context _: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }

    func updateUIViewController(_: UIActivityViewController, context _: Context) {
        // No need to update the controller here
    }
}

extension URL {
    func absoluteStringWithoutPrefix(_ prefix: String) -> String {
        var modifiedURL = absoluteString
        let lowerPrefix = prefix.lowercased()
        // Check for "prefix://"
        let doubleSlashVariant = "\(lowerPrefix)://"
        if modifiedURL.hasPrefix(doubleSlashVariant) {
            modifiedURL.removeFirst(doubleSlashVariant.count)
        }
        // Check for "prefix:"
        else if modifiedURL.hasPrefix("\(lowerPrefix):") {
            modifiedURL.removeFirst("\(lowerPrefix):".count)
        }
        return modifiedURL
    }
}

struct AdaptiveDynamicTypeModifier: ViewModifier {
    @Environment(\.sizeCategory) var sizeCategory
    let text: String
    let maxWidth: CGFloat
    let maxHeight: CGFloat

    @State private var fontSize: CGFloat = 40 // Starting font size

    func body(content: Content) -> some View {
        content
            .font(.system(size: fontSize * getScaleFactor(for: sizeCategory)))
            .lineLimit(nil)
            .minimumScaleFactor(0.5)
            .background(
                GeometryReader { geometry in
                    Color.clear.onAppear {
                        self.adjustSize(for: geometry.size)
                    }
                }
            )
    }

    private func adjustSize(for size: CGSize) {
        let testFont = UIFont.systemFont(ofSize: fontSize * getScaleFactor(for: sizeCategory))
        let attributes = [NSAttributedString.Key.font: testFont]
        let textSize = (text as NSString).boundingRect(with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                                                       options: .usesLineFragmentOrigin,
                                                       attributes: attributes,
                                                       context: nil).size

        if textSize.width > maxWidth || textSize.height > maxHeight {
            fontSize -= 1
            DispatchQueue.main.async {
                self.adjustSize(for: size)
            }
        }
    }

    private func getScaleFactor(for sizeCategory: ContentSizeCategory) -> CGFloat {
        switch sizeCategory {
        case .accessibilityExtraExtraExtraLarge: return 2.0
        case .accessibilityExtraExtraLarge: return 1.8
        case .accessibilityExtraLarge: return 1.6
        case .accessibilityLarge: return 1.4
        case .accessibilityMedium: return 1.2
        default: return 3.0
        }
    }
}


//import SwiftData
//
//struct MintPicker: View {
//    // Observed query to fetch Mints from SwiftData
//    @Query private var mints: [Mint]
//    
//    // Binding to selected Mint
//    @Binding var selectedMint: Mint?
//    
//    init(selectedMint: Binding<Mint?>, sortBy: SortDescriptor<Mint> = SortDescriptor(\Mint.dateAdded, order: .reverse)) {
//        self._selectedMint = selectedMint
//        // Configure the query with sorting
//        _mints = Query(sort: [sortBy])
//    }
//    
//    var body: some View {
//        Picker("Select Mint", selection: $selectedMint) {
//            // Optional "No Selection" option
//            Text("None")
//                .tag(Optional<Mint>.none)
//            ForEach(mints) { mint in
//                MintRowView(mint: mint)
//                    .tag(Optional(mint))
//            }
//        }
//    }
//}
//
//// Separate view for each mint row in the picker
//struct MintRowView: View {
//    let mint: Mint
//    
//    var body: some View {
//        HStack {
//            // Display nickname if available, otherwise show URL
//            Text(mint.nickName ?? mint.url.host() ?? mint.url.absoluteString)
//            
//            // You can add additional information if needed
//            
//        }
//    }
//}
