//
//  ButtonBar.swift
//  macadamia
//
//  Created by zm on 30.03.26.
//

import SwiftUI

private struct OnboardingGlassBackground<S: Shape>: ViewModifier {
    let interactive: Bool
    let shape: S

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.clear.interactive(interactive), in: shape)
        } else {
            content.background(shape.fill(Color.primary.opacity(interactive ? 0.12 : 0.06)))
        }
    }
}

private extension View {
    func onboardingGlass<S: Shape>(interactive: Bool = true, in shape: S) -> some View {
        modifier(OnboardingGlassBackground(interactive: interactive, shape: shape))
    }
}

struct ButtonBar: View {
    let currentPage: OnboardingPage
    let nextEnabled: Bool
    let previousEnabled: Bool
    
    @Binding var termsAccepted: Bool
    @Binding var seedConfirmed: Bool
    
    let onPrevious: () -> Void
    let onNext: () -> Void

    private var showCenterButton: Bool {
        switch currentPage {
        case .terms, .seed: true
        default: false
        }
    }

    var body: some View {
        HStack {
            Image(systemName: "arrow.left")
                .font(.title)
                .padding()
                .contentShape(.capsule)
                .onTapGesture {
                    onPrevious()
                }
                .disabled(!previousEnabled)
                .opacity(previousEnabled ? 1 : 0.3)
                .onboardingGlass(interactive: previousEnabled, in: Circle())
                .animation(.default, value: previousEnabled)
            Spacer()

            if showCenterButton {
                centerButton
            }

            Spacer()
            Image(systemName: "arrow.right")
                .font(.title)
                .padding()
                .contentTransition(.symbolEffect(.replace))
                .contentShape(.capsule)
                .onTapGesture {
                    onNext()
                }
                .disabled(!nextEnabled)
                .opacity(nextEnabled ? 1 : 0.3)
                .onboardingGlass(interactive: nextEnabled, in: Circle())
                .animation(.default, value: nextEnabled)
        }
        .padding(24)
        .animation(.default, value: showCenterButton)
    }
    
    
    private var centerButton: some View {
        Group {
            switch currentPage {
            case .terms:
                HStack {
                    Image(systemName: termsAccepted ? "checkmark.square" : "square")
                        .contentTransition(.symbolEffect(.replace))
                        .font(.title3)
                    Text("I Agree")
                }
            case .seed:
                HStack {
                    Image(systemName: seedConfirmed ? "checkmark.square" : "square")
                        .contentTransition(.symbolEffect(.replace))
                        .font(.title3)
                    Text("I wrote it down")
                }
            default: EmptyView()
            }
        }
        .padding()
        .onboardingGlass(in: Capsule())
        .contentShape(.capsule)  // expands the hit target
        .onTapGesture {
            if currentPage == .terms { termsAccepted.toggle() } else { seedConfirmed.toggle() }
        }
        .transition(.blurReplace)
    }
}

struct ButtonBarPreview: View {
    @State private var sliderValue: Double = 0.0
    @State private var toggle = false

    @State private var termsAccepted: Bool = false

    var body: some View {
        ZStack {
            VStack {
                Slider(value: $sliderValue, in: 0...50)
                    .padding(.horizontal)
                Toggle(
                    isOn: Binding(
                        get: {
                            toggle
                        },
                        set: { newValue in
                            withAnimation {
                                toggle = newValue
                            }
                        }
                    )
                ) {
                    Text("Toggle")
                }
                .padding()
                .tint(.secondary)
                TermsPage(termsAccepted: $termsAccepted)
            }

            VStack {
                Spacer()
            }
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .background(.black.gradient)
    }
}

#Preview {
    ButtonBarPreview()
}

//#Preview {
//    ButtonBar()
//}
