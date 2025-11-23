//
//  RequestView.swift
//  macadamia
//
//  Created by zm on 23.11.25.
//

import SwiftUI
import SwiftData
import CashuSwift

struct RequestView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var nostrService: NostrService
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]
    
    @State private var paymentRequest: CashuSwift.PaymentRequest?
    @State private var amount: Int = 0
    
    @State private var selectedMints = Set<Mint>()
    @State private var showMintSelector = false
    @State private var useNIP17Transport = false
    
    @Query private var allProofs:[Proof]
    @State private var showAlert: Bool = false
    @State private var currentAlert: AlertDetail?
    
    private var mintsInUse: [Mint] {
        if let activeWallet {
            return activeWallet.mints.filter({ !$0.hidden })
                                     .sorted { ($0.userIndex ?? 0) < ($1.userIndex ?? 0) }
        } else {
            return []
        }
    }
    
    private var activeWallet: Wallet? {
        wallets.first
    }
    
    private var doneButtonDisabled: Bool {
        false
    }
    
    var body: some View {
        List {
            Section {
                NumericalInputView(output: $amount,
                                   baseUnit: .sat,
                                   exchangeRates: appState.exchangeRates) {
                    
                }
            }
            
            if let paymentRequest, let string = try? paymentRequest.serialize() {
                Section {
                    StaticQRView(string: string)
                } footer: {
                    Text(paymentRequest.paymentId ?? "No ID")
                }
            } else {
                mintSelectorSection
                
                Section {
                    Button {
                        withAnimation {
                            useNIP17Transport.toggle()
                        }
                    } label: {
                        HStack {
                            Image(systemName: useNIP17Transport ? "checkmark.circle.fill" : "circle")
                            VStack(alignment: .leading) {
                                Text("Nostr DM")
                                Text((try? NostrKeychain.getNpub()) ?? "Unable to get NPUB")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .lineLimit(1)
                        }
                    }
                } header: {
                    Text("Receive via")
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    generatePaymentRequest()
                }) {
                    Text("Done")
                }
                .disabled(doneButtonDisabled)
                .opacity(paymentRequest == nil ? 1 : 0)
            }
        }
        .navigationTitle("Payment Request")
        .alertView(isPresented: $showAlert, currentAlert: currentAlert)
    }
    
    private var mintSelectorSection: some View {
        Section {
            
            Button {
                withAnimation {
                    showMintSelector.toggle()
                }
            } label: {
                HStack {
                    if selectedMints.isEmpty {
                        Text("Any mint")
                    } else {
                        Text("\(selectedMints.count) mint\(selectedMints.count > 1 ? "s" : "")")
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                        .font(.footnote)
                        .rotationEffect(.degrees(showMintSelector ? 90 : 0))
                }
            }
            
            if showMintSelector {
                ForEach(mintsInUse) { mint in
                    Button {
                        if selectedMints.contains(mint) {
                            selectedMints.remove(mint)
                        } else {
                            selectedMints.insert(mint)
                        }
                    } label: {
                        HStack {
                            Image(systemName: selectedMints.contains(mint) ? "checkmark.circle.fill" : "circle")
                            Text(mint.displayName)
                        }
                    }
                }
            }
        } header: {
            HStack {
                Text("Request from")
                Spacer()
                Button {
                    if mintsInUse.count == selectedMints.count {
                        selectedMints.removeAll()
                    } else {
                        selectedMints = Set(mintsInUse)
                    }
                } label: {
                    if mintsInUse.count == selectedMints.count {
                        Text("Deselect")
                    } else {
                        Text("Select All")
                    }
                }
            }
        }
    }
    
    private func generatePaymentRequest() {
        
    }
    
    private func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}

#Preview {
    RequestView()
}
