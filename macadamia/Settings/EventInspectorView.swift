import SwiftUI
import CashuSwift

struct EventInspectorView: View {

    let wallet: Wallet

    private var events: [Event] {
        wallet.events.sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            Section(content: {
                ForEach(events) { event in
                    NavigationLink {
                        EventDataView(event: event)
                    } label: {
                        VStack(alignment: .leading) {
                            HStack {
                                Text(String(describing: event.kind))
                                    .bold()
                                if !event.visible {
                                    Text("hidden")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let amount = event.amount {
                                    Text("\(amount) \(event.currencyUnit.currencyCode)")
                                        .monospaced()
                                }
                            }
                            HStack {
                                Text(event.shortDescription)
                                Spacer()
                                Text(event.date.formatted(date: .numeric, time: .shortened))
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }, header: {
                HStack {
                    Text("Including hidden")
                    Spacer()
                    Text(String(localized: "\(events.count) objects"))
                }
            })
        }
        .navigationTitle("Event Database")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct EventDataView: View {

    var event: Event

    var body: some View {
        List {
            Section("Basic Information") {
                CopyableRow(label: "Event ID", value: event.eventID.uuidString)
                CopyableRow(label: "Kind", value: String(describing: event.kind))
                CopyableRow(label: "Date", value: event.date.formatted())
                CopyableRow(label: "Unit", value: event.currencyUnit.currencyCode)
                if let amount = event.amount {
                    CopyableRow(label: "Amount", value: String(amount), concealValue: true)
                }
                CopyableRow(label: "Visible", value: event.visible ? "true" : "false")
                CopyableRow(label: "Short Description", value: event.shortDescription)
                if let longDescription = event.longDescription {
                    CopyableRow(label: "Long Description", value: longDescription)
                }
                if let memo = event.memo, !memo.isEmpty {
                    CopyableRow(label: "Memo", value: memo)
                }
                if let redeemed = event.redeemed {
                    CopyableRow(label: "Redeemed", value: redeemed ? "true" : "false")
                }
                if let expiration = event.expiration {
                    CopyableRow(label: "Expiration", value: expiration.formatted())
                }
                if let groupingID = event.groupingID {
                    CopyableRow(label: "Grouping ID", value: groupingID.uuidString)
                }
            }

            if let mintQuote = event.mintQuote {
                Section("Mint Quote") {
                    CopyableRow(label: "Quote ID", value: mintQuote.quote)
                    if let state = mintQuote.state {
                        CopyableRow(label: "State", value: state.rawValue)
                    }
                    if let amount = mintQuote.amount {
                        CopyableRow(label: "Amount", value: "\(amount) \(mintQuote.unit)")
                    }
                    CopyableRow(label: "Payment Request", value: mintQuote.request)
                    if let expiry = mintQuote.expiry {
                        CopyableRow(label: "Expiry",
                                    value: Date(timeIntervalSince1970: TimeInterval(expiry)).formatted())
                    }
                }
            }

            if let genericQuote = event.genericMintQuote {
                Section("Mint Quote") {
                    CopyableRow(label: "Quote ID", value: genericQuote.quote)
                    CopyableRow(label: "Method", value: genericQuote.method.rawValue)
                    if let state = genericQuote.state {
                        CopyableRow(label: "State", value: state.rawValue)
                    }
                    if let amount = genericQuote.amount {
                        CopyableRow(label: "Amount", value: "\(amount) \(genericQuote.unit)")
                    }
                    if let amountPaid = genericQuote.amountPaid {
                        CopyableRow(label: "Amount Paid", value: String(amountPaid))
                    }
                    if let amountIssued = genericQuote.amountIssued {
                        CopyableRow(label: "Amount Issued", value: String(amountIssued))
                    }
                    CopyableRow(label: "Payment Request", value: genericQuote.request)
                    if let counter = genericQuote.nut20Counter {
                        CopyableRow(label: "NUT-20 Counter", value: String(counter))
                    }
                    if let expiry = genericQuote.expiry {
                        CopyableRow(label: "Expiry",
                                    value: Date(timeIntervalSince1970: TimeInterval(expiry)).formatted())
                    }
                }
            }

            if let meltQuote = event.bolt11MeltQuote {
                Section("Melt Quote") {
                    CopyableRow(label: "Quote ID", value: meltQuote.quote)
                    if let state = meltQuote.state {
                        CopyableRow(label: "State", value: state.rawValue)
                    }
                    CopyableRow(label: "Amount", value: "\(meltQuote.amount) \(meltQuote.unit)")
                    CopyableRow(label: "Fee Reserve", value: String(meltQuote.feeReserve))
                    if let request = meltQuote.request {
                        CopyableRow(label: "Payment Request", value: request)
                    }
                    if let expiry = meltQuote.expiry {
                        CopyableRow(label: "Expiry",
                                    value: Date(timeIntervalSince1970: TimeInterval(expiry)).formatted())
                    }
                    if let preimage = meltQuote.paymentPreimage, !preimage.isEmpty {
                        CopyableRow(label: "Payment Preimage", value: preimage)
                    }
                }
            }

            if let genericQuote = event.genericMeltQuote {
                Section("Melt Quote") {
                    CopyableRow(label: "Quote ID", value: genericQuote.quote)
                    CopyableRow(label: "Method", value: genericQuote.method.rawValue)
                    if let state = genericQuote.rawStateString {
                        CopyableRow(label: "State", value: state)
                    }
                    CopyableRow(label: "Amount", value: "\(genericQuote.amount) \(genericQuote.unit)")
                    CopyableRow(label: "Fee Reserve", value: String(genericQuote.feeReserve))
                    if let expiry = genericQuote.expiry {
                        CopyableRow(label: "Expiry",
                                    value: Date(timeIntervalSince1970: TimeInterval(expiry)).formatted())
                    }
                    if let preimage = genericQuote.paymentPreimage, !preimage.isEmpty {
                        CopyableRow(label: "Payment Note", value: preimage)
                    }
                }
            }

            if let preImage = event.preImage, !preImage.isEmpty {
                Section("Payment") {
                    CopyableRow(label: "Preimage", value: preImage)
                }
            }

            if let token = event.token {
                Section("Token") {
                    CopyableRow(label: "Sum", value: String(token.sum()), concealValue: true)
                    CopyableRow(label: "Serialized (V4)",
                                value: (try? token.serialize(to: .V4)) ?? "Could not serialize token.")
                }
            }

            if let blankOutputs = event.blankOutputs {
                Section("Blank Outputs (NUT-08)") {
                    CopyableRow(label: "Count", value: String(blankOutputs.outputs.count))
                }
            }

            if let mints = event.mints, !mints.isEmpty {
                Section("Mints") {
                    ForEach(mints) { mint in
                        CopyableRow(label: mint.displayName, value: mint.url.absoluteString)
                    }
                }
            }

            if event.fromMint != nil || event.toMint != nil {
                Section("Transfer Endpoints") {
                    if let from = event.fromMint {
                        CopyableRow(label: "From", value: from.url.absoluteString)
                    }
                    if let to = event.toMint {
                        CopyableRow(label: "To", value: to.url.absoluteString)
                    }
                }
            }

            if let proofs = event.proofs, !proofs.isEmpty {
                Section("Associated Proofs") {
                    CopyableRow(label: "Count", value: String(proofs.count))
                    CopyableRow(label: "Sum", value: String(proofs.sum), concealValue: true)
                }
            }

            if let wallet = event.wallet {
                Section("Wallet") {
                    CopyableRow(label: wallet.name ?? "Unnamed Wallet",
                                value: wallet.walletID.uuidString)
                }
            }
        }
        .navigationTitle("Event Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}
