//
//  BalanceView.swift
//  macadamia
//
//  Created by zm on 21.07.24.
//

import SwiftUI


import SwiftUI

import SwiftUI

struct LargeDynamicText: View {
    let text: String
    let baseSize: CGFloat
    let minSize: CGFloat
    
    @State private var size: CGFloat
    @Environment(\.sizeCategory) var sizeCategory
    
    init(text: String, baseSize: CGFloat = 60, minSize: CGFloat = 20) {
        self.text = text
        self.baseSize = baseSize
        self.minSize = minSize
        self._size = State(initialValue: baseSize)
    }
    
    var body: some View {
        Text(text)
            .font(.system(size: scaledSize, weight: .regular, design: .default))
            .lineLimit(1)
            .minimumScaleFactor(0.1)
            .background(
                GeometryReader { geometry in
                    Color.clear.onAppear {
                        self.adjustSize(for: geometry.size.width)
                    }
                }
            )
    }
    
    private var scaledSize: CGFloat {
        size * dynamicTypeScale(for: sizeCategory)
    }
    
    private func adjustSize(for width: CGFloat) {
        let testSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        var currentSize = baseSize
        
        while currentSize > minSize {
            let font = UIFont.systemFont(ofSize: currentSize * dynamicTypeScale(for: sizeCategory))
            let attributes = [NSAttributedString.Key.font: font]
            let size = (text as NSString).boundingRect(with: testSize, options: .usesLineFragmentOrigin, attributes: attributes, context: nil)
            
            if size.width <= width {
                break
            }
            
            currentSize -= 1
        }
        
        self.size = max(currentSize, minSize)
    }
    
    private func dynamicTypeScale(for sizeCategory: ContentSizeCategory) -> CGFloat {
        switch sizeCategory {
        case .accessibilityExtraExtraExtraLarge: return 1.5
        case .accessibilityExtraExtraLarge: return 1.4
        case .accessibilityExtraLarge: return 1.3
        case .accessibilityLarge: return 1.2
        case .accessibilityMedium: return 1.1
        case .extraLarge: return 1.05
        case .large: return 1.0
        case .medium: return 0.95
        case .small: return 0.9
        case .extraSmall: return 0.85
        default: return 1.0
        }
    }
}

// Usage
struct BalanceView: View {
    let txt = "42000"
    var body: some View {
        LargeDynamicText(text: "4200", baseSize: 80)
            .monospaced()
            .bold()
    }
}

#Preview {
    BalanceView()
}
