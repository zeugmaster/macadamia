//
//  LNURLPayView.swift
//  macadamia
//
//  Created by zm on 13.01.26.
//

import SwiftUI
import LNURL_Swift

struct LNURLPayView: View {
    let userInput: String
    
    @EnvironmentObject private var appState: AppState
    
    @State private var amount: Int = 0
    @State private var actionButtonState = ActionButtonState.idle("...")
    
    @State private var payResponse: LNURLPayResponse?
    @State private var invoiceString: String?
    
    @State private var showAlert = false
    @State private var currentAlert: AlertDetail?
    
    private var inputWithinfLimits: Bool {
        if let payResponse {
            return (Int(payResponse.minSendableSat)...Int(payResponse.maxSendableSat))
                    .contains(amount)
        }
        return true
    }
    
    // do not color label red in case of no input yet
    private var invalidUserInput: Bool {
        !inputWithinfLimits && amount != 0
    }
    
    var body: some View {
        ZStack {
            List {
                // show lnurl pay response and optional amount selection
                
                Section {
                    if let payResponse {
                        NumericalInputView(output: $amount,
                                           baseUnit: .sat,
                                           exchangeRates: appState.exchangeRates,
                                           onReturn: {
                            guard !invalidUserInput else { return }
                            requestInvoice() 
                        })
                        .disabled(payResponse.maxSendable == payResponse.minSendable)
                        if payResponse.minSendable != payResponse.maxSendable {
                            HStack {
                                Text("Min:")
                                Text(String(payResponse.minSendableSat))
                                Spacer()
                                Text("Max:")
                                Text(String(payResponse.maxSendableSat))
                            }
                            .foregroundStyle(!invalidUserInput ? .secondary : Color.red)
                            .animation(.linear(duration: 0.2), value: inputWithinfLimits)
                            .font(.caption)
                        }
                    } else {
                        HStack {
                            Spacer()
                            ProgressView()
                                .controlSize(.large)
                            Spacer()
                        }
                        .listRowBackground(EmptyView())
                    }
                } header: {
                    Text(userInput)
                        .lineLimit(1)
                }
                
                Spacer(minLength: 60)
                    .listRowBackground(Color.clear)
            }
            VStack {
                Spacer()
                ActionButton(state: $actionButtonState, hideShadow: true)
                    .actionDisabled(!inputWithinfLimits)
            }
        }
        .navigationDestination(item: $invoiceString) { invoice in
            MeltView(invoice: invoice)
        }
        .onAppear {
            actionButtonState = .idle(String(localized: "Next"), action: {
                requestInvoice()
            })
            
            resolveRequest()
        }
        .alertView(isPresented: $showAlert, currentAlert: currentAlert)
    }
    
    private func resolveRequest() {
        Task {
            do {
                let response = try await LNURL.shared.fetchPayRequest(userInput)
                withAnimation {
                    payResponse = response
                }
                if response.minSendable == response.maxSendable {
                    amount = Int(response.minSendableSat)
                }
            } catch {
                displayAlert(alert: AlertDetail(with: error))
            }
        }
    }
    
    private func requestInvoice() {
        guard let payResponse else {
            return
        }
        
        actionButtonState = .loading()
        
        Task {
            do {
                let paymentRequest = try await LNURL.shared.pay.requestInvoice(from: payResponse,
                                                                               amountMsat: Int64(amount * 1000))
                
                invoiceString = paymentRequest.pr
            } catch {
                actionButtonState = .fail()
                displayAlert(alert: AlertDetail(with: error))
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    actionButtonState = .idle(String(localized: "Next"), action: { requestInvoice() })
                }
            }
        }
    }
    
    private func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}

//#Preview {
//    LNURLPayView()
//}
