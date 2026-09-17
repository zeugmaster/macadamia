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
    @State private var showDetails = false
    @State private var hourglassStatus: HourglassProgressView.Status = .waiting
    
    var body: some View {
        List {
            Section {
                    if let amount = quote.amount {
                        HStack {
                            Text("Amount:")
                            Spacer()
                            Text(amountDisplayString(amount, unit: quote.unit))
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fontWeight(.semibold)
                        .listRowSeparator(.hidden)
                    }
                Group {
                    switch paymentMethodKind {
                    case .bolt11, .bolt12, .onchain:
                        QRView(string: quote.request)
                    case .generic:
                        QRView(string: quote.quoteID)
                    }
                }
                .listRowInsets(EdgeInsets(top: quote.amount == nil ? 16 : 0,
                                          leading: 16,
                                          bottom: 16,
                                          trailing: 16))
                if quote.paymentMethodKind != .generic {
                    Button {
                        if copied { return }
                            UIPasteboard.general.string = quote.request
                        withAnimation {
                            copied = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation {
                                copied = false
                            }
                        }
                    } label: {
                        HStack {
                            Text(quote.request)
                                .lineLimit(1)
                            Image(systemName: copied ? "clipboard.fill" : "clipboard")
                        }
                    }
                    .listRowSeparator(.hidden)
                }
                HStack {
                    Text("Quote ID")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Spacer()
                    Text(quote.quoteID)
                        .lineLimit(1)
                        .font(.caption)
                        .monospaced()
                        .foregroundStyle(.secondary)
                }
                .contextMenu {
                    Button(action: {
                        UIPasteboard.general.string = quote.quoteID
                    }) {
                        Text("Copy Quote ID")
                        Image(systemName: "doc.on.clipboard")
                    }
                }
                .onTapGesture(count: 2) {
                    UIPasteboard.general.string = quote.quoteID
                }
            } header: {
                switch quote.paymentMethodKind {
                case .bolt11: Text("Invoice")
                case .bolt12: Text("Offer")
                case .onchain: Text("Address")
                case .generic: Text("Quote")
                }
            }
            Section {
                
            }
            
        }
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
