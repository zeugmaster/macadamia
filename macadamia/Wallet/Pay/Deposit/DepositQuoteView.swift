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
    
    var body: some View {
        ZStack {
            // Style with quote.request, quote.amount, quote.unit, quote.expiry,
            // quote.mint, quote.amountPaid and quote.amountIssued.
            
            VStack {
                Spacer()
                ActionButton(state: $actionButtonState, hideShadow: true)
            }
        }
        .navigationTitle("\(quote.paymentMethodName) Deposit")
        .navigationBarTitleDisplayMode(.inline)
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
