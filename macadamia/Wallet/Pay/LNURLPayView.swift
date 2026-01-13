//
//  LNURLPayView.swift
//  macadamia
//
//  Created by zm on 13.01.26.
//

import SwiftUI
import LNURL_Swift

struct LNURLPayView: View {
    let userInput: InputView.Result
    
    @State private var amountString: String = ""
    @State private var actionButtonState = ActionButtonState.idle("...")
    
    @State private var payResponse: LNURLPayResponse?
    
    @State private var showAlert = false
    @State private var currentAlert: AlertDetail?
    
    private var amount: Int {
        Int(amountString) ?? 0
    }
    
    var body: some View {
        ZStack {
            List {
                Section {
                    Text(userInput.payload)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
                
                // show lnurl pay response and optional amount selection
                if let payResponse {
                    Section {
                        Text(String(payResponse.minSendable))
                        Text(String(payResponse.maxSendable))
                        Text(String(payResponse.metadata))
                    }
                    .font(.callout)
                }
                
                Spacer(minLength: 60)
                    .listRowBackground(Color.clear)
            }
            VStack {
                Spacer()
                ActionButton(state: $actionButtonState, hideShadow: true)
                    .actionDisabled(false)
            }
        }
        .onAppear {
            actionButtonState = .idle("Next", action: {
                requestInvoice()
            })
            
            resolveRequest()
        }
        .alertView(isPresented: $showAlert, currentAlert: currentAlert)
    }
    
    private func resolveRequest() {
        Task {
            do {
                let response = try await LNURL.shared.fetchPayRequest(userInput.payload)
                payResponse = response
            } catch {
                displayAlert(alert: AlertDetail(with: error))
            }
        }
    }
    
    private func requestInvoice() {
        print("requestInvoice called")
        
        
    }
    
    private func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}

//#Preview {
//    LNURLPayView()
//}
