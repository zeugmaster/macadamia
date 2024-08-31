//
//  macadamiaApp.swift
//  macadamia
//
//

import SwiftUI
import SwiftData

@main
struct macadamiaApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Wallet.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            TabView {
                ContentView()
                    .tabItem {
                        Text("overview")
                    }
            }
        }
        .modelContainer(sharedModelContainer)
    }
}
