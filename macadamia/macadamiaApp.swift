import SwiftData
import SwiftUI
import OSLog

let logger = Logger(subsystem: "macadamia Wallet", category: "Interface & Database")

@main
struct macadamiaApp: App {
    
    @StateObject private var appState = AppState.shared
    @StateObject private var nostrService = NostrService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(nostrService)
        }
        .modelContainer(DatabaseManager.shared.container)
    }
}
