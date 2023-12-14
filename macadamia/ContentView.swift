//
//  ContentView.swift
//  macadamia
//
//  Created by Dario Lass on 13.12.23.
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
            ContactsView()
                .tabItem {
                    Image(systemName: "person.2")
                    Text("nostr")
                }
                .badge(1)
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

//extension ContentView {
//    @MainActor class ViewModel: ObservableObject {
//        var wallet:Wallet
//        
////        @Published var balance:Int
//        
//        init(wallet: Wallet) {
//            self.wallet = wallet
//        }
//        
//        func prepare() {
//            Task {
//                do {
//                    try await wallet.updateMints()
//                } catch {
//                    
//                }
//            }
//            
//        }
//    }
//}
