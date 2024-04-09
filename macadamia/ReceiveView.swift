//
//  ReceiveView.swift
//  macadamia
//
//  Created by zeugmaster on 05.01.24.
//

import SwiftUI

struct ReceiveView: View {
    @StateObject var vm = ReceiveViewModel()
        
    var body: some View {
        VStack {
            List {
                if vm.token != nil {
                    Section {
                        // TOKEN STRING
//                        Text(vm.token!)
//                            .lineLimit(5, reservesSpace: true)
//                            .monospaced()
//                            .foregroundStyle(.secondary)
//                            .disableAutocorrection(true)
                        TokenText(text: vm.token!)
                            .frame(idealHeight: 70)
                        // TOTAL AMOUNT
                        HStack {
                            Text("Total Amount: ")
                            Spacer()
                            Text(String(vm.totalAmount ?? 0) + " sats")
                        }
                        .foregroundStyle(.secondary)
                        // TOKEN MEMO
                        if vm.tokenMemo != nil {
                            if !vm.tokenMemo!.isEmpty {
                                Text("Memo: \(vm.tokenMemo!)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                         Text("cashu Token")
                    }
                    if !vm.tokenParts.isEmpty {
                        ForEach(vm.tokenParts, id: \.self) {part in
                            Section {
                                Text("Mint: " + part.token.mint.dropFirst(8))
                                    .foregroundStyle(.secondary)
                                switch part.state {
                                case .mintUnavailable:
                                    Text("Mint unavailable")
                                case .notSpendable:
                                    Text("Token not spendable")
                                case .spendable:
                                    EmptyView()
                                case .unknown:
                                    Text("Checking...")
                                }
                                if vm.tokenParts.count > 1 {
                                    HStack {
                                        Text("Amount: ")
                                        Spacer()
                                        Text(String(part.amount) + " sats")
                                    }
                                }
                                if (part.knownMint == false && part.state != .mintUnavailable) {
                                    Button {
                                        vm.addUnknownMint(for: part)
                                    } label: {
                                        HStack {
                                            if part.addingMint {
                                                Text("Adding...")
                                            } else {
                                                Text("Unknown mint. Add it?")
                                                Spacer()
                                                Image(systemName: "plus")
                                            }
                                        }
                                    }
                                    .disabled(part.addingMint || part.state == .mintUnavailable || part.state == .unknown)
                                }
                            }
                        }
                    }
                    
                    Section {
                        Button {
                            vm.reset()
                        } label: {
                            HStack {
                                Text("Reset")
                                Spacer()
                                Image(systemName: "trash")
                            }
                        }
                        .disabled(vm.addingMint)
                    }
                } else {
                    Button {
                        vm.paste()
                    } label: {
                        HStack {
                            Text("Paste from clipboard")
                            Spacer()
                            Image(systemName: "list.clipboard")
                        }
                    }
                }
            }
            .alert(vm.currentAlert?.title ?? "Error", isPresented: $vm.showAlert) {
                Button(role: .cancel) {
                    
                } label: {
                    Text(vm.currentAlert?.primaryButtonText ?? "OK")
                }
                if vm.currentAlert?.onAffirm != nil &&
                    vm.currentAlert?.affirmText != nil {
                    Button(role: .destructive) {
                        vm.currentAlert!.onAffirm!()
                    } label: {
                        Text(vm.currentAlert!.affirmText!)
                    }
                }
            } message: {
                Text(vm.currentAlert?.alertDescription ?? "")
            }
            .navigationTitle("Receive")
            .toolbar(.hidden, for: .tabBar)
            .onAppear(perform: {
                vm.token = "cashuAeyJ0b2tlbiI6W3sicHJvb2ZzIjpbeyJpZCI6IjAwYThjZDljNjViNDNlM2YiLCJhbW91bnQiOjQsIkMiOiIwMmIxOWJmMWI3N2NkOTA1Mjk1YTg0OTFhOTExYzFhMzg3NWQwYWZjZDc5OWQzYzYwZDU0YmNlZGJhNmI0ZDQ3YTAiLCJzZWNyZXQiOiIxYzRjMzcyNjBlMTNkNzJiYzZhNWFmZmU4YzMzZTcwOTVjYTZlZGJmZDk2NDMzYjhlMmExYzlkYTM1OWJjOTEzIn0seyJpZCI6IjAwYThjZDljNjViNDNlM2YiLCJhbW91bnQiOjE2LCJDIjoiMDM1Mjk5MGM3ODdhOTMzYTI5YTM2Mzg1YjMxMzBhMmVjMTE4NDVhNTcwNmMwZWY4NDEyMDUyNWJhY2NmNTUyZjk3Iiwic2VjcmV0IjoiYzFkMGMyODJiMWVhNTkyMjM4YzgxOTIxZjQ0N2RhNGM0ZmM0N2ViMjExMDM0NzBhYzAxMDRjZGY2YTVkNTdiOSJ9XSwibWludCI6Imh0dHBzOi8vbWludC5tYWNhZGFtaWEuY2FzaCJ9XX0="
            })
            Button(action: {
                vm.redeem()
            }, label: {
                if vm.loading {
                    Text("Sending...")
                        .frame(maxWidth: .infinity)
                        .padding()
                } else if vm.success {
                    Text("Done!")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .foregroundColor(.green)
                } else {
                    Text("Redeem")
                    .frame(maxWidth: .infinity)
                    .padding()
                }
            })
            .foregroundColor(.white)
            .buttonStyle(.bordered)
            .padding()
            .bold()
            .toolbar(.hidden, for: .tabBar)
            .disabled(vm.token == nil || vm.loading || vm.success || vm.addingMint)
        }
    }
}

#Preview {
    ReceiveView()
        
}

@MainActor
class ReceiveViewModel: ObservableObject {
    
    @Published var token:String?
    @Published var tokenParts = [TokenPart]()
    @Published var tokenMemo:String?
    @Published var loading = false
    @Published var success = false
    @Published var totalAmount:Int?
    @Published var addingMint = false
    
    @Published var refreshCounter:Int = 0
    
    @Published var showAlert:Bool = false
    var currentAlert:AlertDetail?
    var wallet = Wallet.shared
    
    func paste() {
        let pasteString = UIPasteboard.general.string ?? ""
        parseToken(token: pasteString)
    }
    
    func parseToken(token:String) {
        let deserialized:Token_Container
        
        do {
            deserialized = try wallet.deserializeToken(token: token)
        } catch {
            displayAlert(alert: AlertDetail(title: "Invalid token",
                                            description: "This token could not be read. Input: \(token.prefix(20))... Error: \(String(describing: error))"))
            return
        }
        
        self.token = token
        tokenMemo = deserialized.memo
        
        tokenParts = []
        totalAmount = 0
        for token in deserialized.token {
            let tokenAmount = amountForToken(token: token)
            let known = wallet.database.mints.contains(where: { $0.url.absoluteString.contains(token.mint) })
            let part = TokenPart(token: token, knownMint: known, amount: tokenAmount)
            tokenParts.append(part)
            totalAmount! += tokenAmount
        }
        for part in tokenParts {
            checkTokenState(for: part)
        }
    }
    
    func amountForToken(token:Token_JSON) -> Int {
        var total = 0
        for proof in token.proofs {
            total += proof.amount
        }
        return total
    }
    
    func checkTokenState(for tokenPart:TokenPart) {
        Task {
            do {
                let spendable = try await wallet.checkTokenStateSpendable(for:tokenPart.token)
                if spendable {
                    tokenPart.state = .spendable
                    print("token is spendable")
                } else {
                    tokenPart.state = .notSpendable
                    print("token is NOT spendable")
                }
            } catch {
                tokenPart.state = .mintUnavailable
                print("mint unavailable " + tokenPart.token.mint)
            }
            refreshCounter += 1
        }
    }
    
    func addUnknownMint(for tokenPart:TokenPart) {
        Task {
            guard let url = URL(string: tokenPart.token.mint) else {
                return
            }
            tokenPart.addingMint = true
            addingMint = true
            do {
                try await wallet.addMint(with:url)
                tokenPart.knownMint = true
                tokenPart.addingMint = false
                addingMint = false
            } catch {
                displayAlert(alert: AlertDetail(title: "Could not add mint", 
                                                description: String(describing: error)))
                tokenPart.addingMint = false
                addingMint = false
            }
        }
    }

    func redeem() {
        guard !tokenParts.contains(where: { $0.state == .notSpendable }) else {
            displayAlert(alert: AlertDetail(title: "Unable to redeem", description: "One or more parts of this token are not spendable. macadamia does not yet support redeeming only parts of a token."))
            return
        }
        loading = true
        Task {
            do {
                try await wallet.receiveToken(tokenString: token!)
                self.loading = false
                self.success = true
            } catch {
                displayAlert(alert: AlertDetail(title: "Redeem failed",
                                               description: String(describing: error)))
                self.loading = false
                self.success = false
            }
        }
    }
    
    func reset() {
        token = nil
        tokenMemo = nil
        tokenParts = []
        tokenMemo = nil
        success = false
        addingMint = false
    }
    
    private func displayAlert(alert:AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}

enum TokenPartState {
    case spendable
    case notSpendable
    case mintUnavailable
    case unknown
}

class TokenPart:ObservableObject, Hashable {
    
    @Published var token:Token_JSON
    @Published var knownMint:Bool
    @Published var amount:Int
    @Published var addingMint:Bool
    @Published var state:TokenPartState
    
    static func == (lhs: TokenPart, rhs: TokenPart) -> Bool {
            lhs.token.proofs == rhs.token.proofs
        }
    
    func hash(into hasher: inout Hasher) {
        for proof in token.proofs {
            hasher.combine(proof.C)
        }
    }
    
    init(token: Token_JSON, 
         knownMint: Bool,
         amount: Int,
         addingMint: Bool = false,
         state:TokenPartState = .unknown) {
        self.token = token
        self.knownMint = knownMint
        self.amount = amount
        self.addingMint = addingMint
        self.state = state
    }
}
