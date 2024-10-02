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
    @State private var activeWallet:Wallet?
    
    @State private var releaseNotesPopoverShowing = false
    @State private var selectedTab: Tab = .wallet
    @State private var walletNavigationTag: String?
    @State private var urlState: String?
    
    enum Tab {
        case wallet
        case mints
        case nostr
        case settings
    }
        
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            // FIXME: FOR SOME REASON TRACKING TAB SELECTION LEADS TO FUNNY BEHAVIOUR
            TabView {
                // First tab content
                WalletView(navigationTag:  .constant(nil), urlState: .constant(nil))
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
            activeWallet = wallets.first
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
//         if url.scheme == "cashu" {
//             let noURLPrefix = url.absoluteStringWithoutPrefix("cashu")
//             urlState = noURLPrefix
//             selectedTab = 0
//             walletNavigationTag = "Receive"
//         }
         print(url)
    }
}

#Preview {
    ContentView()
}
