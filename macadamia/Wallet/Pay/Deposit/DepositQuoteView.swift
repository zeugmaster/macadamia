//
//  DepositView.swift
//  macadamia
//
//  Created by zm on 15.09.26.
//

import SwiftUI
import CashuSwift

/// In-memory quote and the context needed to display and later redeem it.
struct DepositQuote: Identifiable, Hashable {
    let id = UUID()
    let response: any CashuSwift.MintQuoteResponse
    let mint: Mint
    let option: PaymentOption
    let requestedAmount: Int?
    let lockingKeyCounter: UInt32?

    var quoteID: String { response.quote }
    var request: String { response.request }
    var method: CashuSwift.PaymentMethodID { response.method }
    var paymentMethodKind: PaymentMethodKind { method.kind }
    var paymentMethodName: String { option.methodDisplayName }
    var unit: Unit { Unit(code: response.unit) }
    var amount: Int? { response.amount ?? requestedAmount }
    var expiry: Date? { response.expiry.map { Date(timeIntervalSince1970: TimeInterval($0)) } }

    /// The generic transport preserves method-specific fields such as accounting.
    var raw: CashuSwift.JSONObject? { (response as? CashuSwift.Generic.MintQuote)?.raw }
    var amountPaid: Int? { integerField("amount_paid") }
    var amountIssued: Int? { integerField("amount_issued") }

    private func integerField(_ name: String) -> Int? {
        guard case .integer(let value) = raw?[name] else { return nil }
        return Int(exactly: value)
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct DepositQuoteView: View {
    
    let quote: DepositQuote

    private var paymentMethodKind: PaymentMethodKind { quote.paymentMethodKind }
    
    @State private var actionButtonState: ActionButtonState = .idle("")
    
    @State private var copied = false
    @State private var hourglassStatus: HourglassProgressView.Status = .waiting
    
    var body: some View {
        VStack {
            VStack(alignment: .leading) {
                switch paymentMethodKind {
                case .bolt11, .bolt12, .onchain:
                    QRView(string: quote.request)
                case .generic:
                    QRView(string: quote.quoteID)
                }
                Spacer().frame(height: 20)
                HStack(alignment: .center) {
                    Text(quote.quoteID)
                        .foregroundStyle(.secondary)
                        .monospaced()
                        .bold()
                        .lineLimit(1)
                        .truncationMode(.head)
                        .padding(8)
                    Spacer()
                    Button {
                        if copied { return }
//                        UIPasteboard.general.string = quote.joined(separator: " ")
                        withAnimation {
                            copied = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation {
                                copied = false
                            }
                        }
                    } label: {
                            Image(systemName: copied ? "clipboard.fill" : "clipboard")
                            .font(.callout)
                            .padding(8)
                            .background {
                                HStack {
                                    Rectangle()
                                        .frame(width: 1)
                                        .foregroundStyle(.background.opacity(0.7))
                                    Spacer()
                                }
                            }
                    }
                }
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.secondary.opacity(0.2))
                }
                .font(.footnote)
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.primary.opacity(0.07))
                    .stroke(.primary.opacity(0.2), lineWidth: 0.5)
            }
            HStack {
                Spacer()
                HourglassProgressView(status: hourglassStatus)
                Group {
                    switch hourglassStatus {
                    case .waiting:
                        Text("Waiting for payment")
                    case .success:
                        Text("Payment received!")
                    case .failure:
                        Text("Error")
                    }
                }
//                .fontWeight(.semibold)
                Spacer()
            }
            .padding(10)
            .foregroundStyle(.secondary)
//            .background {
//                RoundedRectangle(cornerRadius: 20)
//                    .fill(.primary.opacity(0.07))
//                    .stroke(.primary.opacity(0.2), lineWidth: 0.5)
//            }
            Spacer()
        }
        .padding()
        .navigationTitle("\(quote.paymentMethodName) Deposit")
        .navigationBarTitleDisplayMode(.inline)
    }
    
//    private var qrContent: String {
//        switch quote.paymentMethodKind {
//        case .
//        }
//    }
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

#if DEBUG
#Preview("BOLT11") {
    NavigationStack {
        DepositQuoteView(quote: DepositQuotePreview.bolt11)
    }
    .previewEnvironment()
}

#Preview("BOLT12 · Amountless") {
    NavigationStack {
        DepositQuoteView(quote: DepositQuotePreview.bolt12)
    }
    .previewEnvironment()
}

#Preview("On-chain") {
    NavigationStack {
        DepositQuoteView(quote: DepositQuotePreview.onchain)
    }
    .previewEnvironment()
}

#Preview("Generic") {
    NavigationStack {
        DepositQuoteView(quote: DepositQuotePreview.generic)
    }
    .previewEnvironment()
}
#endif
