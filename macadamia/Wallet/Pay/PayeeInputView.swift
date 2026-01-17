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
    
    private var hideScanner: Bool {
        textFieldInFocus || !textFieldInput.isEmpty
    }
    
    var body: some View {
        VStack {
            HStack {
                ZStack(alignment: .leading) {
                    if textFieldInput.isEmpty {
                        Text("satoshin@gmx.net")
                            .opacity(0.4)
                    }
                    HStack {
                        TextField("", text: $textFieldInput)
                            .onSubmit {
                                print("user hit submit via keyboard")
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
                    print("submit button pressed.")
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
            
            InputView(supportedTypes: [.bolt11Invoice, .lightningAddress, .lnurlPay]) { result in
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
                EmptyView()
            default:
                Text("Unsupported Input")
            }
        }
        .navigationTitle("Pay")
    }
}

#Preview {
    PayeeInputView()
}
