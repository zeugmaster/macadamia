//
//  DepositQuoteRequestView.swift
//  macadamia
//
//  Created by zm on 15.09.26.
//

import SwiftUI
import CashuSwift

struct DepositQuoteRequestView: View {
    
    let paymentMethod: CashuSwift.Mint.Info.PaymentMethod
    
    var body: some View {
        Text(/*@START_MENU_TOKEN@*/"Hello, World!"/*@END_MENU_TOKEN@*/)
        
        // validate input 
    }
}

struct HourglassProgressView: View {
    enum Status {
        case waiting, success, failure
    }
    
    let status: Status
    
    @Environment(\.scenePhase) private var scenePhase
    @State private var rotation = 0.0
    
    private var shouldRotate: Bool {
        switch (status, scenePhase) {
        case (.waiting, .active): true
        default: false
        }
    }
    
    private var symbol: String {
        switch status {
        case .waiting: "hourglass.bottomhalf.filled"
        case .success: "checkmark"
        case .failure: "xmark"
        }
    }
    
    var body: some View {
        Image(systemName: symbol)
            .contentTransition(.symbolEffect)
            .frame(width: 32, height: 32)
            .animation(shouldRotate ? .easeInOut(duration: 0.5) : nil) { content in
                content.rotationEffect(.degrees(shouldRotate ? rotation : 0))
            }
            .task(id: shouldRotate) {
                var reset = Transaction(animation: nil)
                reset.disablesAnimations = true
                withTransaction(reset) {
                    rotation = 0
                }
                guard shouldRotate else { return }
                do {
                    while !Task.isCancelled {
                        try await Task.sleep(for: .seconds(2))
                        try Task.checkCancellation()
                        rotation += 360
                    }
                } catch {
                    
                }
            }
    }
}

#Preview("Hourglass Progress View") {
    @Previewable @State var status: HourglassProgressView.Status = .waiting
    HourglassProgressView(status: status)
    Picker("State", selection: $status) {
        Text("waiting").tag(HourglassProgressView.Status.waiting)
        Text("success").tag(HourglassProgressView.Status.success)
        Text("failure").tag(HourglassProgressView.Status.failure)
    }
    .pickerStyle(.segmented)
    .padding()
    .padding()
}
