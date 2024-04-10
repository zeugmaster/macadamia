//
//  ContentView.swift
//  macadamia
//
//

import SwiftUI

struct ContentView: View {
    @State private var releaseNotesPopoverShowing = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView {
                // First tab content
                WalletView()
                    .tabItem {
                        Label("Wallet", systemImage: "bitcoinsign.circle")
                    }
                
                // Second tab content
                NostrInboxView()
                    .tabItem {
                        Image(systemName: "person.2")
                        Text("nostr")
                    }
                    
                // Third tab content
                SettingsView()
                    .tabItem {
                        Image(systemName: "gear")
                        Text("Settings")
                    }.navigationTitle("Title")
                
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
        //FIXME: for some reason calling .onChange here messes up the view beneath,
        // which does not show the balance anymore... weird
    }
    
    func checkReleaseNotes() {
        let releaseNotesSeenHash = UserDefaults.standard.string(forKey: "LastReleaseNotesAcknoledgedHash")
        if releaseNotesSeenHash ?? "not set" != ReleaseNote.hashString() {
            releaseNotesPopoverShowing = true
            UserDefaults.standard.setValue(ReleaseNote.hashString(), 
                                           forKey: "LastReleaseNotesAcknoledgedHash")
        }
    }
}

#Preview {
    ContentView()
}
