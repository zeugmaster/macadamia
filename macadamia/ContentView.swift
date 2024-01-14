//
//  ContentView.swift
//  macadamia
//
//

import SwiftUI

struct ContentView: View {
    
    var body: some View {
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
            
        }.persistentSystemOverlays(.hidden)
            .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
}
