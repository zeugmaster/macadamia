//
//  NFCRequestView.swift
//  macadamia
//
//  EXPERIMENTAL: "Request ecash" over NFC using HCE card emulation (EEA only).
//
//  The user enters an amount, then this device emulates an NFC tag carrying
//  the payment request. A payer device (macadamia's Contactless view or any
//  Numo-spec payer) taps, reads the request, and writes the ecash token back,
//  which is then redeemed via the regular redeem flow.
//

import CashuSwift
import SwiftUI

struct NFCRequestView: View {
    @EnvironmentObject private var appState: AppState

    @StateObject private var cardSession = NFCRequestCardSession()

    @State private var amount: Int = 0
    @State private var description = ""
    @State private var requestPayload: String?
    @State private var redeemTokenString: String?

    @State private var showAlert: Bool = false
    @State private var currentAlert: AlertDetail?

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
        .navigationDestination(item: $redeemTokenString) { tokenString in
            RedeemContainerView(tokenString: tokenString)
        }
        .onChange(of: cardSession.status) { _, newStatus in
            if case .tokenReceived(let token) = newStatus {
                redeemTokenString = token
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
            return "checkmark.circle.fill"
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
            return String(localized: "Payment received!")
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

    private func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}
