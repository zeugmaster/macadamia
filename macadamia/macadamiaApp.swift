import SwiftData
import SwiftUI
import OSLog

let logger = Logger(subsystem: "macadamia Wallet", category: "Interface & Database")

@main
struct macadamiaApp: App {
    
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .modelContainer(DatabaseManager.shared.container)
    }
}
