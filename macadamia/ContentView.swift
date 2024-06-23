//
//  ContentView.swift
//  macadamia
//
//

import SwiftUI

struct ContentView: View {
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
                
                // Second tab content
                NostrInboxView()
                    .tabItem {
                        Image(systemName: "person.2")
                        Text("nostr")
                    }
                    .tag(1)
                    
                // Third tab content
                SettingsView()
                    .tabItem {
                        Image(systemName: "gear")
                        Text("Settings")
                    }
                    .tag(2)
                    .navigationTitle("Title")
                
            }
            .persistentSystemOverlays(.hidden)
            .background(Color.black)
        }
        .ignoresSafeArea()
        .onAppear(perform: {
            checkReleaseNotes()
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
