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

struct ReceivedEcashMessage: Identifiable, Codable {
    let id: String // event id
    let content: String // ecash token
    let sender: String // sender's pubkey (hex)
    let receivedAt: Date
    let isRedeemed: Bool
    
    init(id: String, content: String, sender: String, receivedAt: Date = Date(), isRedeemed: Bool = false) {
        self.id = id
        self.content = content
        self.sender = sender
        self.receivedAt = receivedAt
        self.isRedeemed = isRedeemed
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
    
    @AppStorage("savedURLs") private var savedURLsData: Data = {
        return try! JSONEncoder().encode(defaultRelayURLs)
    }()
    
    private var savedURLs: [URL] {
        get {
            (try? JSONDecoder().decode([URL].self, from: savedURLsData)) ?? defaultRelayURLs
        }
        set {
            savedURLsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }
    
    func connect() {
        nostrLogger.debug(".connect() called for nostr service")
        relayPool = try? RelayPool(relayURLs: Set(defaultRelayURLs))
        
        // subscribe to relay states
        relayPool?.relays.forEach { relay in
            relay.$state
                .sink { [weak self] newState in
                    self?.connectionStates[relay.url] = newState
                    
                    // Start listening for messages when at least one relay is connected
                    if newState == .connected,
                       self?.isListeningForMessages == false,
                       NostrKeychain.hasNsec() {
                        Task { @MainActor in
                            await self?.startListeningForEcashMessages()
                        }
                    }
                }
                .store(in: &cancellables)
        }
        
        relayPool?.connect()
    }
    
    @MainActor func disconnect() {
        stopListeningForEcashMessages()
        relayPool?.disconnect()
        cancellables.removeAll()
        connectionStates.removeAll()
        nostrLogger.info("Disconnected from relays")
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
        
        nostrLogger.info("Starting to listen for ecash messages")
        isListeningForMessages = true
        
        // NIP-17: Gift wrap events are kind 1059, addressed to recipient's pubkey
        guard let filter = Filter(kinds: [EventKind.giftWrap.rawValue], pubkeys: [keypair.publicKey.hex]) else {
            nostrLogger.error("Failed to create filter for gift wrap events")
            isListeningForMessages = false
            return
        }
        
        // Subscribe to the filter
        let subscriptionId = relayPool.subscribe(with: filter)
        messageSubscriptionId = subscriptionId
        
        nostrLogger.info("Subscribed to gift wrap events with id: \(subscriptionId)")
        
        // Listen for events
        relayPool.events
            .sink { [weak self] relayEvent in
                guard let self = self else { return }
                Task { @MainActor in
                    await self.handleIncomingEvent(relayEvent.event)
                }
            }
            .store(in: &cancellables)
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
        nostrLogger.debug("Received event \(event.id)")
        
        guard let keypair = try? getKeypair() else {
            nostrLogger.error("Cannot handle event: no keypair available")
            return
        }
        
        // Cast to GiftWrapEvent and unwrap it
        guard let giftWrapEvent = event as? GiftWrapEvent else {
            nostrLogger.debug("Event \(event.id) is not a GiftWrapEvent")
            return
        }
        
        // Try to unseal the rumor inside the gift wrap
        guard let unwrappedEvent = try? giftWrapEvent.unsealedRumor(using: keypair.privateKey) else {
            nostrLogger.debug("Failed to unwrap gift wrap event \(event.id)")
            return
        }
        
        nostrLogger.info("Successfully unwrapped gift wrap event \(event.id)")
        
        // Check if the content contains ecash tokens
        if containsEcashToken(unwrappedEvent.content) {
            let message = ReceivedEcashMessage(
                id: unwrappedEvent.id,
                content: unwrappedEvent.content,
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
            nostrLogger.debug("Message does not contain ecash token")
        }
    }
    
    /// Checks if a message contains an ecash token
    /// Looks for cashu token patterns (cashuA...)
    private func containsEcashToken(_ content: String) -> Bool {
        // Cashu tokens typically start with "cashuA" (version A)
        // They can be embedded in text or standalone
        let pattern = "cashu[A-Za-z0-9+/=]+"
        
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return false
        }
        
        let range = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, options: [], range: range)
        
        let hasToken = !matches.isEmpty
        if hasToken {
            nostrLogger.debug("Found ecash token in content")
        }
        
        return hasToken
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
