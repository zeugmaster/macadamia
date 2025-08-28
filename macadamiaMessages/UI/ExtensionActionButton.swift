import SwiftUI

// MARK: - Standalone Action Button for Extension
enum ExtensionButtonState: Equatable {
    case idle(String, action: () -> Void)
    case loading(String = "Loading...")
    case success(String = "Success!")
    case error(String = "Failed")
    
    static func == (lhs: ExtensionButtonState, rhs: ExtensionButtonState) -> Bool {
        switch (lhs, rhs) {
        case (.idle(let l, _), .idle(let r, _)):
            return l == r
        case (.loading(let l), .loading(let r)):
            return l == r
        case (.success(let l), .success(let r)):
            return l == r
        case (.error(let l), .error(let r)):
            return l == r
        default:
            return false
        }
    }
    
    var title: String {
        switch self {
        case .idle(let title, _):
            return title
        case .loading(let title):
            return title
        case .success(let title):
            return title
        case .error(let title):
            return title
        }
    }
    
    var isInteractive: Bool {
        if case .idle = self {
            return true
        }
        return false
    }
    
    var backgroundColor: Color {
        switch self {
        case .idle:
            return .blue.opacity(0.8)
        case .loading:
            return .gray.opacity(0.6)
        case .success:
            return .green.opacity(0.8)
        case .error:
            return .red.opacity(0.8)
        }
    }
    
    var textColor: Color {
        return .white
    }
}

struct ExtensionActionButton: View {
    @Binding var state: ExtensionButtonState
    let isDisabled: Bool
    
    init(state: Binding<ExtensionButtonState>, isDisabled: Bool = false) {
        self._state = state
        self.isDisabled = isDisabled
    }
    
    var body: some View {
        Button(action: performAction) {
            HStack {
                if case .loading = state {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                }
                
                Text(state.title)
                    .font(.title3)
                    .fontWeight(.semibold)
            }
            .foregroundColor(state.textColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isDisabled ? Color.gray.opacity(0.3) : state.backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
        }
        .disabled(isDisabled || !state.isInteractive)
        .animation(.easeInOut(duration: 0.2), value: state)
    }
    
    private func performAction() {
        if case .idle(_, let action) = state {
            action()
        }
    }
}

// MARK: - Preview
#if DEBUG
struct ExtensionActionButton_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            ExtensionActionButton(
                state: .constant(.idle("Send Ecash", action: {})),
                isDisabled: false
            )
            
            ExtensionActionButton(
                state: .constant(.loading()),
                isDisabled: false
            )
            
            ExtensionActionButton(
                state: .constant(.success()),
                isDisabled: false
            )
            
            ExtensionActionButton(
                state: .constant(.error()),
                isDisabled: false
            )
            
            ExtensionActionButton(
                state: .constant(.idle("Send Ecash", action: {})),
                isDisabled: true
            )
        }
        .padding()
        .preferredColorScheme(.dark)
        .background(Color.black)
    }
}
#endif
