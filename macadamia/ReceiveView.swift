//
//  ReceiveView.swift
//  macadamia
//
//  Created by zeugmaster on 05.01.24.
//

import SwiftUI
import SwiftData
import CashuSwift

struct ReceiveView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var wallets: [Wallet]
    
    var activeWallet:Wallet? {
        get {
            wallets.first
        }
    }
    
    @ObservedObject var qrsVM = QRScannerViewModel()
    
    @State var tokenString:String?
    @State var token:CashuSwift.Token?
    @State var tokenMemo:String?
    @State var unit:Unit = .other
    @State var loading = false
    @State var success = false
    @State var totalAmount:Int?
    @State var addingMint = false
    
//    @State var refreshCounter:Int = 0
    
    @State var showAlert:Bool = false
    @State var currentAlert:AlertDetail?
    
    private var navigationPath:Binding<NavigationPath>?
    
    init(tokenString: String? = nil, navigationPath:Binding<NavigationPath>? = nil) {
        self.navigationPath = navigationPath
        self.tokenString = tokenString
    }
    
    var body: some View {
        VStack {
            List {
                if tokenString != nil {
                    Section {
                        TokenText(text: tokenString!)
                            .frame(idealHeight: 70)
                        // TOTAL AMOUNT
                        HStack {
                            Text("Total Amount: ")
                            Spacer()
                            Text(String(totalAmount ?? 0) + " sats")
                        }
                        .foregroundStyle(.secondary)
                        // TOKEN MEMO
                        if tokenMemo != nil {
                            if !tokenMemo!.isEmpty {
                                Text("Memo: \(tokenMemo!)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                         Text("cashu Token")
                    }
                    if token != nil && activeWallet != nil {
                        ForEach(token!.token, id: \.proofs.first?.C) { fragment in
                            Section {
                                TokenFragmentView(activeWallet: activeWallet!, fragment: fragment, unit: .other)
                            }
                        }
                    }
                    
                    Section {
                        Button {
                            reset()
                            qrsVM.restart()
                        } label: {
                            HStack {
                                Text("Reset")
                                Spacer()
                                Image(systemName: "trash")
                            }
                        }
                        .disabled(addingMint)
                    }
                } else {
                    
                    //MARK: This check is necessary to prevent a bug in URKit (or the system, who knows)
                    //MARK: from crashing the app when using the camera on an Apple Silicon Mac
                    
                    if !ProcessInfo.processInfo.isiOSAppOnMac {
                        QRScanner(viewModel: qrsVM)
                            .frame(minHeight: 300, maxHeight: 400)
                            .padding(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
                    }
                    
                    Button {
                        paste()
                    } label: {
                        HStack {
                            Text("Paste from clipboard")
                            Spacer()
                            Image(systemName: "list.clipboard")
                        }
                    }
                }
            }
            .onAppear(perform: {
                qrsVM.onResult = scannerDidDecodeString(_:)
            })
            .alertView(isPresented: $showAlert, currentAlert: currentAlert)
            .navigationTitle("Receive")
            .toolbar(.hidden, for: .tabBar)
            Button(action: {
                redeem()
            }, label: {
                if loading {
                    Text("Sending...")
                        .frame(maxWidth: .infinity)
                        .padding()
                } else if success {
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
            .disabled(tokenString == nil || loading || success || addingMint)
        }
    }
    
    // MARK: - LOGIC
    
    func paste() {
        let pasteString = UIPasteboard.general.string ?? ""
        // TODO: NEEDS TO CHECK AND ALERT USER IF PAST OP IS UNSUCCESSFUL
        tokenString = pasteString
        parseTokenString()
    }
    
    func scannerDidDecodeString(_ string:String) {
        tokenString = string
    }
    
    func parseTokenString() {
        guard let tokenString,
              !tokenString.isEmpty else {
                return
          }
        do {
            token = try tokenString.deserializeToken()
        } catch {
            displayAlert(alert: AlertDetail(title: "Could not decode token",
                                            description: String(describing: error)))
        }
        
    }

    func redeem() {
        guard let activeWallet, let token else {
            return
        }
        
        let mintsInToken = activeWallet.mints.filter { mint in
            token.token.contains { fragment in
                mint.url.absoluteString == fragment.mint
            }
        }
        
        guard mintsInToken.count == token.token.count else {
            // TODO: throw an error
            displayAlert(alert: AlertDetail(title: "Unable to redeem",
                                            description: "Are all mints from this token known to the wallet?"))
            return
        }
        
        loading = true
        
        var proofs:[Proof] = []
        
        Task {
            do {
                let proofsDict = try await mintsInToken.receive(token: token, seed:activeWallet.seed)
                mintsInToken.forEach { mint in
                    let proofsPerMint = proofsDict[mint.url.absoluteString]!
                    let internalProofs = proofsPerMint.map { p in
                        Proof(p, unit: Unit(token.unit) ?? .other, state: .valid, mint: mint, wallet: activeWallet)
                    }
                    proofs.append(contentsOf: internalProofs)
                }
                proofs.forEach({ modelContext.insert($0) })
                try modelContext.save()
                self.loading = false
                self.success = true
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    if var navigationPath {
                        #warning("pretty sure this does nothing in the UI")
                                  if !navigationPath.wrappedValue.isEmpty {
                            navigationPath.wrappedValue.removeLast()
                        }
                    }
                }
                
            } catch {
                // receive unsuccessful
                displayAlert(alert: AlertDetail(title: "Unable to redeem",
                                                description: String(describing: error)))
                self.loading = false
                self.success = false
            }
        }
    }
    
    func reset() {
        tokenString = nil
        tokenMemo = nil
        token = nil
        tokenMemo = nil
        success = false
        addingMint = false
    }
    
    private func displayAlert(alert:AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}

struct TokenFragmentView: View {
    
    enum FragmentState {
        case spendable
        case notSpendable
        case mintUnavailable
    }
    
    @Environment(\.modelContext) private var modelContext
    
    @State var fragmentState:FragmentState = .mintUnavailable
    @State var fragment:CashuSwift.ProofContainer
    @State var amount:Int = 0 // will need to change to decimal representation
    @State var unit:Unit = .other
    @State var addingMint:Bool = false
    
    @State var unknownMint:Bool?
    
    var activeWallet:Wallet
    
    init(activeWallet:Wallet, fragment:CashuSwift.ProofContainer, unit:Unit) {
        self.activeWallet = activeWallet
        self.fragment = fragment
        self.unit = unit
    }
    
    var body: some View {
        HStack {
            Text("Amount:")
            Spacer()
            Text(String(amount))
            switch unit {
            case .sat:
                Text("sat")
            case .usd:
                Text("$")
            case .eur:
                Text("€")
            case .other:
                Text("other")
            }
        }
        .onAppear {
            checkFragmentState()
        }
        switch fragmentState {
        case .spendable:
            Text("Token part is valid.")
        case .notSpendable:
            Text("Token part is invalid.")
        case .mintUnavailable:
            Text("Mint unavailable")
        }
        if let unknownMint {
            if unknownMint {
                Button {
                    addMint()
                } label: {
                    if addingMint {
                        Text("Adding,,,") // TODO: communicate success or failure to the user
                    } else {
                        Text("Unknowm mint. Add it?")
                    }
                }
                .disabled(addingMint)
            }
        } else {
            Text("Checking mint...")
        }
    }
    
    func checkFragmentState() {
        guard let url = URL(string: fragment.mint) else {
            fragmentState = .mintUnavailable
            return
        }
        
        if activeWallet.mints.contains(where: { $0.url == url }) {
            unknownMint = false
        } else {
            unknownMint = true
        }
        
        Task {
            do {
                let proofStates = try await CashuSwift.check(fragment.proofs, url: url)
                if proofStates.allSatisfy({ $0 == .unspent }) {
                    fragmentState = .spendable
                } else {
                    fragmentState = .notSpendable
                }
            } catch {
                fragmentState = .mintUnavailable
            }
        }
    }
    
    func addMint() {
        Task {
            do {
                addingMint = true
                guard let url = URL(string: fragment.mint) else {
                    addingMint = false
                    return
                }
                let mint:Mint = try await CashuSwift.loadMint(url: url, type: Mint.self)
                mint.wallet = activeWallet
                mint.proofs = []
                modelContext.insert(mint)
                try modelContext.save()
                unknownMint = false
                checkFragmentState()
            } catch {
                print("Could not add mint")
                unknownMint = true
            }
            addingMint = false
        }
    }
}


#Preview {
    ReceiveView()
}
