//
//  RequestPay.swift
//  macadamia
//
//  Created by zm on 17.11.25.
//

import SwiftUI
import SwiftData
import CashuSwift

struct RequestPay: View {
    
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var nostrService: NostrService
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]
    
    @Query private var allProofs:[Proof]
    
    private var mintsInUse: [Mint] {
        if let activeWallet {
            return activeWallet.mints.filter({ !$0.hidden })
                                     .sorted { ($0.userIndex ?? 0) < ($1.userIndex ?? 0) }
        } else {
            return []
        }
    }
    
    var paymentRequest: CashuSwift.PaymentRequest
    
    @State private var userProvidedAmountString: String = ""
    
    private var userProvidedAmount: Int? {
        Int(userProvidedAmountString)
    }
    
    @State private var selectedMint: Mint?
    @State private var selectedTransport: CashuSwift.Transport?
    
    @State private var expandMintSelector = false
    
    @State private var buttonState: ActionButtonState = .idle("")
    @State private var token: CashuSwift.Token?
    
    @State private var showAlert: Bool = false
    @State private var currentAlert: AlertDetail?
    @State private var showBalanceError = false
    
    private var activeWallet: Wallet? {
        wallets.first
    }
    
    /// The unit the request is denominated in. NUT-18 makes it optional and
    /// defaults to sat; anything else (fiat, custom units like "bux") is fine as
    /// long as one of the accepted mints holds ecash in it.
    private var requestUnit: Currency.Unit {
        Unit(paymentRequest.unit) ?? .sat
    }
    
    private var requestedAmount: Int? {
        paymentRequest.amount ?? userProvidedAmount
    }
    
    /// The note the requester attached (NUT-18 `d`). It travels with the
    /// payment as the payload memo so the recipient sees what was paid for.
    private var requestMemo: String? {
        (paymentRequest.description?.trimmingCharacters(in: .whitespacesAndNewlines)).nilWhenEmtpy
    }
    
    private var insufficentBalance: Bool {
        guard let selectedMint else { return false }
        return selectedMint.balance(for: requestUnit) < (requestedAmount ?? 0)
    }
    
    /// Mints the request allows, regardless of unit.
    private var acceptedMints: [Mint] {
        mintsInUse.acceptedByPaymentRequest(mintURLs: paymentRequest.mints ?? [])
    }
    
    /// Accepted mints that hold ecash in the requested unit.
    private var possibleMints: [Mint] {
        acceptedMints.filter { $0.balance(for: requestUnit) > 0 }
    }
    
    private var relayConnectionIndicatorColor: Color {
        switch nostrService.aggregateConnectionState {
        case .noneConnected:
            return .red
        case .partiallyConnected(_):
            return .orange
        case .allConnected(_):
            return .primary
        }
    }
    
    private var actionButtonDisabled: Bool {
        // Require a selection from the mints that can pay this request: accepted
        // by the request (any mint when it lists none) and holding ecash in the
        // requested unit. When no mint qualifies, possibleMints is empty, nothing
        // can be selected, and the button stays disabled.
        guard let selectedMint, possibleMints.contains(selectedMint) else { return true }

        let requiredAmount = requestedAmount ?? 0
        if requiredAmount <= 0 { return true }
        if requiredAmount > selectedMint.balance(for: requestUnit) { return true }
        if let transports = paymentRequest.transports,
           transports.contains(where: { $0.type == "nostr" }) {
            switch nostrService.aggregateConnectionState {
            case .noneConnected:
                return true
            default:
                break
            }
        }
        return false
    }
    
    var body: some View {
        ZStack {
            List {
                Section {
                    HStack(alignment: .center) {
                        if let amount = paymentRequest.amount {
                            AmountView(amount: amount,
                                       unit: requestUnit,
                                       showUnit: false)
                        } else {
                            TextField("", text: $userProvidedAmountString, prompt: Text("Amount..."))
                                .keyboardType(.numberPad)
                                .disabled(buttonState.type != .idle)
                        }
                        Spacer()
                        Text(requestUnit.currencyCode)
                    }
                    .monospaced()
                    .lineLimit(1)
                    .font(.largeTitle)
                    .listRowBackground(Color.clear)
                    .padding(.horizontal)
                    .bold()
                    
                    if showBalanceError {
                        Text("Insufficient balance")
                            .foregroundStyle(.red)
                            .font(.subheadline)
                            .bold()
                            .listRowBackground(Color.clear)
                    }
                }
                
                mintSelector
                    .disabled(buttonState.type != .idle || token != nil)
                transportSelector
                    .disabled(buttonState.type != .idle || token != nil)
                
                if let requestMemo {
                    Section {
                        Text(requestMemo)
                    } header: {
                        Text("Memo")
                    }
                }
                
                if let lockingCondition = paymentRequest.lockingCondition {
                    Section {
                        HStack {
                            Image(systemName: "lock")
                            Text(lockingCondition.data)
                        }
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                    } header: {
                        Text("Lock to public key")
                    }
                }
                
                if let token {
                    TokenShareView(token: token)
                }
                
                Spacer(minLength: 50)
                    .listRowBackground(Color.clear)
            }
            
            VStack {
                Spacer()
                ActionButton(state: $buttonState, hideShadow: true)
                    .actionDisabled(actionButtonDisabled)
            }
        }
        .onAppear {
            buttonState = .idle("Pay", action: pay)
            if let transports = paymentRequest.transports, !transports.isEmpty {
                selectedTransport = transports.first
            }

            // Don't pre-select a mint: the user must actively choose one of the
            // request's accepted mints, so the selector shows "Select a mint" first.

            if let transports = paymentRequest.transports, transports.contains(where: { $0.type == "nostr" }) {
                nostrService.connect()
            }
            
            showBalanceError = insufficentBalance
        }
        .onChange(of: userProvidedAmount) {
            withAnimation {
                showBalanceError = insufficentBalance
            }
        }
        .onChange(of: selectedMint) {
            withAnimation {
                showBalanceError = insufficentBalance
            }
        }
        .navigationTitle("Payment Request")
        .alertView(isPresented: $showAlert, currentAlert: currentAlert)
    }
    
    private var mintSelector: some View {
        Section {

            if possibleMints.isEmpty {
                // "Make transfer" is temporarily disabled: eagerly constructing
                // SwapView() here freezes the UI. The footer below still explains
                // why no mint can be selected.
                // NavigationLink(destination: SwapView(), label: {
                //     HStack {
                //         Image(systemName: "arrow.down.left.arrow.up.right")
                //         Text("Make transfer")
                //     }
                // })
                EmptyView()
            } else {
                Button {
                    withAnimation {
                        expandMintSelector.toggle()
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            if let selectedMint {
                                Text("Pay from: \(selectedMint.displayName)")
                            } else {
                                Text("Select a mint")
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.footnote)
                            .rotationEffect(.degrees(expandMintSelector ? 90 : 0))
                    }
                }
                
                if expandMintSelector {
                    ForEach(possibleMints) { mint in
                        Button {
                            selectedMint = mint
                        } label: {
                            HStack {
                                Image(systemName: mint == selectedMint ? "checkmark.circle.fill" : "circle")
                                Text(mint.displayName)
                                Spacer()
                                AmountView(amount: mint.balance(for: requestUnit), unit: requestUnit)
                                    .monospaced()
                            }
                        }
                    }
                }
            }
        } footer: {
            if acceptedMints.isEmpty {
                Text("Payment is requested from a mint you don't have any ecash with.")
            } else if possibleMints.isEmpty {
                Text("None of the accepted mints hold any ecash in the requested unit.")
            }
        }
    }
    
    @ViewBuilder
    private var transportSelector: some View {
        if let transports = paymentRequest.transports {
            Section {
                ForEach(transports) { t in
                    Button {
                        self.selectedTransport = t
                    } label: {
                        HStack {
                            self.selectedTransport == t ? Image(systemName: "checkmark.circle.fill") : Image(systemName: "circle")
                            if t.type == "nostr" {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text("Nostr")
                                        Text(t.target)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    SystemImageBadge(systemName: "network", count: nostrService.connectionStates.filter({ $0.value == .connected }).count)
                                        .foregroundStyle(relayConnectionIndicatorColor)
                                }
                            } else if t.type == "post" {
                                VStack(alignment: .leading) {
                                    Text("HTTP")
                                    Text(t.target)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            } header: {
                Text("Send via")
            }
        } else {
            EmptyView()
        }
    }
    
    private func pay() {
        
        guard let selectedMint, let activeWallet else {
            return
        }
        
        guard let amount = requestedAmount, amount > 0 else {
            logger.error("no amount provided")
            return
        }
        
        let unit = requestUnit
        
        Task { @MainActor in
            buttonState = .loading()
            
            guard let selection = selectedMint.select(amount: amount, unit: unit) else {
                logger.error("proof selection failed for \(amount) \(unit.currencyCode) at \(selectedMint.url.absoluteString)")
                failAndReset(with: AlertDetail(with: CashuError.insufficientInputs("")))
                return
            }
            
            selection.selected.setState(.pending)
            
            let requestResponse: CashuSwift.SendPayloadResult
            do {
                requestResponse = try await CashuSwift.send(request: paymentRequest,
                                                            mint: CashuSwift.Mint(selectedMint),
                                                            inputs: selection.selected.sendable(),
                                                            memo: requestMemo,
                                                            seed: activeWallet.seed)
            } catch {
                // The swap did not go through, so the inputs are still ours.
                selection.selected.setState(.valid)
                logger.error("payment request send failed: \(error)")
                failAndReset(with: AlertDetail(with: error))
                return
            }
            
            // From here on the mint has swapped our inputs. Nothing below may
            // return the button to a payable state, or the user could pay twice.
            if let counterIncrease = requestResponse.counterIncrease {
                selectedMint.increaseDerivationCounterForKeysetWithID(counterIncrease.keysetID,
                                                                      by: counterIncrease.increase)
            }
            
            selection.selected.setState(.spent)
            
            let payload = requestResponse.payload
            
            do {
                try selectedMint.addProofs(requestResponse.change,
                                           to: modelContext,
                                           increaseDerivationCounter: false)
                
                // Keep the outgoing proofs as pending, like a regular send, so
                // the event can later check whether they were redeemed.
                let sentProofs = try selectedMint.addProofs(requestResponse.send,
                                                            to: modelContext,
                                                            state: .pending,
                                                            increaseDerivationCounter: false)
                
                let event = Event.sendEvent(unit: unit,
                                            shortDescription: "Send",
                                            wallet: activeWallet,
                                            amount: amount,
                                            token: payload.toToken(),
                                            longDescription: "",
                                            proofs: sentProofs,
                                            memo: requestMemo ?? "",
                                            mint: selectedMint)
                
                modelContext.insert(event)
                try modelContext.save()
            } catch {
                // Persisting failed but the ecash exists; still deliver it and
                // tell the user what went wrong.
                logger.error("failed to persist payment request send: \(error)")
                displayAlert(alert: AlertDetail(with: error))
            }
            
            guard let transport = selectedTransport else {
                token = payload.toToken()
                buttonState = .success()
                return
            }
            
            switch transport.type {
            case "nostr":
                await sendViaNIP17(payload: payload, receiveerNPUB: transport.target)
            case "post":
                await sendViaHTTP(payload: payload, urlString: transport.target)
            default:
                // Unknown transport: hand the token to the user for manual delivery.
                logger.warning("unsupported transport type \(transport.type), showing token instead")
                token = payload.toToken()
                buttonState = .success()
            }
        }
    }
    
    /// Marks the action as failed and returns the button to idle after a short
    /// delay. Only for failures that happen before the mint swapped our inputs.
    private func failAndReset(with alert: AlertDetail) {
        buttonState = .fail()
        displayAlert(alert: alert)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            buttonState = .idle("Pay", action: pay)
        }
    }
    
    private func sendViaNIP17(payload: CashuSwift.PaymentRequestPayload, receiveerNPUB: String) async {
        do {
            // Encode payload as JSON
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let jsonData = try encoder.encode(payload)
            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                displayAlert(alert: AlertDetail(title: String(localized: "⚠️ Encoding Error"), description: String(localized: "Failed to encode payment data.")))
                buttonState = .fail()
                return
            }

            // Send the DM via NIP-17, signed by a throwaway key the service generates
            try await nostrService.sendNIP17(to: receiveerNPUB, message: jsonString)
            
            buttonState = .success()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                dismiss()
            }
        } catch {
            let errorMessage: String
            if let nostrError = error as? NostrServiceError {
                switch nostrError {
                case .noKeypairAvailable:
                    errorMessage = "Failed to generate Nostr key"
                case .invalidRecipientPubkey:
                    errorMessage = "Invalid recipient public key"
                case .encryptionFailed:
                    errorMessage = "Failed to encrypt message"
                case .eventCreationFailed:
                    errorMessage = "Failed to create message event"
                case .decryptionFailed:
                    errorMessage = "Failed to decrypt message"
                }
            } else {
                errorMessage = error.localizedDescription
            }
            
            displayAlert(alert: AlertDetail(title: String(localized: "🛰️ Transmission Error"), description: errorMessage))
            token = payload.toToken() // the swap already happened; let the user deliver it manually
            buttonState = .fail()
        }
    }
    
    private func sendViaHTTP(payload: CashuSwift.PaymentRequestPayload, urlString: String) async {
        let string = urlString.lowercased()
        
        guard (string.hasPrefix("http") || string.hasPrefix("https")),
              let url = URL(string: urlString) else {
            displayAlert(alert: AlertDetail(title: String(localized: "HTTP transport URL invalid."), description: String(localized: "The provided string \(urlString) does not seem to be valid. Please send the ecash manually or reclaim it.")))
            token = payload.toToken() // show the token so the user has a fallback
            buttonState = .fail()
            return
        }
        
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = try JSONEncoder().encode(payload)
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                displayAlert(alert: AlertDetail(title: String(localized: "⚠️ Unexpected HTTP Response"), description: String(localized: "The request returned status: \(String(describing: httpResponse.statusCode))")))
                token = payload.toToken() // the receiver may not have accepted it; keep the token reachable
                buttonState = .fail()
                return
            }
            
            buttonState = .success()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                dismiss()
            }
        } catch {
            let alertDetail = AlertDetail(title: String(localized: "🛰️ Transmission issue"),
                                          description: String(describing: error),
                                          primaryButton: AlertButton(title: String(localized: "Retry"), action: {
                                              // TODO: find less convoluted retry logic
                                              Task { @MainActor in
                                                  await sendViaHTTP(payload: payload, urlString: urlString)
                                              }
                                          }),
                                          secondaryButton: AlertButton(title: String(localized: "Cancel"), role: .cancel, action: {
                                              token = payload.toToken() // keep the swapped ecash reachable
                                              buttonState = .fail()
                                          }))
            displayAlert(alert: alertDetail)
        }
    }
    
    private func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}

struct SystemImageBadge: View {
    let systemName: String
    let count: Int
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: systemName)
                .font(.title2)
                
            Text("\(count)")
                .font(.caption2).bold()
                .foregroundStyle(.background)
                .padding(4)
                .background(
                    Circle().fill(.foreground)
                )
                .offset(x: 6, y: -6)
        }
    }
}

#Preview {
    SystemImageBadge(systemName: "network", count: 3)
        .foregroundStyle(.red)
}


//#Preview {
//    RequestPay()
//}
