//
//  SwapView.swift
//  macadamia
//
//  Created by zm on 18.02.25.
//

import SwiftUI
import SwiftData

struct SwapView: View {
    
    enum PaymentState {
        case none, ready, loading, success, fail
    }
    
    @State private var state: PaymentState = .none
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State var showAlert: Bool = false
    @State var currentAlert: AlertDetail?
    
    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]
    
    @Query private var mints: [Mint]
    @Query private var allProofs: [Proof]
    
    @State private var fromMint: Mint?
    @State private var toMint: Mint?
    @State private var amountString = ""
    @FocusState var amountFieldInFocus: Bool

    var activeWallet: Wallet? {
        wallets.first
    }
    
    var amount: Int? {
        Int(amountString)
    }
    
    var body: some View {
        List {
            Section {
                MintPicker(label: "From: ", selectedMint: $fromMint, allowsNoneState: false, hide: $toMint)
                MintPicker(label: "To: ", selectedMint: $toMint, allowsNoneState: true, hide: $fromMint)
            }

            Section {
                HStack {
                    TextField("enter amount", text: $amountString)
                        .keyboardType(.numberPad)
                        .monospaced()
                        .focused($amountFieldInFocus)
                        .onAppear(perform: {
                            amountFieldInFocus = true
                        })
                    Text("sats")
                        .monospaced()
                }
            } footer: {
                Text("The mint from which the ecash originates will charge fees for this operation")
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    let temp = fromMint
                    fromMint = toMint
                    toMint = temp
                    updateState()
                }) {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .disabled(toMint == nil)
            }
        }
        .onChange(of: fromMint, { oldValue, newValue in
            updateState()
        })
        .onChange(of: toMint, { oldValue, newValue in
            updateState()
        })
        .onChange(of: amountString, { oldValue, newValue in
            updateState()
        })
        .navigationTitle("Mint Swap")
        .navigationBarTitleDisplayMode(.inline)
        .alertView(isPresented: $showAlert, currentAlert: currentAlert)
        
        Spacer()
        
        Button(action: {
            swap()
        }, label: {
            HStack {
                switch state {
                case .ready, .fail, .none:
                    Text("Swap")
                case .loading:
                    ProgressView()
                    Spacer()
                        .frame(width: 10)
                    Text("Loading...")
                case .success:
                    Text("Success!")
                        .foregroundStyle(.green)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .bold()
            .foregroundColor(.white)
        })
        .buttonStyle(.bordered)
        .padding()
        .disabled(state != .ready)
        .opacity(state != .ready ? 0.5 : 1)
    }
    
    private func updateState() {
        if let toMint,
           let fromMint,
           toMint != fromMint,
           let amount,
           amount > 0 {
            state = .ready
        } else {
            state = .none
        }
    }
    
    private func swap() {
        amountFieldInFocus = false
        
        guard let fromMint, let toMint, let amount else {
            return
            // TODO: LOG ERROR
        }
        
        // start the actual swap...
        print("starting swap from \(fromMint.displayName) to \(toMint.displayName) with amount: \(amount)")
    }
    
    private func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}

#Preview {
    SwapView()
}
