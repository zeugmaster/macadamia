import SwiftData
import SwiftUI
import OSLog

let logger = Logger(subsystem: "macadamia Wallet", category: "Interface & Database")

@main
struct macadamiaApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Wallet.self,
            Proof.self,
            Mint.self,
            Event.self,
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
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
