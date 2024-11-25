//
//  RestoreView.swift
//  macadamia
//
//  Created by zeugmaster on 06.01.24.
//

import SwiftUI
import SwiftData
import CashuSwift
import BIP39

struct RestoreView: View {
    @State var mnemonic = ""
    @State var loading = false
    @State var success = false

    @State var showAlert:Bool = false
    @State var currentAlert:AlertDetail?

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]

    var activeWallet:Wallet? {
        get {
            wallets.first
        }
    }

    var body: some View {
        List {
            Section {
                TextField("Enter seed phrase", text: $mnemonic, axis: .vertical)
                    .lineLimit(4, reservesSpace: true)
            } footer: {
                Text("""
                     Enter your 12 word seed phrase, separated by spaces or line breaks. \
                     Please also make sure that your mint list contains all the mints you want to \
                     try restoring from.
                     """)
            }
        }
        Button(action: {
            attemptRestore()
        }, label: {
            HStack(spacing:0) {
                Spacer()
                if loading {
                    ProgressView()
                    Text("Restoring...")
                        .padding()
                } else if success {
                    Text("Done!")
                        .padding()
                        .foregroundColor(.green)
                } else {
                    Text("Restore")
                    .padding()
                }
                Spacer()
            }
        })
        .frame(maxWidth: .infinity)
        .foregroundColor(.white)
        .buttonStyle(.bordered)
        .padding()
        .bold()
        .toolbar(.hidden, for: .tabBar)
        .disabled(mnemonic.isEmpty || loading || success)
        .navigationTitle("Restore")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .navigationBarBackButtonHidden(loading)
        .alertView(isPresented: $showAlert, currentAlert: currentAlert)
    }
     
    private func attemptRestore() {
        guard let activeWallet else {
            displayAlert(alert: AlertDetail(title: "No Wallet",
                                           description: "."))
            return
        }
        
        if activeWallet.proofs.contains(where: { $0.state == .valid }) {
            displayAlert(alert: AlertDetail(title: "Wallet not empty!",
                                            description: """
                                                         This wallet still contains valid ecash \
                                                         that would become inaccessible if you restore now. \
                                                         Please empty the wallet first.
                                                         """))
            return
        }
        
        guard !activeWallet.mints.isEmpty else {
            displayAlert(alert: AlertDetail(title: "No Mints",
                                            description:"""
                                                        You need to add all the mints you want to restore ecash from. \
                                                        You can do so in the 'Mints' tab of the app.
                                                        """))
            logger.warning("user tried to restore wallet with no known mints. aborted.")
            return
        }
        
        Task {
            do {
                loading = true

                try await initiateRestore(mints: activeWallet.mints)

                success = true
                loading = false
            } catch {
                displayAlert(alert: AlertDetail(title: "Error",
                                                description: """
                                                             There was an error when attempting to restore. \
                                                             Detail: \(String(describing: error))
                                                             """))
                loading = false
            }
        }
    }
    
    private func initiateRestore(mints: [Mint]) async throws {
        let words = mnemonic.components(separatedBy: CharacterSet.whitespacesAndNewlines)
        
        guard words.count == 12 else {
            throw CashuError.restoreError("Could not convert text input to twelve word seed phrase. Please try again.")
        }
        
        guard let mnemo = try? Mnemonic(phrase: words) else {
            throw CashuError.restoreError("Could not generate seed from text input. Please try again.")
        }
        
        let seed = String(bytes: mnemo.seed)
        
        let newWallet = Wallet(mnemonic: mnemo.phrase.joined(separator: " "),
                               seed: seed)
                
        for mint in mints {
            let newMint = Mint(url: mint.url, keysets: mint.keysets)
            newMint.userIndex = mint.userIndex
            newMint.nickName = mint.nickName
            
            let results = try await CashuSwift.restore(mint: newMint,
                                                        with: seed)
            
            modelContext.insert(newWallet)
            
            modelContext.insert(newMint)
            
            for result in results {
                let fee = newMint.keysets.first(where: { $0.keysetID == result.keysetID })?.inputFeePPK ?? 0 // FIXME: ugly
                
                let internalProofs = result.proofs.map({ p in
                    Proof(p,
                          unit: Unit(result.unitString) ?? .sat,
                          inputFeePPK: fee,
                          state: .valid,
                          mint: newMint,
                          wallet: newWallet)
                })
                
                newMint.increaseDerivationCounterForKeysetWithID(result.keysetID,
                                                                 by: result.derivationCounter)
                
                print("newMint.keyset derivation counter: \(newMint.keysets.map({ $0.derivationCounter }))")
                                
                newMint.proofs?.append(contentsOf: internalProofs)
                
                newWallet.proofs.append(contentsOf: internalProofs)
            }
            newWallet.mints.append(newMint)
            newMint.wallet = newWallet
        }
        
        wallets.forEach({ $0.active = false })
        
        newWallet.active = true
        
        let event = Event.restoreEvent(shortDescription: "Restore",
                                       wallet: newWallet,
                                       longDescription: """
                                                        Successfulle recovered ecash \
                                                        from \(newWallet.mints.count) mints \
                                                        using a seed phrase! 🤠
                                                        """)
        modelContext.insert(event)
                
        try modelContext.save()
    }

    private func displayAlert(alert:AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}

#Preview {
    RestoreView()
}
