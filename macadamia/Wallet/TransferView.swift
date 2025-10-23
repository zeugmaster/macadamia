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
        guard let mints = pendingTransferEvent.mints,
              mints.count >= 2
        else { return nil }

        return (mints[0], mints[1])
    }

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
                        Text("\(String(amount)) \(pendingTransferEvent.unit.rawValue)")
                            .monospaced()
                    } header: {
                        Text("Amount")
                    }
                }
                
                Section {
                    VStack(alignment: .leading) {
                        HStack {
                            Image(systemName: pendingTransferEvent.bolt11MeltQuote == nil ? "xmark" : "checkmark")
                                .frame(width: 20)
                            Text("Payment Quote")
                        }
                        HStack {
                            Image(systemName: pendingTransferEvent.bolt11MintQuote == nil ? "xmark" : "checkmark")
                                .frame(width: 20)
                            Text("Ecash Quote")
                        }
                        HStack {
                            Image(systemName: pendingTransferEvent.proofs == nil || pendingTransferEvent.proofs?.isEmpty ?? true ? "xmark" : "checkmark")
                                .frame(width: 20)
                            Text("Ecash selected")
                        }
                        HStack {
                            Image(systemName: pendingTransferEvent.blankOutputs == nil ? "xmark" : "checkmark")
                                .frame(width: 20)
                            Text("Change created")
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }
            VStack {
                Spacer(minLength: 50)
                ActionButton(state: $buttonState)
                    .actionDisabled(false)
            }
        }
        .onAppear {
            buttonState = .idle("Complete Transfer", action: { complete() })
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
                buttonState = .loading("Paying...")
            case .minting:
                buttonState = .loading("Issuing Ecash")
            case .success:
                buttonState = .success()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    dismiss()
                }
            case .fail(let error):
                buttonState = .fail()
                
                switch error {
                case let .meltFailure(meltError) as InlineSwapManager.TransferError:
                    
                    let primary = AlertButton(title: "Remove Payment",
                                                role: .destructive,
                                                action: { removeEvent() })
                    
                    displayAlert(alert: AlertDetail(title: "Unpaid ⚠",
                                                    description: "This payment did not go through and one or more parts are marked \"unpaid\". The Ecash reserved for this operation is still valid and can be made available by removing the pending transfer event.",
                                                    primaryButton: primary))
                    
                
                case let .missingData(string) as InlineSwapManager.TransferError:
                    displayAlert(alert: AlertDetail(title: "Missing Data", description: string))
                case let error?:
                    displayAlert(alert: AlertDetail(title: "Error", description: error.localizedDescription))
                case nil:
                    displayAlert(alert: AlertDetail(title: "Something went wrong...", description: "No error provided."))
                }
            }
        })
        
        currentSwapManager?.resumeTransfer(with: pendingTransferEvent)
        
    }
    
    private func removeEvent() {
        pendingTransferEvent.proofs?.setState(.valid)
        pendingTransferEvent.proofs = nil
        pendingTransferEvent.visible = false
        dismiss()
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
