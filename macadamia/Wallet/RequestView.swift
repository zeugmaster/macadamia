//
//  RequestView.swift
//  macadamia
//
//  Created by zm on 23.11.25.
//

import SwiftUI
import SwiftData
import CashuSwift

struct RequestView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var nostrService: NostrService
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]
    
    @Query private var allProofs:[Proof]
    @State private var showAlert: Bool = false
    @State private var currentAlert: AlertDetail?
    
    private var mintsInUse: [Mint] {
        if let activeWallet {
            return activeWallet.mints.filter({ !$0.hidden })
                                     .sorted { ($0.userIndex ?? 0) < ($1.userIndex ?? 0) }
        } else {
            return []
        }
    }
    
    private var activeWallet: Wallet? {
        wallets.first
    }
    
    private var doneButtonDisabled: Bool {
        false
    }
    
    var body: some View {
        List {
            
        }
        .navigationTitle("Payment Request")
        .alertView(isPresented: $showAlert, currentAlert: currentAlert)
    }
    
    
    
    private func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}

#Preview {
    RequestView()
}
