import SwiftUI
import OSLog

fileprivate let buttonLogger = Logger(subsystem: "macadamia", category: "interface")

private struct ActionButtonDisabledKey: EnvironmentKey {
    static let defaultValue: Bool = true
}

extension EnvironmentValues {
    var actionButtonDisabled: Bool {
        get { self[ActionButtonDisabledKey.self] }
        set { self[ActionButtonDisabledKey.self] = newValue }
    }
}

extension View {
    func actionDisabled(_ disabled: Bool) -> some View {
        environment(\.actionButtonDisabled, disabled)
    }
}

struct ActionButtonState: Equatable {
    enum StateType {
        case idle
        case loading
        case success
        case fail
    }
    
    static func == (lhs: ActionButtonState, rhs: ActionButtonState) -> Bool {
        (lhs.type == rhs.type)
        && (lhs.title == rhs.title)
    }
    
    var type: StateType
    var title: String
    var action: (() -> Void)? = nil
    
    // Convenience initializers for common states
    static func idle(_ title: String, action: (() -> Void)? = nil) -> ActionButtonState {
        ActionButtonState(type: .idle, title: title, action: action)
    }
    static func loading(_ title: String = "Loading...") -> ActionButtonState {
        ActionButtonState(type: .loading, title: title)
    }
    static func success(_ title: String = "Success!") -> ActionButtonState {
        ActionButtonState(type: .success, title: title)
    }
    static func fail(_ title: String = "Failed") -> ActionButtonState {
        ActionButtonState(type: .fail, title: title)
    }
}

struct ActionButton: View {
    @Binding var state: ActionButtonState
    let hideShadow: Bool
    
    private let cornerRadius: CGFloat = 20
    
    @GestureState private var isPressed = false
    
    @Environment(\.actionButtonDisabled) private var isDisabled
    
    @State private var animationColor: Color = .clear
    @State private var textColor: Color = .white.opacity(0.3)
    @State private var borderColor: Color = .clear
    @State private var circleScale = 0.01
    @State private var circleLineWidth = 0.0
    @State private var isAnimating = false
    @State private var backgroundColor: Color = .gray.opacity(0.15)
    @State private var sensoryFeedback: SensoryFeedback = .success
    @State private var feedbackTrigger = 0
    
    init(state:Binding<ActionButtonState>,
         hideShadow: Bool = false) {
        self._state = state
        self.hideShadow = hideShadow
    }
    
    var body: some View {
        let gesture = DragGesture(minimumDistance: 0)
            .updating($isPressed) { _, gestureState, _ in
                gestureState = true
            }
            .onEnded { _ in
                performAction()
            }
        
        return VStack {
            ZStack {
                // MARK: Background layer
                backgroundColor.background(.ultraThinMaterial)
                
                Group {
                    Circle()
                        .scale(circleScale)
                        .stroke(animationColor, lineWidth: circleLineWidth)
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(borderColor.opacity(0.6), lineWidth:6.0)
                }
                    
                // MARK: Content layer
                HStack {
                    if state.type == .loading {
                        ProgressView()
                    }
                    Text(state.title)
                }
                .font(.title3)
                .bold()
                .padding(EdgeInsets(top: 22, leading: 0, bottom: 22, trailing: 0))
                .foregroundStyle(textColor)
                
                // MARK: Overlay
                Color.white.opacity(isPressed ? 0.1 : 0.0)
                    .animation(.linear(duration: 0.07), value: isPressed)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
        .fixedSize(horizontal: false, vertical: true)
        .gesture(gesture)
        .padding()
        .sensoryFeedback(sensoryFeedback, trigger: feedbackTrigger)
        .onChange(of: state) { oldValue, newValue in
            didChangeState(newValue.type, disabled: isDisabled)
        }
        .onChange(of: isDisabled) { oldValue, newValue in
            didChangeState(state.type, disabled: newValue)
        }
        .allowsHitTesting(!isDisabled && state.type == .idle)
        .background(LinearGradient(colors: [.clear, hideShadow ? .clear : .black], startPoint: .top, endPoint: .bottom))
    }
    
    private func didChangeState(_ type: ActionButtonState.StateType, disabled: Bool) {
        switch type {
        case .success:
            fillAnimation(to: Color("successGreen"))
        case .fail:
            fillAnimation(to: Color("failureRed"))
        default:
            basicAnimation()
        }
    }
    
    private func fillAnimation(to color: Color) {
        animationColor = color
        
        circleScale = 0.0
        circleLineWidth = 0.0
        
        isAnimating = true
        
        withAnimation(Animation.spring(duration: 0.4)) {
            circleLineWidth = 350.0
            circleScale = 5
            backgroundColor = .gray.opacity(0.1)
            
        } completion: {
            borderColor = animationColor.opacity(0.7)
            
            withAnimation(.spring(duration: 0.4)) {
                textColor = animationColor
                circleLineWidth = 5
                circleScale = 10
            }
        }
    }
    
    private func basicAnimation() {
        withAnimation(.linear(duration: 0.1)) {
            animationColor = .clear
            borderColor = .clear
            textColor = .white.opacity(isDisabled ? 0.3 : 1)
            backgroundColor = .gray.opacity(isDisabled ? 0.15 : 0.25)
        }
    }
    
    private func buzz(_ type: ActionButtonState) {
        switch type {
        case .success():
            sensoryFeedback = .success
        case .fail():
            sensoryFeedback = .error
        default:
            return
        }
        feedbackTrigger += 1
    }
    
    private func performAction() {
        if let action = state.action {
            action()
        } else {
            buttonLogger.warning("ActionButton registered button press but no action closure is specified via state.action")
        }
    }
}

struct TestView: View {
    @State var text = ""
    
    @State var buttonState: ActionButtonState = .idle("Hello World!")
    
    var amount: Int {
        Int(text) ?? 0
    }
    
    var body: some View {
        ZStack {
            VStack {
                TextField("Enter a Number", text: $text)
                    .padding()
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                ActionButton(state: $buttonState)
                    .actionDisabled(amount < 1)
                    .onAppear {
                        buttonState = .idle("Hello World!", action: pressed)
                    }
            }
        }
    }
    
    func pressed() {
        buttonState = .loading()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            buttonState = .fail()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                buttonState = .idle("Hello World!", action: pressed)
            }
        }
    }
}

#Preview {
    TestView()
}
