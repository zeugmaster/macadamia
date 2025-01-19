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
        .navigationTitle("Restore")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .navigationBarBackButtonHidden(loading)
        .alertView(isPresented: $showAlert, currentAlert: currentAlert)
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
    }
     
    private func attemptRestore() {
        guard let activeWallet else {
            displayAlert(alert: AlertDetail(title: "No Wallet",
                                           description: "."))
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
        
        if activeWallet.proofs.contains(where: { $0.state == .valid }) {
            displayAlert(alert: AlertDetail(title: "Wallet not empty!",
                                            description: """
                                                         This wallet still contains valid ecash \
                                                         that will become inaccessible if you restore now. \
                                                         Are you sure? 
                                                         """,
                                            primaryButtonText: "Cancel",
                                            affirmText: "Restore",
                                            onAffirm: {
                restore()
                return
            }))
        } else {
            restore()
        }
    }
    
    private func restore() {
        guard let mints = activeWallet?.mints else {
            return
        }
        
        let words = mnemonic.components(separatedBy: CharacterSet.whitespacesAndNewlines)
        
        guard words.count == 12 else {
            logger.error("The entered test does not appear to be a properly formmatted syeed phrase.")
            displayAlert(alert: AlertDetail(title: "Restore Error", description: "The entered text does not appear to be a properly formmatted seed phrase. Make sure its twelve words, separated by spaces or line breaks."))
            return
        }
        
        loading = true
                
        // TODO: insert wallet, new mints, proofs.
        
        macadamiaApp.restore(from: mints,
                             with: words) { result in
            switch result {
            case .success(let (proofs, newWallet, newMints, event)):
                
                insert(proofs + newMints + [newWallet, event])
                
                wallets.forEach({ $0.active = false })
                newWallet.active = true
                try? modelContext.save()
                
                success = true
                loading = false

            case .failure(let error):
                logger.error("restoring failed with error: \(error)")
                displayAlert(alert: AlertDetail(with: error))
                loading = false
                success = false
            }
        }
        
        // TODO: auto dismiss view
                
    }
    
    @MainActor
    func insert(_ models: [any PersistentModel]) {
        models.forEach({ modelContext.insert($0) })
        do {
            try modelContext.save()
            logger.info("successfully added \(models.count) object\(models.count == 1 ? "" : "s") to the database.")
        } catch {
            logger.error("Saving SwiftData model context failed with error: \(error)")
        }
    }

    private func displayAlert(alert:AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}

#Preview {
    RestoreView()
}
