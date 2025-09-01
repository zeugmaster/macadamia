//
//  MessageMintList.swift
//  macadamiaMessages
//
//  Created by zm on 01.09.25.
//

import SwiftUI
import SwiftData
import CashuSwift
import UIKit
import Messages

extension Notification.Name {
    static let messageSelected = Notification.Name("messageSelected")
}

struct MessageMintList: View {
    weak var vc: MessagesViewController?
    
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]
    
    @State private var selectedToken: String?
    
    private var activeWallet: Wallet? {
        wallets.first
    }
    
    private var mints: [Mint] {
        activeWallet?.mints.filter({ $0.hidden == false })
            .sorted { ($0.userIndex ?? Int.max) < ($1.userIndex ?? Int.max) } ?? []
    }

    var body: some View {
        Group {
            if let token = selectedToken {
                TokenDisplayView(vc: vc, tokenString: token) {
                    selectedToken = nil
                }
            } else {
                NavigationStack {
                    List {
                        ForEach(mints) { mint in
                            NavigationLink {
                                MessageSendView(mint: mint, vc: vc)
                            } label: {
                                MintRow(mint: mint)
                            }
                        }
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .messageSelected)) { notification in
            if let tokenString = notification.object as? String {
                selectedToken = tokenString
            }
        }
    }
    
    func showToken(_ tokenString: String) {
        selectedToken = tokenString
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
    let mint: Mint
    weak var vc: MessagesViewController?
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var memo: String = ""
    @State private var amountString: String = ""
    @State private var buttonState = ActionButtonState.idle("...")
    
    @FocusState private var amountFieldInFocus
    
    private var buttonDisabled: Bool {
        amount > 0 ? false : true && amount >= mint.balance(for: .sat)
    }
    
    private var amount: Int {
        Int(amountString) ?? 0
    }
    
    var body: some View {
        ZStack {
            List {
                HStack {
                    TextField("Enter amount...", text: $amountString)
                        .keyboardType(.numberPad)
                        .focused($amountFieldInFocus)
                    Spacer()
                    Text("sat")
                }
                .monospaced()
                TextField("Optional memo...", text: $memo)
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
        
        guard let proofs = mint.select(amount: amount, unit: .sat) else {
            return
        }
        
        mint.send(proofs: proofs.selected,
                  targetAmount: amount,
                  memo: memo,
                  completion: { result in
            switch result {
            case .success(let success):
                buttonState = .success()
                onSuccess(token: success.token, event: success.event, swapped: success.swapped)
            case .failure(let error):
                buttonState = .fail()
                print("send failed due to error: \(error)")
            }
        })
    }
    
    private func onSuccess(token: CashuSwift.Token, event: Event, swapped: [Proof]) {
        AppSchemaV1.insert(swapped + [event], into: modelContext)
        
        vc?.requestPresentationStyle(.compact)
        
        do {
            let message = try message(for: token)
            
            vc?.activeConversation?.insert(message)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                dismiss()
            }
        } catch {
            buttonState = .fail("Token Error")
            print("error when generating message: \(error)")
        }
    }
    
    private func message(for token: CashuSwift.Token) throws -> MSMessage {
        let tokenString = try token.serialize(to: .V4)
        
        guard let url = URL(string: "data:\(tokenString)") else {
            throw CashuError.unknownError("could not create URL from token")
        }
        
        let message = MSMessage()
        message.url = url
        
        let layout = MSMessageTemplateLayout()
        layout.image = UIImage(named: "message-banner")
        layout.caption = amountDisplayString(token.sum(), unit: .sat)
        layout.subcaption = token.memo
        
        message.layout = layout
        return message
    }
}

struct TokenDisplayView: View {
    weak var vc: MessagesViewController?
    
    let tokenString: String
    let onDismiss: () -> Void
    
    @State private var copied = false
    
    private var amount: Int? {
        try? tokenString.deserializeToken().sum()
    }
    
    private var memo: String? {
        try? tokenString.deserializeToken().memo
    }
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Button("Back") {
                    onDismiss()
                }
                Spacer()
                Text("Ecash Token")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button("    ") { }
                    .disabled(true)
                    .opacity(0)
            }
            .padding(.horizontal)
            
            List {
                Section {
                    Text(tokenString)
                        .monospaced()
                        .lineLimit(1)
                    if let amount {
                        Text(amountDisplayString(amount, unit: .sat))
                            .monospaced()
                    }
                    if let memo {
                        Text(memo)
                    }
                }
                .foregroundStyle(.secondary)
                Section {
                    Button {
                        UIPasteboard.general.string = tokenString
                        withAnimation {
                            copied = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                            withAnimation {
                                copied = false
                            }
                        }
                    } label: {
                        HStack {
                            Text(copied ? "Copied!" : "Copy")
                            Spacer()
                            Image(systemName: "clipboard")
                        }
                    }
                    Button {
                        guard let url = URL(string: "cashu:\(tokenString)") else {
                            return
                        }
                        vc?.extensionContext?.open(url)
                    } label: {
                        HStack {
                            Text("Open in Wallet")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                        }
                    }
                }
            }
            Spacer()
        }
    }
}
