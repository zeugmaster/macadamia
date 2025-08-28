import SwiftUI

// MARK: - Simple Alert System for Extension
struct ExtensionAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let buttonText: String
    
    init(title: String, message: String, buttonText: String = "OK") {
        self.title = title
        self.message = message
        self.buttonText = buttonText
    }
    
    init(error: Error) {
        self.title = "Error"
        self.message = String(describing: error)
        self.buttonText = "OK"
    }
}

// MARK: - Alert Modifier
struct ExtensionAlertModifier: ViewModifier {
    @Binding var alert: ExtensionAlert?
    
    func body(content: Content) -> some View {
        content
            .alert(
                alert?.title ?? "",
                isPresented: Binding(
                    get: { alert != nil },
                    set: { if !$0 { alert = nil } }
                )
            ) {
                Button(alert?.buttonText ?? "OK") {
                    alert = nil
                }
            } message: {
                Text(alert?.message ?? "")
            }
    }
}

extension View {
    func extensionAlert(_ alert: Binding<ExtensionAlert?>) -> some View {
        self.modifier(ExtensionAlertModifier(alert: alert))
    }
}
