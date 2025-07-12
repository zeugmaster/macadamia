import SwiftUI

struct InputViewModal: View {
    private let durationIn: Double =    0.3
    private let durationOut: Double =   0.3
    
    @Binding var originFrame: CGRect
    @Environment(\.dismiss) private var dismiss
    
    @State private var placeHolderOpacity: Double = 1
    @State private var overallOpacity: Double = 0
    @State private var sizeToTarget = false
    
    let inputTypes: [InputView.InputType]
    let onResult: (InputView.Result) -> Void
    
    var body: some View {
        GeometryReader { proxy in
            ZStack() {
                Color.black.opacity(sizeToTarget ? 0.4 : 0)
                    .ignoresSafeArea()
                ZStack {
                    InputView(supportedTypes: inputTypes) { result in
                        onResult(result)
                        animateDismiss()
                    }
                    HStack {
                        Spacer()
                        VStack {
                            Button {
                                animateDismiss()
                            } label: {
                                Image(systemName: "xmark")
                                    .shadow(color: .white, radius: 10)
                                    .padding()
                                    .font(.title2)
                            }
                            Spacer()
                        }
                    }
                    Group {
                        RoundedRectangle(cornerRadius: 8).fill(Color.secondary)
                        Image(systemName: "camera.fill")
                            .font(.largeTitle)
                    }
                    .opacity(placeHolderOpacity)
                    .scaledToFill()
                }
                .opacity(overallOpacity)
                .scaleEffect( sizeToTarget ? 1 : 0)
                .frame(width: sizeToTarget ? proxy.size.width * 0.9 : originFrame.width,
                       height: sizeToTarget ? proxy.size.width * 0.9 : originFrame.height)
                .position(x: sizeToTarget ? proxy.frame(in: .global).midX : originFrame.midX,
                          y: sizeToTarget ? proxy.frame(in: .global).midY * 0.8 : originFrame.midY - 60)
                .onTapGesture {
                    // do nothing
                }
            }
            .onAppear {
                withAnimation(.easeInOut(duration: durationIn * 0.5)) {
                    overallOpacity = 1
                }
                withAnimation(.easeInOut(duration: durationIn).delay(durationIn)) {
                    placeHolderOpacity = 0
                }
                withAnimation(.spring(duration: durationIn)) {
                    sizeToTarget = true
                }
            }
            .onTapGesture {
                animateDismiss()
            }
        }
    }
    
    private func animateDismiss() {
        withAnimation(.easeInOut(duration: durationOut)) {
            sizeToTarget = false
        }
        withAnimation(.easeInOut(duration: durationOut * 0.5).delay(durationOut * 0.5)) {
            overallOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + durationOut) {
            withoutAnimation {
                dismiss()
            }
        }
    }
}

struct InputViewModalButton<Content: View>: View {
    
    @State private var presentModal = false
    @State private var buttonFrame: CGRect = .zero
    
    let inputTypes: [InputView.InputType]
    
    let label: () -> Content
    
    let onResult: (InputView.Result) -> Void
    
    var body: some View {
        Button {
            withoutAnimation {
                presentModal = true
            }
        } label: {
            label()
        }
        .fullScreenCover(isPresented: $presentModal) {
            InputViewModal(originFrame: $buttonFrame, inputTypes: inputTypes) { result in
                onResult(result)
            }
                .presentationBackground(Color.clear)
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: ButtonFrameKey.self,
                        value: proxy.frame(in: .global)
                    )
            }
        )
        .onPreferenceChange(ButtonFrameKey.self) {
            buttonFrame = $0
        }
    }
}

struct SampleView: View {
    @State private var presentModal = false
    @State private var buttonFrame: CGRect = .zero

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                gradient: .init(colors: [.blue, .yellow]),
                startPoint: .bottom,
                endPoint: .top
            )
            .ignoresSafeArea()

            ScrollView {
                Spacer(minLength: 700)
                HStack {
                    InputViewModalButton(inputTypes: [.token]) {
                        Text("I am a button.")
                    } onResult: { result in
                        print(result)
                    }
                    .padding()
                    .buttonStyle(.bordered)
                    Spacer()
                }
                Spacer(minLength: 700)
            }
        }
    }
}

private struct ButtonFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

extension View {
    func withoutAnimation(action: @escaping () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            action()
        }
    }
}

#Preview {
    SampleView()
}
