//
//  RequestView.swift
//  macadamia
//
//  Created by zm on 23.11.25.
//

import SwiftUI
import SwiftData
import CashuSwift
import NostrSDK

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
    
    @StateObject private var nfcSession = NFCRequestCardSession()
    /// nil until the asynchronous NFC eligibility check has completed
    @State private var nfcAvailable: Bool?
    /// A token the payer wrote back over NFC; drives navigation to the redeem screen
    @State private var receivedTokenString: String?
    
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
    
    var body: some View {
        List {
            Section {
                NumericalInputView(output: $amount,
                                   baseUnit: .sat,
                                   exchangeRates: appState.exchangeRates) {}
                                   .disabled(paymentRequest != nil)
            }
            
            if let paymentRequest, let string = try? NUT26.encode(paymentRequest) {
                Section {
                    StaticQRView(string: string)
                    Button {
                        // The QR uses the uppercase form for alphanumeric-mode compactness,
                        // but copy the canonical lowercase bech32m so pasted requests are unmodified.
                        UIPasteboard.general.string = string.lowercased()
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
                            Text(copied ? String(localized: "Copied!") : String(localized: "Copy to clipboad"))
                            Spacer()
                            Image(systemName: copied ? "clipboard.fill" : "clipboard")
                        }
                    }
                } footer: {
                    Text(paymentRequest.paymentId ?? "No ID")
                }
                
                nfcSection
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
                                Text("A one-time key is generated for this request")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .lineLimit(1)
                        }
                    }
                } header: {
                    Text("Receive via")
                } footer: {
                    if useNIP17Transport {
                        Text("Payments to this request can be received via Nostr for 90 days.")
                    }
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
                    .opacity(paymentRequest == nil ? 1 : 0)
                }
            }
        }
        .navigationTitle("Payment Request")
        .task {
            nfcAvailable = await NFCRequestCardSession.isAvailable
        }
        .onChange(of: nfcSession.status) { _, status in
            switch status {
            case .tokenReceived(let tokenString):
                receivedTokenString = tokenString
            case .failed(let message):
                displayAlert(alert: AlertDetail(title: String(localized: "⚠️ NFC Error"),
                                                description: message))
            case .idle, .presenting:
                break
            }
        }
        .navigationDestination(item: $receivedTokenString) { tokenString in
            // Same screen as a scanned or pasted token, but redeeming starts on its own
            RedeemView(tokenString: tokenString, autoRedeem: true)
        }
        .onDisappear {
            nfcSession.stop()
        }
        .alertView(isPresented: $showAlert, currentAlert: currentAlert)
    }
    
    /// Lets the payer read the request from this iPhone by tapping it. The
    /// button is always shown; it is only enabled once card emulation is known
    /// to be available on this device and in this region.
    private var nfcSection: some View {
        Section {
            Button {
                presentViaNFC()
            } label: {
                HStack {
                    Text("Receive via NFC")
                    Spacer()
                    if nfcSession.isPresenting {
                        ProgressView()
                    } else {
                        Image(systemName: "wave.3.right")
                    }
                }
            }
            .disabled(nfcAvailable != true || nfcSession.isPresenting)
        } footer: {
            switch nfcAvailable {
            case true?:
                Text("Hold the payer's device to this iPhone. Ecash received over NFC is redeemed automatically.")
            case false?:
                Text("Receiving via NFC is not available on this device or in your region.")
            case nil:
                EmptyView()
            }
        }
    }
    
    private func presentViaNFC() {
        guard let paymentRequest else { return }
        do {
            // NUT-18 (creqA) is what Numo-spec payers and macadamia's Contactless
            // view expect to read from the tag; the QR code uses the compact NUT-26 form.
            let payload = try paymentRequest.serialize()
            nfcSession.start(payload: payload)
        } catch {
            displayAlert(alert: AlertDetail(with: error))
        }
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

        let paymentId = createPaymentRequestIdentifier()

        // Create transports array if NIP-17 is enabled
        var transports: [CashuSwift.Transport]? = nil
        if useNIP17Transport {
            guard let activeWallet else {
                displayAlert(alert: AlertDetail(title: String(localized: "⚠️ Nostr Key Error"),
                                                description: String(localized: "No active wallet to create a receive key for.")))
                return
            }

            // A fresh random keypair for every request: requests stay unlinkable to each
            // other, and the key lives in the database, sharing the wallet's lifecycle
            guard let keypair = Keypair() else {
                displayAlert(alert: AlertDetail(title: String(localized: "⚠️ Nostr Key Error"),
                                                description: String(localized: "Failed to generate a Nostr key for this request.")))
                return
            }

            // Use nprofile format with relay hints so the sender knows where to publish.
            // These must be the saved relays this wallet actually listens on.
            let relayStrings = nostrService.relayURLs.map { $0.absoluteString }

            let nprofile: String
            do {
                nprofile = try NostrKeyMaterial.nprofile(publicKeyHex: keypair.publicKey.hex,
                                                         relays: relayStrings)
            } catch {
                displayAlert(alert: AlertDetail(title: String(localized: "⚠️ Nostr Key Error"),
                                                description: String(localized: "Failed to encode the Nostr key for this request: \(error.localizedDescription)")))
                return
            }

            let keyRow = NostrKeypair(privateKeyHex: keypair.privateKey.hex,
                                      publicKeyHex: keypair.publicKey.hex,
                                      paymentId: paymentId,
                                      wallet: activeWallet)
            modelContext.insert(keyRow)
            do {
                try modelContext.save()
            } catch {
                // Never show a QR code nobody will be listening for
                modelContext.delete(keyRow)
                displayAlert(alert: AlertDetail(title: String(localized: "⚠️ Nostr Key Error"),
                                                description: String(localized: "Failed to store the Nostr key for this request: \(error.localizedDescription)")))
                return
            }

            let nostrTransport = CashuSwift.Transport(type: CashuSwift.Transport.TransportType.nostr, target: nprofile)
            transports = [nostrTransport]
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

        let request = CashuSwift.PaymentRequest(paymentId: paymentId,
                                                amount: requestAmount,
                                                unit: Unit.sat.currencyCode,
                                                singleUse: false,
                                                mints: mintURLs,
                                                description: requestDescription,
                                                transports: transports,
                                                lockingCondition: lockingCondition)

        withAnimation {
            paymentRequest = request
        }

        if useNIP17Transport {
            // Start or extend the relay subscription to include the new key
            nostrService.refreshSubscriptions()
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

//#Preview {
//    RequestView()
//}
