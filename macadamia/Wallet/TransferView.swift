//
//  PendingTransferView.swift
//  macadamia
//
//  Created by zm on 21.10.25.
//

import SwiftUI
import SwiftData
import CashuSwift

// FIXME: rename pending transfer view
struct TransferView: View {
    
    @State private var pendingTransferEvent: Event
    
    @State private var buttonState = ActionButtonState.idle("")
    
    @State private var currentSwapManager: InlineSwapManager?
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]
    
    @State private var showAlert = false
    @State private var currentAlert: AlertDetail?
    
    private var activeWallet: Wallet? {
        wallets.first
    }
    
    private var mints: [Mint] {
        activeWallet?.mints.filter({ $0.hidden == false })
            .sorted { ($0.userIndex ?? Int.max) < ($1.userIndex ?? Int.max) } ?? []
    }
    
    init(pendingTransferEvent: Event) {
        self._pendingTransferEvent = .init(initialValue: pendingTransferEvent)
    }
    
    private var transferMints: (from: Mint, to: Mint)? {
        pendingTransferEvent.transferMints
    }

    private enum RemoteStatus {
        case loading
        case state(CashuSwift.QuoteState)
        case unavailable
    }

    @State private var sourceStatus: RemoteStatus = .loading
    @State private var destinationStatus: RemoteStatus = .loading

    var body: some View {
        ZStack {
            List {
                if let transferMints {
                    Section {
                        TransferMintLabel(from: transferMints.from.displayName,
                                          to: transferMints.to.displayName)
                    }
                } else {
                    Text("One or both mints for this transfer could not be found.")
                }
                if let amount = pendingTransferEvent.amount {
                    Section {
                        AmountView(amount: amount, unit: pendingTransferEvent.currencyUnit)
                            .monospaced()
                    } header: {
                        Text("Amount")
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        statusRow(title: String(localized: "Payment"), status: sourceStatus, isMeltSide: true)
                        statusRow(title: String(localized: "Ecash issued"), status: destinationStatus, isMeltSide: false)
                        expiryRow
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                } header: {
                    Text("Status")
                }
            }
            VStack {
                Spacer(minLength: 50)
                ActionButton(state: $buttonState)
                    .actionDisabled(false)
            }
        }
        .onAppear {
            buttonState = .idle(String(localized: "Complete Transfer"), action: { complete() })
        }
        .task {
            await loadStatus()
        }
        .alertView(isPresented: $showAlert, currentAlert: currentAlert)
    }

    @ViewBuilder
    private func statusRow(title: String, status: RemoteStatus, isMeltSide: Bool) -> some View {
        HStack {
            Group {
                switch status {
                case .loading:
                    ProgressView()
                        .scaleEffect(0.7)
                case .state(let state):
                    switch state {
                    case .paid:
                        Image(systemName: isMeltSide ? "checkmark.circle.fill" : "hourglass")
                            .foregroundStyle(isMeltSide ? .green : .orange)
                    case .issued:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .pending:
                        Image(systemName: "hourglass")
                            .foregroundStyle(.orange)
                    case .unpaid:
                        Image(systemName: "circle")
                    }
                case .unavailable:
                    Image(systemName: "questionmark.circle")
                }
            }
            .frame(width: 20)
            Text(title)
            Spacer()
            Text(statusDescription(status, isMeltSide: isMeltSide))
        }
    }

    private func statusDescription(_ status: RemoteStatus, isMeltSide: Bool) -> String {
        switch status {
        case .loading:
            return ""
        case .unavailable:
            return String(localized: "Unknown")
        case .state(let state):
            switch (state, isMeltSide) {
            case (.paid, true):     return String(localized: "Paid")
            case (.paid, false):    return String(localized: "Payment received")
            case (.pending, true):  return String(localized: "In flight")
            case (.pending, false): return String(localized: "Processing")
            case (.unpaid, true):   return String(localized: "Unpaid")
            case (.unpaid, false):  return String(localized: "Awaiting payment")
            case (.issued, _):      return String(localized: "Issued")
            }
        }
    }

    @ViewBuilder
    private var expiryRow: some View {
        if let expiry = pendingTransferEvent.mintQuoteExpiry {
            HStack {
                Image(systemName: "clock")
                    .frame(width: 20)
                Text("Quote expires")
                Spacer()
                if expiry < Date() {
                    Text("expired — completing may fail")
                        .foregroundStyle(.red)
                } else {
                    Text(expiry, style: .relative)
                        .foregroundStyle(expiry.timeIntervalSinceNow < 900 ? .orange : .secondary)
                }
            }
        }
    }

    private func loadStatus() async {
        guard let (from, to) = transferMints else {
            sourceStatus = .unavailable
            destinationStatus = .unavailable
            return
        }

        let sendableFrom = CashuSwift.Mint(from)
        let sendableTo = CashuSwift.Mint(to)
        let mintQuote = pendingTransferEvent.mintQuote
        let meltQuote = pendingTransferEvent.bolt11MeltQuote

        if let mintQuote,
           let state = (try? await CashuSwift.Bolt11.mintQuoteState(mintQuote.quote, from: sendableTo))?.state {
            destinationStatus = .state(state)
        } else {
            destinationStatus = .unavailable
        }

        if let meltQuote,
           let state = (try? await CashuSwift.Bolt11.meltQuoteState(meltQuote.quote, from: sendableFrom))?.state {
            sourceStatus = .state(state)
        } else {
            sourceStatus = .unavailable
        }
    }

    private func complete() {

        currentSwapManager = InlineSwapManager(modelContext: modelContext, updateHandler: { state in
            switch state {
            case .ready:
                print("swap manager ready")
            case .loading:
                buttonState = .loading()
            case .melting:
                buttonState = .loading(String(localized: "Paying..."))
            case .minting:
                buttonState = .loading(String(localized: "Issuing Ecash"))
            case .success:
                buttonState = .success()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    dismiss()
                }
            case .pending(let message):
                buttonState = .idle(String(localized: "Check Again"), action: { complete() })
                displayAlert(alert: AlertDetail(title: String(localized: "Still Pending"),
                                                description: message))
                Task { await loadStatus() }
            case .fail(let error):
                buttonState = .fail()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    buttonState = .idle(String(localized: "Complete Transfer"), action: { complete() })
                }
                Task { await loadStatus() }

                switch error {
                case let transferError as TransferError:
                    switch transferError {
                    case .meltFailure(let meltError):
                        let primary = AlertButton(title: String(localized: "Remove Payment"),
                                                    role: .destructive,
                                                    action: { verifyAndRemoveEvent() })

                        displayAlert(alert: AlertDetail(title: String(localized: "Unpaid ⚠"),
                                                        description: String(localized: """
                                                        This payment did not go through: \(meltError.localizedDescription) \
                                                        The Ecash reserved for this operation can be made available again \
                                                        by removing the pending transfer event.
                                                        """),
                                                        primaryButton: primary))
                    case .missingData(let string):
                        displayAlert(alert: AlertDetail(title: String(localized: "Missing Data"), description: string))
                    default:
                        displayAlert(alert: AlertDetail(with: transferError))
                    }
                case let error?:
                    displayAlert(alert: AlertDetail(title: String(localized: "Error"), description: error.localizedDescription))
                case nil:
                    displayAlert(alert: AlertDetail(title: String(localized: "Something went wrong..."), description: String(localized: "No error provided.")))
                }
            }
        })

        currentSwapManager?.resumeTransfer(with: pendingTransferEvent)

    }

    /// Removes the pending transfer only after verifying with the mint that the
    /// payment is unpaid, and reverts only those inputs the mint confirms unspent.
    private func verifyAndRemoveEvent() {
        buttonState = .loading(String(localized: "Verifying..."))

        guard let (from, _) = transferMints else {
            buttonState = .idle(String(localized: "Complete Transfer"), action: { complete() })
            displayAlert(alert: AlertDetail(title: String(localized: "Cannot Remove"),
                                            description: String(localized: "The mints for this transfer could not be found.")))
            return
        }

        let sendableFrom = CashuSwift.Mint(from)
        let meltQuote = pendingTransferEvent.bolt11MeltQuote
        let proofs = pendingTransferEvent.proofs ?? []

        Task {
            if let meltQuote {
                let state = (try? await CashuSwift.Bolt11.meltQuoteState(meltQuote.quote, from: sendableFrom))?.state
                guard state == .unpaid else {
                    buttonState = .idle(String(localized: "Complete Transfer"), action: { complete() })
                    displayAlert(alert: AlertDetail(title: String(localized: "Cannot Remove"),
                                                    description: String(localized: """
                                                    The payment could not be verified as unpaid. Removing it now \
                                                    could lose funds — try completing the transfer instead.
                                                    """)))
                    return
                }
            }

            if !proofs.isEmpty {
                guard let states = try? await CashuSwift.check(proofs.sendable(), mint: sendableFrom),
                      states.count == proofs.count else {
                    buttonState = .idle(String(localized: "Complete Transfer"), action: { complete() })
                    displayAlert(alert: AlertDetail(title: String(localized: "Cannot Remove"),
                                                    description: String(localized: "The state of the reserved ecash could not be checked with the mint. Try again later.")))
                    return
                }
                for (proof, state) in zip(proofs, states) {
                    proof.state = (state == .unspent) ? .valid : .spent
                }
            }

            pendingTransferEvent.visible = false
            try? modelContext.save()
            dismiss()
        }
    }

    private func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}

struct TransferMintLabel: View {
    let from:   String
    let to:     String
    
    var body: some View {
        Group {
            VStack(alignment: .leading) {
                HStack {
                    VStack(alignment: .leading) {
                        Text("From")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text(from)
                    }
                    Spacer()
                }
                LinearGradient(colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.3), Color.clear],
                               startPoint: .leading,
                               endPoint: .trailing)
                .frame(height: 0.5)
                .padding(.vertical, 4)
                HStack {
                    VStack(alignment: .leading) {
                        Text("To")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text(to)
                    }
                }
            }
        }
        .overlay(alignment: .trailing) {
            Image(systemName: "arrow.down")
                .font(.title2)
                .foregroundStyle(.primary)
                .padding(6)
                .background(Circle().fill(.secondary.opacity(0.4)))
        }
        .padding(EdgeInsets(top: 12, leading: 18, bottom: 12, trailing: 18))
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(Color(uiColor: .secondarySystemGroupedBackground)))
        .listRowBackground(EmptyView())
        .listRowInsets(EdgeInsets())
    }
}

#Preview(body: {
    TransferMintLabel(from: "one", to: "two")
})
