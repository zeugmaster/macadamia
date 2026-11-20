import SwiftData
import SwiftUI
import OSLog
import MarkdownUI

let logger = Logger(subsystem: "macadamia Wallet", category: "Interface & Database")

@main
struct macadamiaApp: App {
    
    @StateObject private var appState = AppState.shared
    @StateObject private var nostrService = NostrService()

    @Environment(\.scenePhase) private var scenePhase

    init() {
        TorRuntime.shared.install()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(nostrService)
                .markdownImageProvider(WalletMarkdownImages())
                .markdownInlineImageProvider(WalletMarkdownImages())
                .onChange(of: scenePhase, initial: true) { _, phase in
                    if phase == .background { TorRuntime.shared.suspend() }
                    if phase == .active {
                        TorRuntime.shared.resume()
                        if nostrService.hasRelayPool { nostrService.reconnect() }
                    }
                }
        }
        .modelContainer(DatabaseManager.shared.container)
    }
}
