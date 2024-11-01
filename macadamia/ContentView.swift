import BIP39
import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var wallets: [Wallet]
    
    private var activeWallet: Wallet? {
        get {
            wallets.first
        }
        set {}
    }

    @State private var releaseNotesPopoverShowing = false
    @State private var selectedTab: Tab = .wallet
    
    @State private var urlState: String?

    enum Tab {
        case wallet
        case mints
        case settings
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            // FIXME: FOR SOME REASON TRACKING TAB SELECTION LEADS TO FUNNY BEHAVIOUR
            TabView(selection: $selectedTab) {
                // First tab content
                WalletView(urlState: $urlState)
                    .tabItem {
                        Label("Wallet", systemImage: "bitcoinsign.circle")
                    }
                    .tag(Tab.wallet)

                MintManagerView()
                    .tabItem {
                        Image(systemName: "building.columns")
                        Text("Mints")
                    }
                    .tag(Tab.mints)

                // Third tab content
                SettingsView()
                    .tabItem {
                        Image(systemName: "gear")
                        Text("Settings")
                    }
                    .tag(Tab.settings)
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
            
//            let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
//            print("App Support Directory: \(urls[0])")
            
            selectedTab = .wallet
        })
        .popover(isPresented: $releaseNotesPopoverShowing, content: {
            ReleaseNoteView()
            Text("Swipe down to dismiss")
                .foregroundStyle(.secondary)
                .font(.footnote)
        })
        .preferredColorScheme(.dark)
        .onOpenURL { url in
            handleUrl(url)
        }
    }

    private func initializeWallet() {
        let seed = String(bytes: Mnemonic().seed)
        let wallet = Wallet(seed: seed)
        modelContext.insert(wallet)
        logger.info("No wallet was found, initializing a new one with ID \(wallet.walletID)...")
        do {
            try modelContext.save()
            logger.debug("Successfully saved new wallet.")
        } catch {
            logger.critical("Could not save new wallet with ID \(wallet.walletID). error: \(error)")
        }
    }

    func checkReleaseNotes() {
        let releaseNotesSeenHash = UserDefaults.standard.string(forKey: "LastReleaseNotesAcknoledgedHash")
        if releaseNotesSeenHash ?? "not set" != ReleaseNote.hashString() {
            releaseNotesPopoverShowing = true
            UserDefaults.standard.setValue(ReleaseNote.hashString(),
                                           forKey: "LastReleaseNotesAcknoledgedHash")
            logger.info("Release notes have changed and will be shown.")
        }
    }

    func handleUrl(_ url: URL) {
        logger.info("URL has been passed to the application: \(url.absoluteString.prefix(30) + (url.absoluteString.count > 30 ? "..." : ""))")
         if url.scheme == "cashu" {
             let noURLPrefix = url.absoluteStringWithoutPrefix("cashu")
             selectedTab = .wallet
             urlState = noURLPrefix
         }
    }
}

#Preview {
    ContentView()
}
