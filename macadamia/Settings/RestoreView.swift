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
    @Environment(\.dismiss) private var dismiss
    
    @State var mnemonic = ""
    
    @State private var buttonState: ActionButtonState = .idle("")

    @State private var showAlert:Bool = false
    @State private var currentAlert:AlertDetail?

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
        .onAppear {
            buttonState = .idle("Restore", action: initiateRestore)
        }
        .navigationTitle("Restore")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .navigationBarBackButtonHidden(buttonState.type == .loading)
        .alertView(isPresented: $showAlert, currentAlert: currentAlert)
        
        ActionButton(state: $buttonState)
            .actionDisabled(mnemonic.isEmpty)
    }
     
    private func initiateRestore() {
        guard let activeWallet else {
            displayAlert(alert: AlertDetail(title: "No Wallet Initialized"))
            return
        }
        
        guard !activeWallet.mints.isEmpty else {
            displayAlert(alert: AlertDetail(title: "No Mints",
                                            description:"""
                                                        You need to add all the mints you want to restore ecash from. \
                                                        You can do so in the 'Mints' tab of the app.
                                                        """))
            logger.warning("user tried to restore wallet with no known mints. aborted.")
            restoreDidFail()
            return
        }
        
        if activeWallet.proofs.contains(where: { $0.state == .valid }) {
            displayAlert(alert: AlertDetail(title: "Wallet not empty!",
                                            description: """
                                                         This wallet still contains valid ecash \
                                                         that will become inaccessible if you restore now. \
                                                         Are you sure? 
                                                         """,
                                            primaryButton: AlertButton(title: "Restore", role: .destructive, action: {
                restore()
                return
            })))
        } else {
            restore()
        }
    }
    
    private func restore() {
        guard let mints = activeWallet?.mints.filter({ $0.hidden == false }) else {
            return
        }
        
        let words = mnemonic.components(separatedBy: CharacterSet.whitespacesAndNewlines)
        
        guard words.count == 12 else {
            logger.error("The entered test does not appear to be a properly formmatted seed phrase.")
            displayAlert(alert: AlertDetail(title: "Restore Error", description: "The entered text does not appear to be a properly formmatted seed phrase. Make sure its twelve words, separated by spaces or line breaks."))
            restoreDidFail()
            return
        }
        
        buttonState = .loading()
        
        macadamiaApp.restore(from: mints,
                             with: words) { result in
            switch result {
            case .success(let (proofs, newWallet, newMints, event)):
                
                insert(proofs + newMints + [newWallet, event])
                
                wallets.forEach({ $0.active = false })
                newWallet.active = true
                try? modelContext.save()
                
                buttonState = .success()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: { dismiss() })
            case .failure(let error):
                logger.error("restoring failed with error: \(error)")
                displayAlert(alert: AlertDetail(with: error))
                restoreDidFail()
            }
        }
    }
    
    private func restoreDidFail() {
        buttonState = .fail()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: {
            buttonState = .idle("Restore", action: initiateRestore)
        })
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
