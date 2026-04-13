import SwiftData
import SwiftUI
import CashuSwift

struct URLState: Equatable {
    let url: String
    let timestamp = Date() // prevents .onChange from not firing if you open the same URL twice
}

struct ContentView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Query private var wallets: [Wallet]
    
    private var activeWallet: Wallet? {
        get {
            if wallets.filter({ $0.active == true }).count > 1 {
                logger.critical("""
                                The database seems to contain more than one wallet marked ACTIVE. \
                                this will give undefined behaviour.
                                """)
            }
            if !wallets.isEmpty && wallets.filter({ $0.active == true }).count < 1 {
                logger.critical("""
                                The database contains at least one wallet, but none are marked active. \
                                this will result in wallet malfunctions.
                                """)
            }
            return wallets.first(where: \.active)
        }
        set {}
    }

    @EnvironmentObject private var appState: AppState
    
    @State private var releaseNotesPopoverShowing = false
    
    @State private var selectedTab: Tab = .wallet
    
    @State private var urlState: URLState?
    @State private var pendingNavigation: WalletView.Destination?
    
    @State private var showAlert = false
    @State private var currentAlert: AlertDetail?

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
                WalletView(urlState: $urlState, pendingNavigation: $pendingNavigation)
                    .tabItem {
                        if #available(iOS 18, *) {
                            Label("Wallet", systemImage: "wallet.bifold")
                        } else {
                            Label("Wallet", systemImage: "bitcoinsign.circle")
                        }
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
            if wallets.isEmpty {
                OnboardingCanvas(onComplete: { wallet in
                    modelContext.insert(wallet)
                    for mint in wallet.mints {
                        modelContext.insert(mint)
                    }
                    for proof in wallet.proofs {
                        modelContext.insert(proof)
                    }
                    for event in wallet.events {
                        modelContext.insert(event)
                    }
                    do {
                        try modelContext.save()
                    } catch {
                        logger.critical("Could not save wallet from onboarding: \(error)")
                    }
                    AppState.showOnboarding = false
                })
                .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                .zIndex(1)
            }
        }
//        .ignoresSafeArea()
        .onAppear(perform: {
            if !wallets.isEmpty {
                releaseNotesPopoverShowing = AppState.showReleaseNotes()
            }
            selectedTab = .wallet
        })
        .onAppear {
            Task { @MainActor in
                if let activeWallet {
                    for mint in activeWallet.mints {
                        do {
                            let newKeysets = try await CashuSwift.updatedKeysetsForMint(CashuSwift.Mint(mint))
                            mint.keysets = newKeysets
                        } catch {
                            logger.warning("""
                                           Could not update keyset information for mint at \
                                           \(mint.url.absoluteString), due to error: \(error)
                                           """)
                        }
                    }
                    try modelContext.save()
                }
            }
        }
        .popover(isPresented: $releaseNotesPopoverShowing, content: {
            ZStack(alignment: .topTrailing) {
                ReleaseNoteView()
                Button {
                    releaseNotesPopoverShowing = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .scaleEffect(1.8)
                        .opacity(0.3)
                }
                .padding(EdgeInsets(top: 24, leading: 0, bottom: 0, trailing: 20))
            }
        })
        .preferredColorScheme(.dark)
        .onOpenURL { url in
            handleUrl(url)
        }
        .onChange(of: appState.pendingDeepLink) { _, newValue in
            guard let deepLink = newValue else { return }
            handleDeepLink(deepLink)
            appState.pendingDeepLink = nil
        }
        .alertView(isPresented: $showAlert, currentAlert: currentAlert)
    }


    func handleUrl(_ url: URL) {
        logger.info("""
                    URL has been passed to the application: \ 
                    \(url.absoluteString)
                    """)
         if url.scheme == "cashu" {
             let noURLPrefix = url.absoluteStringWithoutPrefix("cashu")
             selectedTab = .wallet
             
             urlState = URLState(url: noURLPrefix)
         } else if url.scheme == "bitcoin" {
             selectedTab = .wallet
             handleBitcoinURI(url.absoluteString)
         } else {
             displayAlert(alert: AlertDetail(title: String(localized: "Unsupported URL Scheme"), description: String(localized: "The system passed an unexpected URL \(url.absoluteString)")))
         }
    }
    
    private func handleBitcoinURI(_ uriString: String) {
        let supportedTypes: [InputView.InputType] = [.bolt11Invoice, .creq]
        let result = BIP321.resolve(uriString, supportedTypes: supportedTypes)
        switch result {
        case .valid(let inputResult):
            switch inputResult.type {
            case .bolt11Invoice:
                pendingNavigation = .melt(invoice: inputResult.payload)
            case .creq:
                do {
                    let req = try parsePaymentRequest(inputResult.payload)
                    pendingNavigation = .reqPay(req: req)
                } catch {
                    displayAlert(alert: AlertDetail(with: error))
                }
            default:
                displayAlert(alert: AlertDetail(title: String(localized: "Unsupported"),
                                                description: String(localized: "This payment method is not supported.")))
            }
        case .invalid(let message):
            displayAlert(alert: AlertDetail(title: String(localized: "Unsupported"),
                                            description: message))
        }
    }
    
    func handleDeepLink(_ deepLink: DeepLink) {
        logger.info("Handling deep link: \(String(describing: deepLink))")
        selectedTab = .wallet
        
        switch deepLink {
        case .contactless:
            pendingNavigation = .contactless
        }
    }

    private func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}

#Preview {
    ContentView()
}
