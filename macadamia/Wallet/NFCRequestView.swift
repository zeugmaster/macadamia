//
//  NFCRequestView.swift
//  macadamia
//
//  EXPERIMENTAL: "Request ecash" over NFC using HCE card emulation (EEA only).
//
//  The user enters an amount, then this device emulates an NFC tag carrying
//  the payment request. A payer device (macadamia's Contactless view or any
//  Numo-spec payer) taps, reads the request, and writes the ecash token back.
//  Tokens from a known mint are redeemed immediately — mirroring the nostr
//  transport's auto-redeem in WalletView — while unknown mints and redeem
//  errors fall back to the manual redeem sheet without losing the token.
//

import CashuSwift
import SwiftData
import SwiftUI

struct NFCRequestView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState

    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]

    @StateObject private var cardSession = NFCRequestCardSession()

    @State private var amount: Int = 0
    @State private var description = ""
    @State private var requestPayload: String?

    /// Outcome of handling the token a payer wrote back over NFC.
    private enum RedeemState {
        case idle
        case redeeming
        case success(amount: Int, unit: Unit)
        /// Auto-redeem was not possible; the token is preserved for manual handling.
        case fallback(tokenString: String, message: String)
    }
    @State private var redeemState: RedeemState = .idle
    @State private var showManualRedeem = false

    @State private var showAlert: Bool = false
    @State private var currentAlert: AlertDetail?

    private var activeWallet: Wallet? {
        wallets.first
    }

    var body: some View {
        List {
            Section {
                NumericalInputView(output: $amount,
                                   baseUnit: .sat,
                                   exchangeRates: appState.exchangeRates) {}
                                   .disabled(requestPayload != nil)
            }

            if requestPayload != nil {
                emulationSection
                eventLogSection
            } else {
                Section {
                    TextField("", text: $description, prompt: Text("Optional description..."))
                } footer: {
                    Text("The request is offered to any mint. The payer returns the ecash token over NFC.")
                }
            }
        }
        .toolbar {
            if requestPayload == nil {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        generateAndPresentRequest()
                    }) {
                        Text("Done")
                    }
                    .disabled(amount <= 0)
                }
            }
        }
        .navigationTitle("NFC Request")
        .onChange(of: cardSession.status) { _, newStatus in
            if case .tokenReceived(let token) = newStatus {
                autoRedeem(tokenString: token)
            }
        }
        .sheet(isPresented: $showManualRedeem) {
            if case .fallback(let tokenString, _) = redeemState {
                RedeemContainerView(tokenString: tokenString)
            }
        }
        .onDisappear {
            cardSession.stop()
        }
        .alertView(isPresented: $showAlert, currentAlert: currentAlert)
    }

    // MARK: - Emulation Status UI

    private var emulationSection: some View {
        Section {
            VStack {
                HStack {
                    Image(systemName: statusSymbolName)
                        .foregroundStyle(.primary.opacity(0.5))
                        .fontWeight(.light)
                    if isAwaitingReader {
                        RadioWaveSymbol()
                    }
                }
                .font(.system(size: 60))
                .padding(20)

                Text(statusText)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                switch redeemState {
                case .idle:
                    EmptyView()
                case .redeeming:
                    ProgressView()
                        .padding(.top, 8)
                case .success(let amount, let unit):
                    AmountView(amount: amount, unit: unit)
                        .font(.title2.bold().monospacedDigit())
                        .padding(.top, 8)
                case .fallback(let tokenString, _):
                    VStack(spacing: 4) {
                        Button {
                            showManualRedeem = true
                        } label: {
                            Label("Redeem Manually", systemImage: "arrow.down.circle")
                        }
                        .padding()
                        Button {
                            UIPasteboard.general.string = tokenString
                        } label: {
                            Label("Copy Token", systemImage: "clipboard")
                        }
                    }
                    .padding(.top, 4)
                }

                if case .ended = cardSession.status, let requestPayload {
                    Button {
                        cardSession.start(payload: requestPayload)
                    } label: {
                        Label("Present Again", systemImage: "arrow.counterclockwise")
                    }
                    .padding()
                }
            }
            .frame(maxWidth: .infinity)
        } footer: {
            if let requestPayload {
                Text(requestPayload)
                    .font(.caption.monospaced())
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        }
    }

    private var eventLogSection: some View {
        Section {
            ForEach(Array(cardSession.eventLog.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .listRowSeparator(.hidden)
            }
        } header: {
            HStack {
                Text("Event Log")
                Spacer()
                Button {
                    UIPasteboard.general.string = cardSession.eventLog.joined(separator: "\n")
                } label: {
                    Image(systemName: "clipboard")
                }
            }
        }
    }

    private var isAwaitingReader: Bool {
        switch cardSession.status {
        case .waitingForReader, .readerConnected, .requestRead:
            return true
        default:
            return false
        }
    }

    private var statusSymbolName: String {
        switch cardSession.status {
        case .tokenReceived:
            switch redeemState {
            case .success:
                return "checkmark.circle.fill"
            case .fallback:
                return "exclamationmark.circle"
            case .idle, .redeeming:
                return "iphone.gen2.crop.circle"
            }
        case .unavailable, .ended:
            return "exclamationmark.circle"
        default:
            return "iphone.gen2.crop.circle"
        }
    }

    private var statusText: String {
        switch cardSession.status {
        case .idle:
            return String(localized: "Preparing...")
        case .unavailable(let reason):
            return reason
        case .waitingForReader:
            return String(localized: "Hold near the payer's device...")
        case .readerConnected:
            return String(localized: "Connected, sending payment request...")
        case .requestRead:
            return String(localized: "Request read, awaiting payment...")
        case .tokenReceived:
            switch redeemState {
            case .idle, .redeeming:
                return String(localized: "Payment received, redeeming...")
            case .success:
                return String(localized: "Payment received!")
            case .fallback(_, let message):
                return message
            }
        case .ended(let message):
            return message ?? String(localized: "Session ended.")
        }
    }

    // MARK: - Request Creation

    private func generateAndPresentRequest() {
        // No transport: the payer is expected to write the token back over NFC.
        let request = CashuSwift.PaymentRequest(paymentId: createIdentifier(),
                                                amount: amount,
                                                unit: Unit.sat.currencyCode,
                                                singleUse: true,
                                                mints: nil,
                                                description: description.isEmpty ? nil : description,
                                                transports: nil,
                                                lockingCondition: nil)
        do {
            // NUT-18 creqA encoding: understood by macadamia's Contactless payer
            // as well as Numo-spec payer implementations.
            let payload = try request.serialize()
            withAnimation {
                requestPayload = payload
            }
            cardSession.start(payload: payload)
        } catch {
            displayAlert(alert: AlertDetail(with: error))
        }
    }

    private func createIdentifier() -> String {
        let uuid = UUID().uuidString.lowercased()
        return uuid.components(separatedBy: "-").first ?? ""
    }

    // MARK: - Auto Redeem

    /// Redeems a token the payer wrote back over NFC, mirroring the nostr
    /// transport's auto-redeem in WalletView. Unknown mints and redeem errors
    /// fall back to the manual redeem sheet so the token is never lost and
    /// adding a foreign mint stays an explicit user decision.
    @MainActor
    private func autoRedeem(tokenString: String) {
        guard case .idle = redeemState else { return }

        guard let activeWallet else {
            redeemState = .fallback(tokenString: tokenString,
                                    message: String(localized: "No active wallet to redeem to."))
            return
        }

        let token: CashuSwift.Token
        do {
            token = try tokenString.deserializeToken()
        } catch {
            cardSession.note("token deserialization failed: \(error)")
            redeemState = .fallback(tokenString: tokenString,
                                    message: String(localized: "Could not decode the received token."))
            return
        }

        guard let mintURLString = token.proofsByMint.keys.first,
              let mint = activeWallet.mints.first(where: { $0.url.absoluteString == mintURLString && !$0.hidden }) else {
            cardSession.note("token from unknown mint")
            redeemState = .fallback(tokenString: tokenString,
                                    message: String(localized: "The payer sent ecash from a mint not in this wallet. Redeem manually to add the mint or swap."))
            return
        }

        redeemState = .redeeming
        cardSession.note("redeeming with \(mint.url.absoluteString)")

        let tokenUnit = Unit(code: token.unit)
        let keyString = activeWallet.privateKeyData.map { String(bytes: $0) }

        Task {
            do {
                let receiveResult = try await CashuSwift.receive(token: token,
                                                                 of: CashuSwift.Mint(mint),
                                                                 seed: activeWallet.seed,
                                                                 privateKey: keyString)
                let proofs = try mint.addProofs(receiveResult.proofs, to: modelContext)

                let event = Event.receiveEvent(unit: tokenUnit,
                                               shortDescription: "Receive",
                                               wallet: activeWallet,
                                               amount: proofs.sum,
                                               longDescription: "",
                                               proofs: proofs,
                                               memo: token.memo ?? "",
                                               mint: mint,
                                               redeemed: true)
                modelContext.insert(event)
                try modelContext.save()

                cardSession.note("redeem successful, added \(proofs.sum) to wallet")
                withAnimation {
                    redeemState = .success(amount: proofs.sum, unit: tokenUnit)
                }
            } catch {
                cardSession.note("redeem failed: \(error)")
                redeemState = .fallback(tokenString: tokenString,
                                        message: String(localized: "Redeeming failed: \(error.localizedDescription) The token is preserved, try redeeming it manually."))
            }
        }
    }

    private func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}
