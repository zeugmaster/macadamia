import CashuSwift
import SwiftData
import SwiftUI
import OSLog

fileprivate let walletLogger = Logger(subsystem: "macadamia", category: "WalletView")

@MainActor
struct WalletView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var nostrService: NostrService
    @AppStorage("nostrAutoConnectEnabled") private var autoConnectEnabled: Bool = true
    
    @Query(filter: #Predicate<Wallet> { wallet in
        wallet.active == true
    }) private var wallets: [Wallet]

    @Query private var nostrKeys: [NostrKeypair]

    @State var showAlert: Bool = false
    @State var currentAlert: AlertDetail?
    @State private var processedMessageIds = Set<String>()

    @Binding var urlState: URLState?
    @Binding var pendingNavigation: Destination?
    
    private let buttonCornerRadius = 14.0
    
    enum Destination: Identifiable, Hashable {
        case mint
        case send
        case receive(urlString: String?)
        case melt(invoice: String?)
        case reqPay(req: CashuSwift.PaymentRequest)
        case reqView
        case nfcRequest
        case nfcPay
        case contactless
        case lnurl(userInput: String)
        case payeeInput

        var id: String {
            switch self {
            case .mint:
                return "mint"
            case .send:
                return "send"
            case .receive(let urlString):
                return "receive_\(urlString ?? "nil")"
            case .melt:
                return "melt"
            case .reqPay(_):
                return "reqPay"
            case .reqView:
                return "reqView"
            case .nfcRequest:
                return "nfcRequest"
            case .nfcPay:
                return "nfcPay"
            case .contactless:
                return "contactless"
            case .lnurl(_):
                return "lnurl"
            case .payeeInput:
                return "payeeInput"
            }
        }
    }
    
    @State private var navigationDestination: Destination?
    @State private var navigationPath = NavigationPath()

    static let buttonPadding: CGFloat = 1
    
    init(urlState: Binding<URLState?>, pendingNavigation: Binding<Destination?>) {
        self._urlState = urlState
        self._pendingNavigation = pendingNavigation
    }
    
    var activeWallet:Wallet? {
        wallets.first
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack {
                Spacer(minLength: 40)
                ZStack(alignment: .top) {
                    // Event list comes first to be visually behind the balance card
                    EventList(style: .minimal)
                        .padding(.horizontal, 40)
                        .safeAreaPadding(EdgeInsets(top: 180, leading: 0, bottom: 0, trailing: 0))
                    
                    BalanceCarousel()
                        .onAppear(perform: {
                            // quick sanity check for uniqueness of C across list of proofs
                            guard let activeWallet else {
//                                logger.warning("""
//                                               wallet view appeared with no activeWallet. \
//                                               this will give undefined behaviour.
//                                               """)
                                return
                            }
                        let uniqueCs = Set(activeWallet.proofs.map( { $0.C }))
                        if uniqueCs.count != activeWallet.proofs.count {
                            logger.critical("Wallet seems to contain duplicate proofs.")
                        }
                    })
                }
                HStack(alignment: .center) {
                    // MARK: BUTTON "RECEIVE" -
                    Templates.Menu(
                        configuration: {
                            $0.popoverAnchor = .bottom
                            $0.originAnchor = .top
                            $0.backgroundColor = Color.black.opacity(0.5)
                        }
                    ) {
                        Templates.MenuItem {
                            navigationDestination = .reqView
                        } label: { fade in
                            menuButtonLabel(title: String(localized: "Request"),
                                            subtitle: String(localized: "Create Payment Request"),
                                            imageSystemName: "wallet.pass",
                                            fade: fade)
                        }
                        .background(Color.black)
                        Templates.MenuItem {
                            navigationDestination = .nfcRequest
                        } label: { fade in
                            menuButtonLabel(title: String(localized: "Contactless"),
                                            subtitle: String(localized: "Request ecash via NFC"),
                                            imageSystemName: "wave.3.right",
                                            fade: fade)
                        }
                        .background(Color.black)
                        Templates.MenuItem {
                            navigationDestination = .receive(urlString: nil)
                        } label: { fade in
                            menuButtonLabel(title: String(localized: "Ecash"),
                                            subtitle: String(localized: "Scan or paste a token"),
                                            imageSystemName: "qrcode",
                                            fade: fade)
                        }
                        .background(Color.black)
                        Templates.MenuItem {
                            navigationDestination = .mint
                        } label: { fade in
                            menuButtonLabel(title: String(localized: "Lightning"),
                                            subtitle: String(localized: "Create invoice to add funds"),
                                            imageSystemName: "bolt.fill",
                                            fade: fade)
                        }
                        .background(Color.black)
                    } label: { fade in
                        menuLabel(imageName: "arrow.down", text: String(localized: "Receive"), fade: fade)
                    }
                    
                    // MARK: - SCANNER
                    InputViewModalButton(inputTypes: [.bolt11Invoice, .token, .creq, .lightningAddress, .lnurlPay, .merchantCode]) {
                        Image(systemName: "qrcode")
                            .font(.largeTitle)
                            .padding(16)
                            .background(Color.secondary.opacity(0.3))
                            .cornerRadius(buttonCornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: buttonCornerRadius)
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color.gray.opacity(0.6), Color.gray.opacity(0.2)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                    } onResult: { result in
                        switch result.type {
                            case .bolt11Invoice:
                            navigationDestination = .melt(invoice: result.payload)
                        case .token:
                            navigationDestination = .receive(urlString: result.payload)
                        case .creq:
                            do {
                                let req = try parsePaymentRequest(result.payload)
                                navigationDestination = .reqPay(req: req)
                            } catch {
                                displayAlert(alert: AlertDetail(with: error))
                            }
                        case .lightningAddress, .lnurlPay, .merchantCode:
                            // merchantCode payload is already converted to a lightning address
                            navigationDestination = .lnurl(userInput: result.payload)
                        default:
                            // TODO: ADD LOGGING
                            break
                        }
                    }

                    // MARK: BUTTON "SEND" -
                    Templates.Menu(
                        configuration: {
                            $0.popoverAnchor = .bottom
                            $0.originAnchor = .top
                            $0.backgroundColor = Color.black.opacity(0.5)
                        }
                    ) {
                        Templates.MenuItem {
                            navigationDestination = .contactless
                        } label: { fade in
                            menuButtonLabel(title: String(localized: "Contactless"),
                                            subtitle: String(localized: "Pay a terminal using NFC"),
                                            imageSystemName: "wave.3.right",
                                            fade: fade)
                        }
                        .background(Color.black)
                        Templates.MenuItem {
                            navigationDestination = .nfcPay
                        } label: { fade in
                            menuButtonLabel(title: String(localized: "NFC Pay (exp.)"),
                                            subtitle: String(localized: "Pay an NFC ecash request"),
                                            imageSystemName: "wave.3.right.circle",
                                            fade: fade)
                        }
                        .background(Color.black)
                        Templates.MenuItem {
                            navigationDestination = .send
                        } label: { fade in
                            menuButtonLabel(title: String(localized: "Ecash"),
                                            subtitle: String(localized: "Create Token to Share"),
                                            imageSystemName: "banknote",
                                            fade: fade)
                        }
                        .background(Color.black)
                        Templates.MenuItem {
                            navigationDestination = .payeeInput
                        } label: { fade in
                            menuButtonLabel(title: String(localized: "Lightning"),
                                            subtitle: String(localized: "Pay invoice"),
                                            imageSystemName: "bolt.fill",
                                            fade: fade)
                        }
                        .background(Color.black)
                    } label: { fade in
                        menuLabel(imageName: "arrow.up", text: String(localized: "Send"), fade: fade)
                    }
                }
                .padding(EdgeInsets(top: 20, leading: 16, bottom: 40, trailing: 16))
            }
            .navigationDestination(item: $navigationDestination) { destination in
                switch destination {
                case .mint:
                    MintView()
                case .send:
                    SendView()
                case .receive(let urlString):
                    RedeemContainerView(tokenString: urlString)
                case .melt(let invoice):
                    MeltView(invoice: invoice)
                case .reqPay(req: let req):
                    RequestPay(paymentRequest: req)
                case .reqView:
                    RequestView()
                case .nfcRequest:
                    NFCRequestView()
                case .nfcPay:
                    NFCIsoDepPayerView()
                case .contactless:
                    Contactless()
                case .lnurl(userInput: let userInput):
                    LNURLPayView(userInput: userInput)
                case .payeeInput:
                    PayeeInputView()
                }
            }
            .onChange(of: urlState) { oldValue, newValue in
                print("url state var did change to \(newValue?.url ?? "nil")")
                if let newValue {
                    navigationDestination = .receive(urlString: newValue.url)
                    urlState = nil
                }
            }
            .onChange(of: pendingNavigation) { _, newValue in
                if let destination = newValue {
                    navigationDestination = destination
                    pendingNavigation = nil
                }
            }
            .onChange(of: nostrService.receivedEcashMessages) { _, newMessages in
                processNewEcashMessages(newMessages)
            }
            .onAppear {
                connectNostrIfConfigured()
            }
            .onChange(of: nostrKeys) { _, _ in
                // Fires when the legacy-key migrator or a new payment request adds a key
                // (or a key is deleted) while this view is already on screen
                connectNostrIfConfigured()
            }
            .alertView(isPresented: $showAlert, currentAlert: currentAlert)
        }
        .environment(\.dismissToRoot, DismissToRootAction({ @MainActor in
            navigationDestination = nil
            navigationPath = NavigationPath()
        }))
    }
    
    // MARK: - Nostr Ecash Receiving
    
    private var activeReceiveKeysExist: Bool {
        guard let wallet = wallets.first else { return false }
        return nostrKeys.contains { $0.wallet?.walletID == wallet.walletID && $0.isActive }
    }

    private func connectNostrIfConfigured() {
        guard activeReceiveKeysExist else {
            walletLogger.debug("No active nostr receive keys, skipping connection")
            return
        }

        if nostrService.hasRelayPool {
            // Already connected: make sure the subscription covers the current key set
            nostrService.refreshSubscriptions()
        } else {
            guard autoConnectEnabled else {
                walletLogger.debug("Auto-connect to relays disabled, skipping connection")
                return
            }
            walletLogger.info("Connecting to Nostr relays for ecash messages")
            nostrService.connect()
        }
    }

    private func processNewEcashMessages(_ messages: [ReceivedEcashMessage]) {
        // processedMessageIds only prevents duplicate concurrent tasks within this
        // session; the persisted NostrMessage ledger is the source of truth
        for message in messages where !processedMessageIds.contains(message.id) {
            processedMessageIds.insert(message.id)
            Task {
                await receiveEcashFromMessage(message)
            }
        }
    }

    private func ledgerEntry(for messageID: String) -> NostrMessage? {
        let descriptor = FetchDescriptor<NostrMessage>(predicate: #Predicate<NostrMessage> { $0.messageID == messageID })
        return try? modelContext.fetch(descriptor).first
    }

    /// Updates or inserts the persisted ledger row for a processed nostr message.
    private func recordOutcome(_ outcome: NostrMessage.Outcome,
                               for message: ReceivedEcashMessage,
                               eventID: UUID? = nil) {
        if let existing = ledgerEntry(for: message.id) {
            existing.outcome = outcome
            if let eventID { existing.eventID = eventID }
        } else {
            let receiverPubkeyHex = message.receiverPubkeyHex
            let keyDescriptor = FetchDescriptor<NostrKeypair>(predicate: #Predicate<NostrKeypair> { $0.publicKeyHex == receiverPubkeyHex })
            let keypair = try? modelContext.fetch(keyDescriptor).first
            modelContext.insert(NostrMessage(messageID: message.id,
                                             outcome: outcome,
                                             eventID: eventID,
                                             keypair: keypair))
        }
        do {
            try modelContext.save()
        } catch {
            walletLogger.error("Failed to save nostr message ledger entry: \(error)")
        }
    }
    
    private func receiveEcashFromMessage(_ message: ReceivedEcashMessage) async {
        guard let activeWallet else {
            walletLogger.error("No active wallet to receive ecash")
            return
        }

        // The persisted ledger is the cross-launch source of truth: skip anything
        // already redeemed or known to be spent without touching the network
        if let existing = ledgerEntry(for: message.id), existing.outcome.isTerminal {
            walletLogger.debug("Skipping message \(message.id), already processed (\(existing.outcome.rawValue))")
            return
        }

        let token = message.payload.toToken()

        // Get the mint URL from the token
        guard let mintURLString = token.proofsByMint.keys.first else {
            walletLogger.error("Could not determine mint URL from token")
            return
        }

        // Find the mint in our wallet
        guard let mint = activeWallet.mints.first(where: { $0.url.absoluteString == mintURLString && !$0.hidden }) else {
            walletLogger.warning("Received ecash from unknown mint: \(mintURLString)")
            // Retryable: if the user adds the mint later, a future replay redeems it.
            // Only alert the first time we see this message, not on every replay.
            let firstSighting = ledgerEntry(for: message.id) == nil
            recordOutcome(.unknownMint, for: message)
            if firstSighting {
                displayAlert(alert: AlertDetail(title: String(localized: "⚡ Incoming Ecash"),
                                                description: String(localized: "Received ecash from an unknown mint (\(mintURLString)). Add this mint to redeem.")))
            }
            return
        }

        // Check if proofs are still valid/unspent
        guard let proofs = token.proofsByMint[mintURLString] else {
            walletLogger.error("No proofs found in token")
            return
        }

        Task { @MainActor in
            do {
                let proofStates = try await CashuSwift.check(proofs, mint: CashuSwift.Mint(mint))

                // All proofs must be unspent to proceed
                guard proofStates.allSatisfy({ $0 == .unspent }) else {
                    walletLogger.warning("Received ecash contains spent proofs, skipping")
                    recordOutcome(.spent, for: message)
                    return
                }

                walletLogger.info("Proofs are valid, receiving \(token.sum()) sats")

                // Get private key for P2PK locked tokens
                let privateKeyString = activeWallet.privateKeyData.map { String(bytes: $0) }

                let redeemResult = try await CashuSwift.receive(token: token,
                                                                of: CashuSwift.Mint(mint),
                                                                seed: activeWallet.seed,
                                                                privateKey: privateKeyString)

                walletLogger.debug("result of redeeming token DLEQ check; in: \(String(describing: redeemResult.inputDLEQ)) out: \(String(describing: redeemResult.outputDLEQ))")

                let internalProofs = try mint.addProofs(redeemResult.proofs, to: modelContext)

                let receiveEvent = Event.receiveEvent(unit: .sat,
                                                      shortDescription: "Receive",
                                                      wallet: activeWallet,
                                                      amount: redeemResult.proofs.sum,
                                                      longDescription: "",
                                                      proofs: internalProofs,
                                                      memo: token.memo,
                                                      mint: mint,
                                                      redeemed: true)
                modelContext.insert(receiveEvent)

                try modelContext.save()

                recordOutcome(.redeemed, for: message, eventID: receiveEvent.eventID)

            } catch {
                // Retryable: transient network or mint errors may resolve on a later replay
                let firstSighting = ledgerEntry(for: message.id) == nil
                recordOutcome(.failed, for: message)
                processedMessageIds.remove(message.id)
                if firstSighting {
                    displayAlert(alert: AlertDetail(title: String(localized: "Something went wrong"), description: String(localized: "An error occured while trying to redeem a token received via Nostr DMs. \(String(describing: error))")))
                }
                walletLogger.error("error while trying to auto-redeem token from nostr dm: \(error)")
            }
        }
    }
    
    private func menuLabel(imageName: String,
                           text: String,
                           fade: Bool) -> some View {
        Text("\(Image(systemName: imageName))  \(text)")
            .opacity(fade ? 0.5 : 1)
            .font(.title3)
            .fontWeight(.semibold)
            .padding(EdgeInsets(top: 20, leading: 0, bottom: 20, trailing: 0))
            .frame(maxWidth: .infinity)
            .background(Color.secondary.opacity(0.3))
            .cornerRadius(buttonCornerRadius)
            .lineLimit(1)
            .overlay(
                RoundedRectangle(cornerRadius: buttonCornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [Color.gray.opacity(0.6), Color.gray.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
    }
    
    private func menuButtonLabel(title: String,
                                 subtitle: String,
                                 imageSystemName: String,
                                 fade: Bool) -> some View {
        Color.clear.overlay(
            HStack {
                VStack(alignment: .leading) {
                    Text(title)
                        .foregroundStyle(.white)
                        .font(.title3)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
                Spacer()
                Image(systemName: imageSystemName)
            }
        )
        .opacity(fade ? 0.5 : 1)
        .padding(EdgeInsets(top: 24, leading: 12, bottom: 24, trailing: 12))
    }

    private func displayAlert(alert: AlertDetail) {
        currentAlert = alert
        showAlert = true
    }
}

#if DEBUG
#Preview {
    WalletPreviewWrapper()
        .previewEnvironment()
}

private struct WalletPreviewWrapper: View {
    @State private var urlState: URLState?
    @State private var pendingNavigation: WalletView.Destination?

    var body: some View {
        WalletView(urlState: $urlState, pendingNavigation: $pendingNavigation)
    }
}
#endif
