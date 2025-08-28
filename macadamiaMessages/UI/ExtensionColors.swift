import SwiftUI

// MARK: - Extension Color Palette
extension Color {
    /// Macadamia brand colors for extension
    static let macadamiaOrange = Color(red: 1.0, green: 0.647, blue: 0.0) // Bitcoin orange
    static let macadamiaGreen = Color(red: 0.0, green: 0.8, blue: 0.4)   // Success green  
    static let macadamiaRed = Color(red: 1.0, green: 0.3, blue: 0.3)     // Error red
    static let macadamiaGray = Color(red: 0.5, green: 0.5, blue: 0.5)    // Secondary gray
    
    /// Background colors
    static let macadamiaBackground = Color.black
    static let macadamiaSecondaryBackground = Color(red: 0.1, green: 0.1, blue: 0.1)
    static let macadamiaTertiary = Color(red: 0.2, green: 0.2, blue: 0.2)
    
    /// Text colors
    static let macadamiaPrimary = Color.white
    static let macadamiaSecondary = Color(red: 0.7, green: 0.7, blue: 0.7)
}

// MARK: - Extension Theme
struct ExtensionTheme {
    static let cornerRadius: CGFloat = 12
    static let smallCornerRadius: CGFloat = 8
    static let padding: CGFloat = 16
    static let smallPadding: CGFloat = 12
    
    static let primaryFont = Font.title3
    static let secondaryFont = Font.body
    static let captionFont = Font.caption
    
    static func cardBackground() -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.macadamiaSecondaryBackground)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
    }
    
    static func inputFieldStyle() -> some ViewModifier {
        return InputFieldModifier()
    }
}

// MARK: - Custom View Modifiers
struct InputFieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(
                RoundedRectangle(cornerRadius: ExtensionTheme.smallCornerRadius)
                    .fill(Color.macadamiaTertiary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ExtensionTheme.smallCornerRadius)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
    }
}

extension View {
    func extensionInputStyle() -> some View {
        self.modifier(InputFieldModifier())
    }
}
