//
//  ButtonBar.swift
//  macadamia
//
//  Created by zm on 30.03.26.
//

import SwiftUI

@available(iOS 26.0, *)
struct ButtonBar: View {
    let currentPage: OnboardingPage
    
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

    private var nextEnabled: Bool {
        switch currentPage {
        case .terms: termsAccepted
        case .seed: seedConfirmed
        default: true
        }
    }

    private var previousEnabled: Bool {
        switch currentPage {
        case .welcome, .setup: false
        default: true
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
                .glassEffect(.clear.interactive(previousEnabled), in: .circle)
                .animation(.default, value: previousEnabled)
            Spacer()

            if showCenterButton {
                centerButton
            }

            Spacer()
            Image(systemName: currentPage == .success ? "checkmark" : "arrow.right")
                .font(.title)
                .padding()
                .contentTransition(.symbolEffect(.replace))
                .contentShape(.capsule)
                .onTapGesture {
                    onNext()
                }
                .disabled(!nextEnabled)
                .opacity(nextEnabled ? 1 : 0.3)
                .glassEffect(.clear.interactive(nextEnabled), in: .circle)
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
        .glassEffect(.clear.interactive())
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
        if #available(iOS 26.0, *) {
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
                    //                    ButtonBar(previousEnabled: true,
                    //                              nextEnabled: termsAccepted,
                    //                              termsAccepted: $termsAccepted,
                    //                              showCenterButton: toggle)
                }
            }
            .ignoresSafeArea(.container, edges: .bottom)
            .background(.black.gradient)
        } else {
            Text("unavailable")
        }
    }
}

#Preview {
    ButtonBarPreview()
}

//#Preview {
//    ButtonBar()
//}
