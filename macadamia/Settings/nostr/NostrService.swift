//
//  NostrService.swift
//  macadamia
//
//  Simplified for wallet-specific nostr key management
//

import SwiftUI
import SwiftData
import NostrSDK
import Combine
import OSLog
import CashuSwift


// MARK: - NostrService

fileprivate let nostrLogger = Logger(subsystem: "macadamia", category: "NostrService")

enum NostrServiceError: Error {
    case noKeypairAvailable
    case invalidRecipientPubkey
    case encryptionFailed
    case eventCreationFailed
    case decryptionFailed
}

// MARK: - Received Message Model

struct ReceivedEcashMessage: Identifiable, Equatable {
    let id: String // event id of the unsealed rumor
    let payload: CashuSwift.PaymentRequestPayload
    let sender: String // sender's pubkey (hex)
    let receiverPubkeyHex: String // pubkey of the receive key this message was addressed to
    let receivedAt: Date

    init(id: String, payload: CashuSwift.PaymentRequestPayload, sender: String, receiverPubkeyHex: String, receivedAt: Date = Date()) {
        self.id = id
        self.payload = payload
        self.sender = sender
        self.receiverPubkeyHex = receiverPubkeyHex
        self.receivedAt = receivedAt
    }

    static func == (lhs: ReceivedEcashMessage, rhs: ReceivedEcashMessage) -> Bool {
        lhs.id == rhs.id
    }
}


class NostrService: ObservableObject, EventCreating, MetadataCoding {
    
    enum ConnectionState {
        case noneConnected, partiallyConnected(Int), allConnected(Int)
    }
    
    // MARK: - Reactive Properties (In-Memory)
    
    @Published var connectionStates = [URL: Relay.State]()
    @Published var receivedEcashMessages: [ReceivedEcashMessage] = []
    @Published var isListeningForMessages = false
    @Published private(set) var relayURLs: [URL] = []
    
    var aggregateConnectionState: ConnectionState {
        let connected = connectionStates.filter({ $0.value == .connected }).count
        let all = connectionStates.count
        if connected == 0 {
            return .noneConnected
        } else if connected == all {
            return .allConnected(all)
        } else {
            return .partiallyConnected(connected)
        }
    }
    
    private var relayPool: RelayPool?
    private var messageSubscriptionId: String?
    private var cancellables = Set<AnyCancellable>()
    private var relayCancellables = [URL: AnyCancellable]()
    private var eventsCancellable: AnyCancellable?

    /// Whether a relay pool currently exists (regardless of per-relay connection state).
    var hasRelayPool: Bool { relayPool != nil }
    
    @AppStorage("savedURLs") private var savedURLsData: Data = {
        return try! JSONEncoder().encode(defaultRelayURLs)
    }()
    
    private var savedURLs: [URL] {
        get {
            (try? JSONDecoder().decode([URL].self, from: savedURLsData)) ?? defaultRelayURLs
        }
        set {
            savedURLsData = (try? JSONEncoder().encode(newValue)) ?? Data()
            relayURLs = newValue
        }
    }
    
    init() {
        // Initialize relayURLs from persisted data
        relayURLs = savedURLs
    }
    
    func connect() {
        nostrLogger.info("🔌 connect() called for nostr service")
        
        guard relayPool == nil else {
            nostrLogger.info("RelayPool already exists, skipping creation")
            return
        }
        
        let urlsToConnect = savedURLs
        relayURLs = urlsToConnect
        
        relayPool = try? RelayPool(relayURLs: Set(urlsToConnect))
        nostrLogger.info("Created RelayPool with \(urlsToConnect.count) relay URLs")
        
        // Subscribe to relay states
        subscribeToRelayStates()
        
        nostrLogger.info("Calling relayPool.connect()")
        relayPool?.connect()
    }
    
    /// Subscribes to state changes for all relays in the pool
    private func subscribeToRelayStates() {
        relayPool?.relays.forEach { relay in
            subscribeToRelayState(relay)
        }
    }
    
    /// Subscribes to state changes for a single relay
    private func subscribeToRelayState(_ relay: Relay) {
        nostrLogger.info("Setting up state observer for relay: \(relay.url)")
        
        let cancellable = relay.$state
            .sink { [weak self] newState in
                nostrLogger.info("Relay \(relay.url) state changed to: \(String(describing: newState))")
                self?.connectionStates[relay.url] = newState
                
                // Check if we should start listening (when most relays are connected)
                if newState == .connected,
                   self?.isListeningForMessages == false {
                    self?.checkAndStartListening()
                }
            }
        
        relayCancellables[relay.url] = cancellable
        cancellable.store(in: &cancellables)
    }
    
    // MARK: - Dynamic Relay Management
    
    /// Adds a relay URL to the pool and persists the change
    @MainActor
    func addRelay(_ url: URL) {
        guard !savedURLs.contains(url) else {
            nostrLogger.info("Relay \(url) already exists, skipping")
            return
        }
        
        // Update persisted list
        var urls = savedURLs
        urls.append(url)
        savedURLs = urls
        
        nostrLogger.info("Added relay \(url) to saved list")
        
        // Reconnect to apply changes if pool exists
        if relayPool != nil {
            reconnect()
        }
    }
    
    /// Removes a relay URL from the pool and persists the change
    @MainActor
    func removeRelay(_ url: URL) {
        // Update persisted list
        var urls = savedURLs
        urls.removeAll { $0 == url }
        savedURLs = urls
        
        // Clean up connection state for removed relay
        connectionStates.removeValue(forKey: url)
        relayCancellables.removeValue(forKey: url)
        
        nostrLogger.info("Removed relay \(url) from saved list")
        
        // Reconnect to apply changes if pool exists
        if relayPool != nil {
            reconnect()
        }
    }
    
    /// Returns the connection state for a specific relay URL
    func connectionState(for url: URL) -> Relay.State? {
        connectionStates[url]
    }
    
    /// Checks if enough relays are connected and starts listening
    private func checkAndStartListening() {
        let connectedCount = connectionStates.filter { $0.value == .connected }.count
        let totalCount = connectionStates.count
        
        nostrLogger.info("Connected relays: \(connectedCount)/\(totalCount)")
        
        // If already listening, resubscribe to catch newly connected relays
        if isListeningForMessages {
            nostrLogger.info("Already listening, resubscribing to include newly connected relays")
            Task { @MainActor in
                await resubscribeToAllRelays()
            }
            return
        }
        
        // Start listening when at least half of the relays are connected
        if connectedCount >= max(1, totalCount / 2) {
            nostrLogger.info("Enough relays connected, starting message listener")
            Task { @MainActor in
                await startListeningForEcashMessages()
            }
        }
    }
    
    /// Resubscribes to all connected relays (for when new relays connect after the initial
    /// subscription, or when the set of receive keys changed)
    @MainActor
    private func resubscribeToAllRelays() async {
        guard let relayPool = relayPool,
              let existingSubscriptionId = messageSubscriptionId else {
            return
        }

        // Close existing subscription
        relayPool.closeSubscription(with: existingSubscriptionId)

        // Create new subscription from the current key set
        guard let filter = currentGiftWrapFilter() else {
            nostrLogger.info("No active receive keys left, stopping message listener")
            messageSubscriptionId = nil
            isListeningForMessages = false
            return
        }

        let newSubscriptionId = relayPool.subscribe(with: filter)
        messageSubscriptionId = newSubscriptionId

        nostrLogger.info("Resubscribed with new subscription id: \(newSubscriptionId)")
    }
    
    @MainActor func disconnect() {
        stopListeningForEcashMessages()
        relayPool?.disconnect()
        relayPool = nil
        cancellables.removeAll()
        relayCancellables.removeAll()
        eventsCancellable = nil
        connectionStates.removeAll()
        nostrLogger.info("Disconnected from relays")
    }
    
    /// Reconnects with the current relay list (useful after modifying relays while disconnected)
    @MainActor
    func reconnect() {
        disconnect()
        connect()
    }

    /// Idempotent entry point for "the set of receive keys changed": starts, updates,
    /// or stops the gift-wrap subscription to match the database.
    @MainActor
    func refreshSubscriptions() {
        let keys = activeReceiveKeys()

        if keys.isEmpty {
            stopListeningForEcashMessages()
            return
        }

        if relayPool == nil {
            // Subscription follows once relays report .connected
            connect()
            return
        }

        if isListeningForMessages {
            Task { @MainActor in
                await resubscribeToAllRelays()
            }
        } else {
            checkAndStartListening()
        }
    }
    
    /// Sends a NIP-17 direct message signed by a throwaway keypair
    /// - Parameters:
    ///   - receiverNpub: The receiver's public key in npub, nprofile (bech32) or hex format
    ///   - message: The message content to send
    /// - Throws: NostrServiceError if keypair generation, recipient parsing, or event creation fails
    @MainActor
    func sendNIP17(to receiverNpub: String, message: String) async throws {
        // A fresh random sender key per message: the recipient only needs the ecash
        // payload, and an ephemeral identity avoids linking payments to each other.
        guard let keypair = Keypair() else {
            nostrLogger.error("Failed to generate throwaway sender keypair")
            throw NostrServiceError.noKeypairAvailable
        }
        
        // Parse receiver's public key (supports npub and nprofile)
        let recipientPublicKey: PublicKey
        let normalized = receiverNpub.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if normalized.lowercased().hasPrefix("npub") {
            guard let pubkey = PublicKey(npub: normalized) else {
                nostrLogger.error("Failed to parse npub")
                throw NostrServiceError.invalidRecipientPubkey
            }
            recipientPublicKey = pubkey
        } else if normalized.lowercased().hasPrefix("nprofile") {
            // Extract pubkey from nprofile
            guard let metadata = try? decodedMetadata(from: normalized),
                  let pubkeyHex = metadata.pubkey,
                  let pubkey = PublicKey(hex: pubkeyHex) else {
                nostrLogger.error("Failed to parse nprofile")
                throw NostrServiceError.invalidRecipientPubkey
            }
            recipientPublicKey = pubkey
        } else if normalized.count == 64 {
            // Try as hex public key
            guard let pubkey = PublicKey(hex: normalized) else {
                nostrLogger.error("Failed to parse hex public key")
                throw NostrServiceError.invalidRecipientPubkey
            }
            recipientPublicKey = pubkey
        } else {
            nostrLogger.error("Invalid recipient format")
            throw NostrServiceError.invalidRecipientPubkey
        }
        
        // Build the direct message event
        let dmBuilder = DirectMessageEvent.Builder()
        dmBuilder.content(message)
        dmBuilder.appendTags(NostrSDK.Tag(name: TagName.pubkey.rawValue, value: recipientPublicKey.hex))
        
        let directMessageEvent = dmBuilder.build(pubkey: keypair.publicKey)
        
        // Gift wrap the direct message
        guard let giftWrapEvent = try? giftWrap(
            withDirectMessageEvent: directMessageEvent,
            toRecipient: recipientPublicKey,
            signedBy: keypair
        ) else {
            nostrLogger.error("Failed to create gift wrap")
            throw NostrServiceError.encryptionFailed
        }
        
        // Publish to relays
        guard let relayPool = relayPool else {
            nostrLogger.error("RelayPool not initialized")
            throw NostrServiceError.eventCreationFailed
        }
        
        relayPool.publishEvent(giftWrapEvent)
        
        nostrLogger.info("Successfully published NIP-17 DM to relays")
    }
    
    // MARK: - Receiving Messages
    
    /// Starts listening for incoming NIP-17 direct messages containing ecash tokens
    @MainActor
    func startListeningForEcashMessages() async {
        guard !isListeningForMessages else {
            nostrLogger.debug("Already listening for ecash messages")
            return
        }

        guard let relayPool = relayPool else {
            nostrLogger.error("Cannot start listening: relay pool not initialized")
            return
        }

        // NIP-17: Gift wrap events are kind 1059, addressed to a receive key via p tag
        guard let filter = currentGiftWrapFilter() else {
            nostrLogger.debug("No active receive keys, not starting message listener")
            return
        }

        isListeningForMessages = true

        // Set up the event listener once per pool lifecycle, FIRST before subscribing
        if eventsCancellable == nil {
            eventsCancellable = relayPool.events
                .sink { [weak self] relayEvent in
                    guard let self = self else { return }
                    nostrLogger.debug("📩 Received relay event, kind: \(relayEvent.event.kind.rawValue)")
                    Task { @MainActor in
                        await self.handleIncomingEvent(relayEvent.event)
                    }
                }
            nostrLogger.info("Event listener set up")
        }

        // Subscribe to the filter
        let subscriptionId = relayPool.subscribe(with: filter)
        messageSubscriptionId = subscriptionId

        nostrLogger.info("Subscribed to gift wrap events with subscription id: \(subscriptionId)")
    }
    
    /// Stops listening for incoming messages
    @MainActor
    func stopListeningForEcashMessages() {
        guard isListeningForMessages else { return }
        
        if let subscriptionId = messageSubscriptionId {
            relayPool?.closeSubscription(with: subscriptionId)
            messageSubscriptionId = nil
            nostrLogger.info("Closed message subscription")
        }
        
        isListeningForMessages = false
    }
    
    /// Handles an incoming event from a relay
    @MainActor
    private func handleIncomingEvent(_ event: NostrEvent) async {
        nostrLogger.debug("Received event kind: \(event.kind.rawValue), id: \(event.id), type: \(type(of: event))")

        // Check if this is a gift wrap event (kind 1059)
        guard event.kind == .giftWrap else {
            nostrLogger.debug("Event \(event.id) is not a gift wrap (kind \(event.kind.rawValue))")
            return
        }

        // Cast to GiftWrapEvent - NostrSDK should return the correct subtype for kind 1059
        guard let giftWrapEvent = event as? GiftWrapEvent else {
            nostrLogger.error("Failed to cast event to GiftWrapEvent (type: \(type(of: event)))")
            return
        }

        let keys = activeReceiveKeys()
        guard !keys.isEmpty else {
            nostrLogger.warning("Cannot handle event: no active receive keys")
            return
        }

        // Route to the addressed key via the gift wrap's "p" tag, falling back to
        // trying every active key when the tag doesn't match any of them
        let referencedPubkeys = Set(giftWrapEvent.referencedPubkeys)
        var candidates = keys.filter { referencedPubkeys.contains($0.publicKeyHex) }
        if candidates.isEmpty { candidates = keys }

        var unsealed: (rumor: NostrEvent, key: ReceiveKey)?
        for key in candidates {
            if let rumor = try? giftWrapEvent.unsealedRumor(using: key.keypair.privateKey) {
                unsealed = (rumor, key)
                break
            }
        }

        guard let (unwrappedEvent, matchedKey) = unsealed else {
            nostrLogger.warning("Failed to unwrap gift wrap event \(event.id) - might not be for us or decryption failed")
            return
        }

        nostrLogger.debug("Successfully unwrapped gift wrap event \(event.id), content length: \(unwrappedEvent.content.count)")

        // Skip messages the persisted ledger already marks as terminally processed
        let rumorID = unwrappedEvent.id
        let context = DatabaseManager.shared.container.mainContext
        let descriptor = FetchDescriptor<NostrMessage>(predicate: #Predicate<NostrMessage> { $0.messageID == rumorID })
        if let ledgerRow = try? context.fetch(descriptor).first,
           ledgerRow.outcome.isTerminal {
            nostrLogger.debug("Message \(rumorID) already processed (\(ledgerRow.outcome.rawValue)), skipping")
            return
        }

        // Check if the content is a valid PaymentRequestPayload
        if let payload = decodePaymentRequestPayload(unwrappedEvent.content) {
            let message = ReceivedEcashMessage(
                id: unwrappedEvent.id,
                payload: payload,
                sender: unwrappedEvent.pubkey,
                receiverPubkeyHex: matchedKey.publicKeyHex
            )

            // Check if we already have this message
            if !receivedEcashMessages.contains(where: { $0.id == message.id }) {
                receivedEcashMessages.append(message)
                nostrLogger.info("Added new ecash message from \(message.sender)")
            } else {
                nostrLogger.debug("Duplicate ecash message \(message.id), skipping")
            }
        } else {
            // Never log message content: DMs can carry multi-kilobyte token text
            nostrLogger.warning("Message \(rumorID) does not contain a valid PaymentRequestPayload (content length: \(unwrappedEvent.content.count))")
        }
    }
    
    /// Attempts to decode content as a PaymentRequestPayload
    /// Returns the decoded payload if successful, nil otherwise
    private func decodePaymentRequestPayload(_ content: String) -> CashuSwift.PaymentRequestPayload? {
        guard let data = content.data(using: .utf8) else {
            nostrLogger.debug("Failed to convert content to data")
            return nil
        }
        
        do {
            let payload = try JSONDecoder().decode(CashuSwift.PaymentRequestPayload.self, from: data)
            nostrLogger.debug("Successfully decoded PaymentRequestPayload")
            return payload
        } catch {
            nostrLogger.debug("Failed to decode PaymentRequestPayload: \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Receive Keys

    /// A receive key rehydrated from the database, ready for filter construction and unsealing.
    struct ReceiveKey {
        let keypair: Keypair
        let publicKeyHex: String
        let dateCreated: Date
        let isLegacy: Bool
    }

    /// Fetches the active wallet's non-archived receive keys from the database.
    @MainActor
    func activeReceiveKeys() -> [ReceiveKey] {
        let context = DatabaseManager.shared.container.mainContext

        let activeWalletID: UUID
        do {
            let wallets = try context.fetch(FetchDescriptor<Wallet>(predicate: #Predicate<Wallet> { $0.active == true }))
            guard let wallet = wallets.first else { return [] }
            activeWalletID = wallet.walletID
        } catch {
            nostrLogger.error("Failed to fetch active wallet: \(error)")
            return []
        }

        let rows = (try? context.fetch(FetchDescriptor<NostrKeypair>())) ?? []

        // isActive is computed (90-day cutoff), so filtering happens in memory
        return rows
            .filter { $0.wallet?.walletID == activeWalletID && $0.isActive }
            .compactMap { row in
                guard let keypair = NostrKeyMaterial.parseKeypair(row.privateKeyHex) else {
                    nostrLogger.warning("Could not parse stored receive key \(row.keypairID)")
                    return nil
                }
                return ReceiveKey(keypair: keypair,
                                  publicKeyHex: row.publicKeyHex,
                                  dateCreated: row.dateCreated,
                                  isLegacy: row.isLegacy)
            }
    }

    /// The kind-1059 filter covering all currently active receive keys, or nil if there are none.
    @MainActor
    private func currentGiftWrapFilter() -> Filter? {
        let keys = activeReceiveKeys()
        return NostrKeyMaterial.giftWrapFilter(activePubkeys: keys.map(\.publicKeyHex),
                                               earliestCreation: keys.map(\.dateCreated).min(),
                                               containsLegacy: keys.contains(where: \.isLegacy))
    }
}
