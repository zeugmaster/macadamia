//
//  NostrService.swift
//  macadamia
//
//  Simplified for wallet-specific nostr key management
//

import SwiftUI
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
    let id: String // event id
    let payload: CashuSwift.PaymentRequestPayload
    let sender: String // sender's pubkey (hex)
    let receivedAt: Date
    let isRedeemed: Bool
    
    init(id: String, payload: CashuSwift.PaymentRequestPayload, sender: String, receivedAt: Date = Date(), isRedeemed: Bool = false) {
        self.id = id
        self.payload = payload
        self.sender = sender
        self.receivedAt = receivedAt
        self.isRedeemed = isRedeemed
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
                   self?.isListeningForMessages == false,
                   NostrKeychain.hasNsec() {
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
    
    /// Resubscribes to all connected relays (for when new relays connect after initial subscription)
    @MainActor
    private func resubscribeToAllRelays() async {
        guard let keypair = try? getKeypair(),
              let relayPool = relayPool,
              let existingSubscriptionId = messageSubscriptionId else {
            return
        }
        
        // Close existing subscription
        relayPool.closeSubscription(with: existingSubscriptionId)
        
        // Create new subscription (will subscribe to all currently connected relays)
        guard let filter = Filter(kinds: [EventKind.giftWrap.rawValue], tags: ["p": [keypair.publicKey.hex]]) else {
            nostrLogger.error("Failed to create filter for resubscription")
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
        connectionStates.removeAll()
        nostrLogger.info("Disconnected from relays")
    }
    
    /// Reconnects with the current relay list (useful after modifying relays while disconnected)
    @MainActor
    func reconnect() {
        disconnect()
        connect()
    }
    
    /// Sends a NIP-17 direct message
    /// - Parameters:
    ///   - nsec: The sender's private key in nsec (bech32) or hex format
    ///   - receiverNpub: The receiver's public key in npub or nprofile (bech32) format
    ///   - message: The message content to send
    /// - Throws: NostrServiceError if keypair parsing, recipient parsing, or event creation fails
    @MainActor
    func sendNIP17(from nsec: String, to receiverNpub: String, message: String) async throws {
        // Parse sender's keypair
        guard let keypair = parseKeypair(from: nsec) else {
            nostrLogger.error("Failed to parse sender keypair")
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
        
        guard let keypair = try? getKeypair() else {
            nostrLogger.error("Cannot start listening: no keypair available")
            return
        }
        
        guard let relayPool = relayPool else {
            nostrLogger.error("Cannot start listening: relay pool not initialized")
            return
        }
        
        nostrLogger.info("Starting to listen for ecash messages for pubkey: \(keypair.publicKey.hex)")
        isListeningForMessages = true
        
        // Set up event listener FIRST before subscribing
        relayPool.events
            .sink { [weak self] relayEvent in
                guard let self = self else { return }
                nostrLogger.info("📩 Received relay event, kind: \(relayEvent.event.kind.rawValue)")
                Task { @MainActor in
                    await self.handleIncomingEvent(relayEvent.event)
                }
            }
            .store(in: &cancellables)
        
        nostrLogger.info("Event listener set up")
        
        // NIP-17: Gift wrap events are kind 1059, addressed to recipient's pubkey via p tag
        guard let filter = Filter(kinds: [EventKind.giftWrap.rawValue], tags: ["p": [keypair.publicKey.hex]]) else {
            nostrLogger.error("Failed to create filter for gift wrap events")
            isListeningForMessages = false
            return
        }
        
        nostrLogger.info("Created filter for kind 1059 with p tag for pubkey: \(keypair.publicKey.hex)")
        
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
        nostrLogger.info("Received event kind: \(event.kind.rawValue), id: \(event.id), type: \(type(of: event))")
        
        guard let keypair = try? getKeypair() else {
            nostrLogger.error("Cannot handle event: no keypair available")
            return
        }
        
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
        
        nostrLogger.info("Successfully cast to GiftWrapEvent")
        
        // Try to unseal the rumor inside the gift wrap
        guard let unwrappedEvent = try? giftWrapEvent.unsealedRumor(using: keypair.privateKey) else {
            nostrLogger.warning("Failed to unwrap gift wrap event \(event.id) - might not be for us or decryption failed")
            return
        }
        
        nostrLogger.info("Successfully unwrapped gift wrap event \(event.id), content length: \(unwrappedEvent.content.count)")
        
        // Check if the content is a valid PaymentRequestPayload
        if let payload = decodePaymentRequestPayload(unwrappedEvent.content) {
            let message = ReceivedEcashMessage(
                id: unwrappedEvent.id,
                payload: payload,
                sender: unwrappedEvent.pubkey
            )
            
            // Check if we already have this message
            if !receivedEcashMessages.contains(where: { $0.id == message.id }) {
                receivedEcashMessages.append(message)
                nostrLogger.info("Added new ecash message from \(message.sender)")
            } else {
                nostrLogger.debug("Duplicate ecash message \(message.id), skipping")
            }
        } else {
            nostrLogger.warning("Message does not contain valid PaymentRequestPayload. Content: \(unwrappedEvent.content.prefix(200))")
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
    
    // MARK: - Helper Methods
    
    /// Gets the user's keypair from the keychain
    private func getKeypair() throws -> Keypair {
        let nsec = try NostrKeychain.getNsec()
        guard let keypair = parseKeypair(from: nsec) else {
            throw NostrServiceError.noKeypairAvailable
        }
        return keypair
    }
    
    private func parseKeypair(from keyString: String) -> Keypair? {
        let normalized = keyString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if normalized.lowercased().hasPrefix("nsec") {
            return Keypair(nsec: normalized)
        } else {
            return Keypair(hex: normalized)
        }
    }
}
