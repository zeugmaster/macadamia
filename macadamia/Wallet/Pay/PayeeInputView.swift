//
//  PayeeInputView.swift
//  macadamia
//
//  Created by zm on 17.01.26.
//

// Provides the QR scanner and a text input field for LNURL Lightning Addresses

import SwiftUI

struct PayeeInputView: View {
    
    @State private var textFieldInput: String = ""
    @FocusState private var textFieldInFocus: Bool
    
    @State private var input: InputView.Result?
    
    @State private var showAlert = false
    @State private var currentAlert: AlertDetail?
    
    private var hideScanner: Bool {
        textFieldInFocus || !textFieldInput.isEmpty
    }
    
    var body: some View {
        VStack {
            HStack {
                ZStack(alignment: .leading) {
                    if textFieldInput.isEmpty {
                        Text("satoshin@gmx.com")
                            .opacity(0.4)
                    }
                    HStack {
                        TextField("", text: $textFieldInput)
                            .onSubmit {
                                onTextInputSubmit()
                            }
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($textFieldInFocus)
                        
                        Button {
                            textFieldInput = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .bold()
                                .font(.callout)
                        }
                        .opacity(textFieldInput.isEmpty ? 0 : 1)
                        .animation(.linear(duration: 0.1), value: textFieldInput.isEmpty)
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.3)))
                
                Button {
                    if textFieldInput.isEmpty { return }
                    onTextInputSubmit()
                } label: {
                    Image(systemName: "arrow.right")
                        .font(.title2)
                        .bold()
                }
                .foregroundStyle(textFieldInput.isEmpty ? .secondary : .primary)
                .opacity(textFieldInput.isEmpty ? 0.6 : 1)
                .animation(.linear(duration: 0.2), value: textFieldInput.isEmpty)
                .padding(6)
            }
            
            Spacer().frame(height: 20)
            
            InputView(supportedTypes: [.bolt11Invoice, .lightningAddress, .lnurlPay, .merchantCode]) { result in
                input = result
            }
            .opacity(hideScanner ? 0 : 1)
            .animation(.easeInOut(duration: 0.2), value: hideScanner)
            
            Spacer()
        }
        .padding()
        .navigationDestination(item: $input) { input in
            switch input.type {
            case .bolt11Invoice:
                // go directly to melt view
                MeltView(invoice: input.payload)
            case .lightningAddress, .lnurlPay, .merchantCode:
                // merchantCode payload is already converted to a lightning address
                LNURLPayView(userInput: input.payload)
            default:
                Text("Unsupported Input")
            }
        }
        .navigationTitle("Pay")
        .alertView(isPresented: $showAlert, currentAlert: currentAlert)
    }
    
    private func onTextInputSubmit() {
        guard !textFieldInput.isEmpty else {
            return
        }
        
        let inputValidationResult = InputValidator.validate(textFieldInput, supportedTypes: [.bolt11Invoice, .lightningAddress, .lnurlPay])
        
        switch inputValidationResult {
        case .valid(let result):
            input = result
        case .invalid(_):
            let desc = """
                This field supports BOLT11 invoices, LNURL strings (LNURL1...) or \
                Lightning Addresses (e.g. user@host.com).
                """
            displayAlert(alert: AlertDetail(title: "Invalid Input", description: desc))
        }
    }
    
    private func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}

#Preview {
    PayeeInputView()
}
