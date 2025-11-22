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
    
    @State private var showAlert: Bool = false
    @State private var currentAlert: AlertDetail?
    @State private var showBalanceError = false
    
    private var activeWallet: Wallet? {
        wallets.first
    }
    
    private var insufficentBalance: Bool {
        selectedMint?.balance(for: .sat) ?? 0 < paymentRequest.amount ?? userProvidedAmount ?? 0
    }
    
    private var possibleMints: [Mint] {
        let urls = paymentRequest.mints ?? []
        return mintsInUse.filter { urls.isEmpty || urls.contains($0.url.absoluteString) }
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
        if paymentRequest.amount ?? userProvidedAmount ?? 0 <= 0 { return true }
        if paymentRequest.amount ?? userProvidedAmount ?? 0 > selectedMint?.balance(for: .sat) ?? 0 {
            return true
        }
        if paymentRequest.unit != "sat" {
            return true
        }
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
                            Text(String(amount))
                        } else {
                            TextField("", text: $userProvidedAmountString, prompt: Text("Amount..."))
                                .keyboardType(.numberPad)
                        }
                        Spacer()
                        Text(paymentRequest.unit ?? "sat")
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
                transportSelector
                
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
            
            // TODO: select first possible mint
            
            // TODO: connect to relays
            if let transports = paymentRequest.transports, transports.contains(where: { $0.type == "nostr" }) {
                nostrService.connect()
            }
            
            showBalanceError = insufficentBalance
        }
        .onChange(of: userProvidedAmount) { _, _ in
            withAnimation {
                showBalanceError = insufficentBalance
            }
        }
        .onChange(of: selectedMint) { _, _ in
            withAnimation {
                showBalanceError = insufficentBalance
            }
        }
        .navigationTitle("Payment Request")
    }
    
    private var mintSelector: some View {
        Section {
//            if let mints = paymentRequest.mints {
//                ForEach(mints, id: \.self) { urlString in
//                    if let url = URL(string: urlString) {
//                        Text(url.host() ?? urlString)
//                    } else {
//                        Text(urlString)
//                    }
//                }
//            }
            
            if possibleMints.isEmpty {
                NavigationLink(destination: SwapView(), label: {
                    HStack {
                        Image(systemName: "arrow.down.left.arrow.up.right")
                        Text("Make transfer")
                    }
                })
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
                                Group {
                                    let balance = mint.balance(for: .sat)

                                    Text(balance, format: .number)
                                        .contentTransition(.numericText(value: Double(balance)))
                                        .animation(.snappy, value: balance)

                                    Text(" sat")
                                }
                                .monospaced()
                            }
                        }
                    }
                }
            }
        } footer: {
            if possibleMints.isEmpty {
                Text("Payment is requested from a mint you don't have any ecash with.")
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
        
        guard let amount = paymentRequest.amount ?? userProvidedAmount else {
            logger.error("no amount provided")
            return
        }
        
        Task { @MainActor in
            do {
                buttonState = .loading()
                
                guard let proofs = selectedMint.select(amount: amount,
                                                       unit: Unit(paymentRequest.unit ?? "sat") ?? .sat) else {
                    // TODO: log error
                    return
                }
                
                // TODO: add memo field
                let requestResponse = try await CashuSwift.send(request: paymentRequest,
                                                                mint: CashuSwift.Mint(selectedMint),
                                                                inputs: proofs.selected.sendable(),
                                                                memo: nil,
                                                                seed: activeWallet.seed)
                
                if let counterIncrease = requestResponse.counterIncrease {
                    selectedMint.increaseDerivationCounterForKeysetWithID(counterIncrease.keysetID,
                                                                          by: counterIncrease.increase)
                }
                
                try selectedMint.addProofs(requestResponse.change,
                                           to: modelContext,
                                           increaseDerivationCounter: false)
                
                let event = Event.sendEvent(unit: Unit(paymentRequest.unit ?? "sat") ?? .sat,
                                            shortDescription: "Send",
                                            wallet: activeWallet,
                                            amount: paymentRequest.amount ?? userProvidedAmount ?? 0,
                                            token: requestResponse.payload.toToken(),
                                            longDescription: "",
                                            proofs: [],
                                            memo: "",
                                            mint: selectedMint)
                
                modelContext.insert(event)
                try modelContext.save()
                
                // check for 
                
            } catch {
                fatalError()
            }
        }
    }
    
    private func sendViaNIP17(payload: CashuSwift.PaymentRequestPayload, receiveerNPUB: String) {
        //...
    }
    
    private func sendViaHTTP(payload: CashuSwift.PaymentRequestPayload, url: URL) async throws {
        
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
