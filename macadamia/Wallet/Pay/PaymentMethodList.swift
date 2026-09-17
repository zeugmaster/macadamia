//
//  PaymentMethodList.swift
//  macadamia
//
//  Created by zm on 15.09.26.
//

import SwiftUI
import SwiftData
import CashuSwift

struct PaymentMethodList: View {
    let paymentDirection: PaymentDirection
    let paymentMethods: [CashuSwift.Mint.Info.PaymentMethod]

    @Query private var mints: [Mint]
    @Query(filter: #Predicate<Wallet> { $0.active }) private var wallets: [Wallet]
    @State private var supportingMintIDs: [CashuSwift.PaymentMethodID: Set<UUID>] = [:]

    private var visibleMints: [Mint] {
        guard let wallet = wallets.first else { return [] }
        return mints.filter { $0.wallet == wallet && !$0.hidden }
    }

    private var uniquePaymentMethods: [CashuSwift.Mint.Info.PaymentMethod] {
        var seen = Set<CashuSwift.PaymentMethodID>()
        return paymentMethods.filter { seen.insert($0.method).inserted }
    }

    var body: some View {
        List {
            ForEach(uniquePaymentMethods, id: \.method) { method in
                NavigationLink(destination: {
                    // FIXME: assuming deposit payment direction
                    DepositQuoteRequestView(paymentMethod: method)
                }, label: {
                    PaymentMethodCard(name: name(for: method),
                                      icon: Image(systemName: imageSystemName(for: method)),
                                      description: description(for: method),
                                      numberOfSupportingMints: numberOfMints(for: method))
                        
                })
                .navigationLinkIndicatorVisibility(.hidden)
                .listRowBackground(EmptyView())
                .listRowSeparator(.hidden)
            }
        }
        .navigationTitle("Select Method")
        .listStyle(.plain)
        .task(id: visibleMints.map(\.mintID)) {
            await refreshMintSupport()
        }
    }

    private func imageSystemName(for method: CashuSwift.Mint.Info.PaymentMethod) -> String {
        switch method.method {
        case "bolt11", "bolt12": "bolt.fill"
        case "onchain": "link"
        default: "arrow.down.to.line.compact"
        }
    }

    private func name(for method: CashuSwift.Mint.Info.PaymentMethod) -> String {
        method.methodName ?? method.displayName
    }

    private func description(for method: CashuSwift.Mint.Info.PaymentMethod) -> LocalizedStringKey {
        switch method.method.kind {
        case .bolt11:
            "Deposit by paying a Bolt11 invoice"
        case .bolt12:
            "Pay to a reusable Bolt12 offer"
        case .onchain:
            "Make an on-chain Bitcoin payment"
        case .generic:
            "Create a generic deposit quote for this payment method"
        }
    }

    private func numberOfMints(for method: CashuSwift.Mint.Info.PaymentMethod) -> Int {
        supportingMintIDs[method.method]?.count ?? 0
    }

    @MainActor
    private func refreshMintSupport() async {
        supportingMintIDs = [:]
        var supportedIDs: [CashuSwift.PaymentMethodID: Set<UUID>] = [:]
        for mint in visibleMints {
            // Payment methods are assumed to be available in both directions.
            let options = await mint.supportedPaymentOptions(direction: .deposit)
            guard !Task.isCancelled else { return }
            for option in options {
                supportedIDs[option.method, default: []].insert(mint.mintID)
            }
        }
        supportingMintIDs = supportedIDs
    }
}

struct PaymentMethodCard: View {
    let name: String
    let icon: Image
    let description: LocalizedStringKey
    let numberOfSupportingMints: Int

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                icon
                Text(name)
                    .bold()
                Spacer()
                HStack(alignment: .center, spacing: 2) {
                    Text(String(numberOfSupportingMints))
                        .font(.callout)
                    Image(systemName: "building.columns")
                        .font(.caption)
                }
                .fontWeight(.regular)
                .padding(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                .opacity(0.8)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.primary.opacity(0.1))
                        .stroke(.primary.opacity(0.1))
                }
            }
            Text(description)
                .font(.callout)
                .padding(.top)
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.primary.opacity(0.05))
                .stroke(.primary.opacity(0.2), lineWidth: 0.5)
        }
    }
}

#if DEBUG

#Preview("List") {
    NavigationStack {
        PaymentMethodList(paymentDirection: PaymentDirection.deposit
                          ,paymentMethods: [
            .init(method: .bolt11, unit: "sat"),
            .init(method: .bolt11, unit: "usd"),
            .init(method: .bolt12, unit: "sat"),
            .init(method: "onchain", unit: "sat"),
            .init(method: "branch", unit: "bux", methodName: "Branch")
        ])
    }
    .previewEnvironment()
}
#endif
