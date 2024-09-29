//
//  ContentView.swift
//  macadamia
//
//

import SwiftUI
import SwiftData
import BIP39

struct ContentView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Query private var wallets: [Wallet]
    
    
    var activeWallet:Wallet? {
        get {
            wallets.first
        }
    }
    
    @State private var releaseNotesPopoverShowing = false
    @State private var selectedTab: Int = 0
    @State private var walletNavigationTag: String?
    @State private var urlState: String?
        
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $selectedTab) {
                // First tab content
                WalletView(navigationTag:  $walletNavigationTag, urlState: $urlState)
                    .tabItem {
                        Label("Wallet", systemImage: "bitcoinsign.circle")
                    }
                    .tag(0)
                
                MintManagerView()
                    .tabItem {
                        Image(systemName: "building.columns")
                        Text("Mints")
                    }
                
                // Second tab content
//                NostrInboxView()
//                    .tabItem {
//                        Image(systemName: "person.2")
//                        Text("nostr")
//                    }
//                    .tag(1)
                    
                // Third tab content
                SettingsView()
                    .tabItem {
                        Image(systemName: "gear")
                        Text("Settings")
                    }
                    .tag(2)
                
            }
            .persistentSystemOverlays(.hidden)
            .background(Color.black)
        }
        .ignoresSafeArea()
        .onAppear(perform: {
            checkReleaseNotes()
            if wallets.isEmpty {
                initializeWallet()
            }
        })
        .popover(isPresented: $releaseNotesPopoverShowing, content: {
            ReleaseNoteView()
            Text("Swipe down to dismiss")
                .foregroundStyle(.secondary)
                .font(.footnote)
        })
        .preferredColorScheme(.dark)
        .onOpenURL () { url in
            handleUrl(url)
        }
    }
    
    private func initializeWallet() {
        let seed = String(bytes: Mnemonic().seed)
        let wallet = Wallet(seed: seed)
        modelContext.insert(wallet)
        try? modelContext.save()
    }
    
    func checkReleaseNotes() {
        let releaseNotesSeenHash = UserDefaults.standard.string(forKey: "LastReleaseNotesAcknoledgedHash")
        if releaseNotesSeenHash ?? "not set" != ReleaseNote.hashString() {
            releaseNotesPopoverShowing = true
            UserDefaults.standard.setValue(ReleaseNote.hashString(), 
                                           forKey: "LastReleaseNotesAcknoledgedHash")
        }
    }
     func handleUrl(_ url: URL) {
         if url.scheme == "cashu" {
             let noURLPrefix = url.absoluteStringWithoutPrefix("cashu")
             urlState = noURLPrefix
             selectedTab = 0
             walletNavigationTag = "Receive"
         }
    }
}

#Preview {
    ContentView()
}
