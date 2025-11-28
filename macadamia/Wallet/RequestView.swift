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
    @State private var useNIP17Transport = true
    @State private var useP2PK = false
    @State private var description = ""
    @State private var copied = false
    
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
        
        // Disable if NIP-17 is selected but no Nostr key is available
        if useNIP17Transport && !NostrKeychain.hasNsec() {
            return true
        }
        
        return false
    }
    
    var body: some View {
        List {
            Section {
                NumericalInputView(output: $amount,
                                   baseUnit: .sat,
                                   exchangeRates: appState.exchangeRates) {}
                                   .disabled(paymentRequest != nil)
            }
            
            if let paymentRequest, let string = try? paymentRequest.serialize() {
                Section {
                    StaticQRView(string: string)
                    Button {
                        UIPasteboard.general.string = string
                        withAnimation {
                            copied = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            withAnimation {
                                copied = false
                            }
                        }
                    } label: {
                        HStack {
                            Text(copied ? "Copied!" : "Copy to clipboad")
                            Spacer()
                            Image(systemName: copied ? "clipboard.fill" : "clipboard")
                        }
                    }
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
                                Text((try? NostrKeychain.getNprofile(relays: nil)) ?? "Unable to get key")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .lineLimit(1)
                        }
                    }
                } header: {
                    Text("Receive via")
                }
                
                if let publicKeyString = activeWallet?.publicKeyString {
                    Section {
                        Button {
                            useP2PK.toggle()
                        } label: {
                            HStack {
                                Image(systemName: useP2PK ? "checkmark.circle.fill" : "circle")
                                VStack(alignment: .leading) {
                                    Text("P2PK")
                                    Text(publicKeyString)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .lineLimit(1)
                                Spacer()
                                Image(systemName: "lock")
                            }
                        }
                    } header: {
                        Text("Lock to wallet key")
                    }
                }
                
                Section {
                    TextField("", text: $description, prompt: Text("Optional description..."))
                }
            }
        }
        .toolbar {
            if paymentRequest == nil {
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
        
        // Convert selected mints to URL strings
        let mintURLs: [String]? = selectedMints.isEmpty ? nil : selectedMints.map { $0.url.absoluteString }
        
        // Create transports array if NIP-17 is enabled
        var transports: [CashuSwift.Transport]? = nil
        if useNIP17Transport {
            do {
                // Use nprofile format with relay hints so sender knows where to publish
                let relayStrings = defaultRelayURLs.map { $0.absoluteString }
                let nprofile = try NostrKeychain.getNprofile(relays: relayStrings)
                let nostrTransport = CashuSwift.Transport(type: CashuSwift.Transport.TransportType.nostr, target: nprofile)
                transports = [nostrTransport]
            } catch {
                displayAlert(alert: AlertDetail(title: "⚠️ Nostr Key Error", description: "Failed to get your Nostr public key: \(error.localizedDescription)"))
                return
            }
        }
        
        // Extract complex expressions to help type inference
        let requestAmount: Int? = amount > 0 ? amount : nil
        let requestDescription: String? = description.isEmpty ? nil : description
        
        // Create NUT-10 locking condition if P2PK is enabled and we have a public key
        let lockingCondition: CashuSwift.NUT10Option?
        if useP2PK, let publicKeyString = activeWallet?.publicKeyString {
            lockingCondition = CashuSwift.NUT10Option(kind: CashuSwift.NUT10Option.Kind.p2pk,
                                                      data: publicKeyString,
                                                      tags: nil)
        } else {
            lockingCondition = nil
        }
        
        let request = CashuSwift.PaymentRequest(paymentId: createPaymentRequestIdentifier(),
                                                amount: requestAmount,
                                                unit: "sat",
                                                singleUse: false,
                                                mints: mintURLs,
                                                description: requestDescription,
                                                transports: transports,
                                                lockingCondition: lockingCondition)
        
        withAnimation {
            paymentRequest = request
        }
        
    }

    func createPaymentRequestIdentifier() -> String {
        let uuid = UUID().uuidString.lowercased()
        if let firstComponent = uuid.components(separatedBy: "-").first {
            return firstComponent
        }
        return ""
    }
    
    private func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}

#Preview {
    RequestView()
}
