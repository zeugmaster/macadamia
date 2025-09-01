//
//  MessageMintList.swift
//  macadamiaMessages
//
//  Created by zm on 01.09.25.
//

import SwiftUI
import SwiftData
import CashuSwift
import Messages

struct MessageMintList: View {
    weak var delegate: MessagesViewController?
    var mint: Mint?
    
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]
    
    private var activeWallet: Wallet? {
        wallets.first
    }
    
    private var mints: [Mint] {
        activeWallet?.mints.filter({ $0.hidden == false })
            .sorted { ($0.userIndex ?? Int.max) < ($1.userIndex ?? Int.max) } ?? []
    }

    var body: some View {
        List {
            Section {
                ForEach(mints) { mint in
                    NavigationLink {
                        MessageSendView(delegate: delegate,
                                        mint: mint)
                    } label: {
                        MintRow(mint: mint)
                    }
                }
            } header: {
                Text("Pay from")
            }
        }
    }
}

struct MintRow: View {
    let mint: Mint
    
    var body: some View {
        HStack {
            Text(mint.displayName)
            Spacer()
            Text(amountDisplayString(mint.balance(for: .sat), unit: .sat))
                .monospaced()
        }
        .bold()
    }
}

struct MessageSendView: View {
    weak var delegate: MessagesViewController?
    let mint: Mint
    
    @State private var memo: String = ""
    @State private var amountString: String = ""
    @State private var buttonState = ActionButtonState.idle("...")
    
    @FocusState private var amountFieldInFocus
    
    private var buttonDisabled: Bool {
        amount > 0 ? false : true
    }
    
    private var amount: Int {
        Int(amountString) ?? 0
    }
    
    var body: some View {
        ZStack {
            Form {
                Section {
                    HStack {
                        TextField("Enter amount...", text: $amountString)
                            .keyboardType(.numberPad)
                            .focused($amountFieldInFocus)
                        Spacer()
                        Text("sat")
                    }
                    .monospaced()
                }
                Section {
                    TextField("Optional memo...", text: $memo)
                }
                Spacer(minLength: 50)
                    .listRowBackground(Color.clear)
            }
            VStack {
                Spacer()
                ActionButton(state: $buttonState)
                    .actionDisabled(buttonDisabled)
            }
        }
        .onAppear {
            buttonState = .idle("Send", action: createToken)
            amountFieldInFocus = true
        }
    }
    
    private func createToken() {
        buttonState = .loading()
        
        //....
        print("create token ....")
    }
    
    private func message(for token: CashuSwift.Token) throws -> MSMessage {
        let tokenString = try token.serialize(to: .V4)
        
        let message = MSMessage()
        message.url = URL(string: "macadamia-message:\(tokenString)")
        
        let layout = MSMessageTemplateLayout()
        layout.image = UIImage(named: "message-banner")
        layout.caption = amountDisplayString(token.sum(), unit: .sat)
        layout.subcaption = token.memo
        
        message.layout = layout
        return message
    }
}


