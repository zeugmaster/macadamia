//
//  ButtonBar.swift
//  macadamia
//
//  Created by zm on 30.03.26.
//

import SwiftUI

@available(iOS 26.0, *)
struct ButtonBar: View {
    let nextEnabled: Bool
    
    @Binding var termsAccepted: Bool
    
    let showCenterButton: Bool
    
    var body: some View {
        HStack {
            Image(systemName: "arrow.left")
                .font(.title)
                .padding()
                .glassEffect(.clear.interactive(), in: .circle)
                .onTapGesture {
                    previous()
                }
            Spacer()
            Group {
                if showCenterButton {
                    HStack {
                        Image(systemName: termsAccepted ? "checkmark.square" : "square")
                            .contentTransition(.symbolEffect(.replace))
                            .font(.title3)
                        Text("Akzeptieren")
                    }
                    .padding()
                    .glassEffect(.clear.interactive())
                    .contentShape(.capsule) // expands the hit target
                    .onTapGesture {
                        termsAccepted.toggle()
                    }
                    .transition(.opacity)
                }
            }
            .animation(.default, value: showCenterButton)
                
            Spacer()
            Image(systemName: "arrow.right")
                .font(.title)
                .padding()
                .onTapGesture {
                    next()
                }
                .disabled(!nextEnabled)
                .opacity(nextEnabled ? 1 : 0.3)
                .glassEffect(.clear.interactive(nextEnabled), in: .circle)
                .animation(.default, value: nextEnabled)
        }
        .padding()
//        .animation(.spring(duration: 0.3, bounce: 0.3), value: showCenterButton)
    }
    
    
    private func next() {
        
    }
    
    private func previous() {
        
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
                    Toggle(isOn: $toggle) {
                        Text("Toggle")
                    }
                    .padding()
                    .tint(.secondary)
                    TermsPage(termsAccepted: .constant(false))
                }
                
                VStack {
                    Spacer()
                    ButtonBar(nextEnabled: termsAccepted,
                              termsAccepted: $termsAccepted,
                              showCenterButton: toggle)
//                        .padding(sliderValue)
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
