//
//  Alerts.swift
//  macadamia
//
//  Created by zeugmaster on 02.01.24.
//

import Foundation

import SwiftUI
import UIKit


struct AlertDetail {
    let title:String
    let alertDescription:String?
    let primaryButtonText:String?
    let affirmText:String?
    let onAffirm:(() -> Void)?
    
    init(title: String,
         description: String? = nil,
         primaryButtonText: String? = nil,
         affirmText: String? = nil,
         onAffirm: (() -> Void)? = nil) {
        
        self.title = title
        self.alertDescription = description
        self.primaryButtonText = primaryButtonText
        self.affirmText = affirmText
        self.onAffirm = onAffirm
    }
}

struct AlertViewModifier: ViewModifier {
    @Binding var isPresented: Bool
    var currentAlert: AlertDetail?

    func body(content: Content) -> some View {
        content
            .alert(currentAlert?.title ?? "Error", isPresented: $isPresented) {
                Button(role: .cancel) {
                    // This button could potentially reset or handle cancel logic
                } label: {
                    Text(currentAlert?.primaryButtonText ?? "OK")
                }
                if let affirmText = currentAlert?.affirmText, let onAffirm = currentAlert?.onAffirm {
                    Button(role: .destructive) {
                        onAffirm()
                    } label: {
                        Text(affirmText)
                    }
                }
            } message: {
                Text(currentAlert?.alertDescription ?? "")
            }
    }
}

extension View {
    func alertView(isPresented: Binding<Bool>, currentAlert: AlertDetail?) -> some View {
        self.modifier(AlertViewModifier(isPresented: isPresented, currentAlert: currentAlert))
    }
}


struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No need to update the controller here
    }
}

extension URL {
    func absoluteStringWithoutPrefix(_ prefix: String) -> String {
        var modifiedURL = self.absoluteString
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
        let textSize = (text as NSString).boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: .usesLineFragmentOrigin,
            attributes: attributes,
            context: nil
        ).size
        
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

