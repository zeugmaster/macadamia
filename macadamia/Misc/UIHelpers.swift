import Foundation
import SwiftUI
import UIKit

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

struct DismissToRootAction: Sendable {
    private let action: @MainActor @Sendable () -> Void
    
    init(_ action: @escaping @MainActor @Sendable () -> Void = { @MainActor in }) {
        self.action = action
    }
    
    @MainActor
    func callAsFunction() {
        action()
    }
}
private struct DismissToRootKey: EnvironmentKey {
    static let defaultValue = DismissToRootAction()
}

extension EnvironmentValues {
    var dismissToRoot: DismissToRootAction {
        get { self[DismissToRootKey.self] }
        set { self[DismissToRootKey.self] = newValue }
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
