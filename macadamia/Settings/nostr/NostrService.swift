//
//  NostrService.swift
//  macadamia
//
//  Created by zm on 09.11.25.
//

import SwiftUI
import NostrSDK
import Combine
import OSLog

// Type aliases to avoid conflicts with SwiftUI.Tag
typealias NostrTag = NostrSDK.Tag
typealias NostrTagName = NostrSDK.TagName

// MARK: - Nostr Data Models (In-Memory)

struct PrivateMessage: Identifiable {
    let id: String // event id
    let type: MessageType
    let sender: String // sender pubkey
    let recipient: String // recipient pubkey (our user)
    let content: String // decrypted content
    let createdAt: Date
    let subject: String? // For NIP-17 direct messages
    
    enum MessageType {
        case nip4  // Legacy encrypted DM
        case nip17 // Gift-wrapped private message
    }
    
    init(id: String, type: MessageType, sender: String, recipient: String, content: String, createdAt: Int64, subject: String? = nil) {
        self.id = id
        self.type = type
        self.sender = sender
        self.recipient = recipient
        self.content = content
        self.createdAt = Date(timeIntervalSince1970: TimeInterval(createdAt))
        self.subject = subject
    }
}

struct NostrProfile: Identifiable, Codable {
    let id: String // pubkey
    var pubkey: String { id }
    var name: String?
    var displayName: String?
    var about: String?
    var pictureURL: String?
    var bannerPictureURL: String?
    var nostrAddress: String?
    var lightningAddress: String?
    var websiteURL: String?
    var isBot: Bool?
    var lastUpdated: Date
    
    enum CodingKeys: String, CodingKey {
        case id, name, displayName, about, pictureURL, bannerPictureURL
        case nostrAddress, lightningAddress, websiteURL, isBot, lastUpdated
    }
    
    init(pubkey: String, name: String? = nil, displayName: String? = nil, about: String? = nil,
         pictureURL: String? = nil, bannerPictureURL: String? = nil, nostrAddress: String? = nil,
         lightningAddress: String? = nil, websiteURL: String? = nil, isBot: Bool? = nil,
         lastUpdated: Date = Date()) {
        self.id = pubkey
        self.name = name
        self.displayName = displayName
        self.about = about
        self.pictureURL = pictureURL
        self.bannerPictureURL = bannerPictureURL
        self.nostrAddress = nostrAddress
        self.lightningAddress = lightningAddress
        self.websiteURL = websiteURL
        self.isBot = isBot
        self.lastUpdated = lastUpdated
    }
    
    mutating func update(from event: MetadataEvent) {
        self.name = event.name
        self.displayName = event.displayName
        self.about = event.about
        self.pictureURL = event.pictureURL?.absoluteString
        self.bannerPictureURL = event.bannerPictureURL?.absoluteString
        self.nostrAddress = event.nostrAddress
        self.lightningAddress = event.lightningAddress
        self.websiteURL = event.websiteURL?.absoluteString
        self.isBot = event.isBot
        self.lastUpdated = Date()
    }
}

struct NostrContact: Identifiable, Codable {
    let id: String // Composite: ownerPubkey + contactPubkey
    var ownerPubkey: String
    var contactPubkey: String
    var petname: String?
    var relayURL: String?
    var dateAdded: Date
    
    init(ownerPubkey: String, contactPubkey: String, petname: String? = nil,
         relayURL: String? = nil, dateAdded: Date = Date()) {
        self.id = "\(ownerPubkey)_\(contactPubkey)"
        self.ownerPubkey = ownerPubkey
        self.contactPubkey = contactPubkey
        self.petname = petname
        self.relayURL = relayURL
        self.dateAdded = dateAdded
    }
}

struct NostrRelay: Identifiable {
    let id: String // url
    var url: String { id }
    var read: Bool
    var write: Bool
    var dateAdded: Date
    var lastConnected: Date?
    
    init(url: String, read: Bool = true, write: Bool = true, dateAdded: Date = Date()) {
        self.id = url
        self.read = read
        self.write = write
        self.dateAdded = dateAdded
    }
}

// MARK: - NostrService

fileprivate let nostrLogger = Logger(subsystem: "macadamia", category: "NostrService")

enum ConnectionStatus: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
}

enum NostrServiceError: Error {
    case noKeypairAvailable
    case invalidRecipientPubkey
    case encryptionFailed
    case eventCreationFailed
}

class NostrService: ObservableObject, EventCreating {
    
    // MARK: - Reactive Properties (In-Memory)
    
    @Published var currentProfile: NostrProfile?
    @Published var contacts: [NostrContact] = []
    @Published var contactProfiles: [String: NostrProfile] = [:]
    @Published var relays: [NostrRelay] = []
    @Published var isConnected: Bool = false
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var privateMessages: [PrivateMessage] = []
    
    // MARK: - Private Properties
    
    private var relayPool: RelayPool?
    private var subscriptions: Set<String> = []
    private var cancellables = Set<AnyCancellable>()
    private var currentUserPubkey: String?
    private var currentUserKeypair: Keypair?
    private var relayURLsObserver: AnyCancellable?
    
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
    
    // MARK: - Initialization
    
    init() {
        nostrLogger.info("NostrService initialized with cache support")
        
        // Check if user has a key - if not, clear any stale cache
        if !NostrKeychain.hasNsec() {
            nostrLogger.info("No Nostr key found, clearing any stale cache")
            NostrCache.shared.clearAll()
        } else {
            // Load cached data
            loadFromCache()
        }
        
        // Observe relay changes
        observeRelayChanges()
    }
    
    // MARK: - Public Methods
    
    func start() {
        nostrLogger.info("Starting NostrService")
        
        // Check if user has a key
        guard let keyString = try? NostrKeychain.getNsec() else {
            nostrLogger.warning("No Nostr key found, cannot start service")
            connectionStatus = .error("No key found")
            return
        }
        
        // Parse keypair
        guard let keypair = parseKeypair(from: keyString) else {
            nostrLogger.error("Failed to parse keypair from stored key")
            connectionStatus = .error("Invalid key")
            return
        }
        
        currentUserPubkey = keypair.publicKey.hex
        currentUserKeypair = keypair
        
        // Check if user changed and clear cache if so
        NostrCache.shared.checkAndClearIfUserChanged(currentPubkey: keypair.publicKey.hex)
        
        // Reload from cache after potential clear
        loadFromCache()
        
        // Connect to relays
        connectToRelays()
    }
    
    func stop() {
        nostrLogger.info("Stopping NostrService (keeping data in memory)")
        
        // Save current data to cache before stopping
        saveToCache()
        
        // Close all subscriptions
        subscriptions.forEach { subscriptionId in
            relayPool?.closeSubscription(with: subscriptionId)
        }
        subscriptions.removeAll()
        
        // Disconnect from relays
        relayPool?.disconnect()
        relayPool = nil
        
        // Cancel all combine subscriptions
        cancellables.removeAll()
        
        // Update connection status but keep all data in memory
        isConnected = false
        connectionStatus = .disconnected
        
        // Clear private messages (ephemeral only)
        privateMessages.removeAll()
        
        // Keep: currentProfile, contacts, contactProfiles, currentUserPubkey, currentUserKeypair
        // This allows viewing cached data when disconnected
    }
    
    func clearCacheAndStop() {
        nostrLogger.info("Clearing cache and stopping NostrService")
        
        // First disconnect without saving
        subscriptions.forEach { subscriptionId in
            relayPool?.closeSubscription(with: subscriptionId)
        }
        subscriptions.removeAll()
        
        relayPool?.disconnect()
        relayPool = nil
        cancellables.removeAll()
        
        // Clear all in-memory data
        currentProfile = nil
        contacts.removeAll()
        contactProfiles.removeAll()
        privateMessages.removeAll()
        
        isConnected = false
        connectionStatus = .disconnected
        currentUserPubkey = nil
        currentUserKeypair = nil
        
        // Clear the cache files
        NostrCache.shared.clearAll()
        
        nostrLogger.info("All Nostr data and cache cleared")
    }
    
    func refreshProfile() {
        guard let pubkey = currentUserPubkey else { return }
        subscribeToProfile(pubkey: pubkey)
    }
    
    func refreshContacts() {
        guard let pubkey = currentUserPubkey else { return }
        subscribeToContacts(pubkey: pubkey)
    }
    
    // MARK: - Message Sending
    
    @MainActor
    func sendNIP4Message(to recipientPubkey: String, content: String) async throws {
        guard let keypair = currentUserKeypair else {
            throw NostrServiceError.noKeypairAvailable
        }
        
        guard let recipientPublicKey = PublicKey(hex: recipientPubkey) else {
            throw NostrServiceError.invalidRecipientPubkey
        }
        
        // Create and sign the encrypted direct message event
        let event = try legacyEncryptedDirectMessage(
            withContent: content,
            toRecipient: recipientPublicKey,
            signedBy: keypair
        )
        
        // Publish to all connected relays
        relayPool?.publishEvent(event)
        
        nostrLogger.info("Sent NIP-4 message to \(recipientPubkey.prefix(8))...")
    }
    
    @MainActor
    func sendNIP17Message(to recipientPubkey: String, content: String, subject: String? = nil) async throws {
        guard let keypair = currentUserKeypair else {
            throw NostrServiceError.noKeypairAvailable
        }
        
        guard let recipientPublicKey = PublicKey(hex: recipientPubkey) else {
            throw NostrServiceError.invalidRecipientPubkey
        }
        
        // Create the DirectMessageEvent rumor (unsigned)
        // The rumor must include a p tag for the recipient to define the chat room
        let recipientTag = NostrTag(name: "p", value: recipientPubkey, otherParameters: [])
        var builder = DirectMessageEvent.Builder()
            .content(content)
            .appendTags(recipientTag)
        
        // Add subject if provided
        if let subject = subject {
            builder = builder.subject(subject)
        }
        
        // Build as rumor (unsigned event)
        let directMessageRumor = builder.build(pubkey: keypair.publicKey)
        
        // Create the gift wrap (handles seal + wrap internally)
        let giftWrapEvent = try giftWrap(
            withDirectMessageEvent: directMessageRumor,
            toRecipient: recipientPublicKey,
            signedBy: keypair
        )
        
        // Publish to all connected relays
        relayPool?.publishEvent(giftWrapEvent)
        
        nostrLogger.info("Sent NIP-17 gift wrapped message to \(recipientPubkey.prefix(8))...")
    }
    
    func updateRelays(_ urls: [URL]) {
        nostrLogger.info("Updating relays to: \(urls.map { $0.absoluteString })")
        savedURLs = urls
        
        // If service is running, reconnect with new relays
        if isConnected || connectionStatus != .disconnected {
            stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.start()
            }
        }
    }
    
    // MARK: - Private Methods - Relay Management
    
    private func connectToRelays() {
        let relayURLs = savedURLs
        
        guard !relayURLs.isEmpty else {
            nostrLogger.warning("No relay URLs configured")
            connectionStatus = .error("No relays configured")
            return
        }
        
        connectionStatus = .connecting
        
        do {
            relayPool = try RelayPool(relayURLs: Set(relayURLs))
            
            // Subscribe to relay events
            relayPool?.events
                .receive(on: DispatchQueue.main)
                .sink { [weak self] relayEvent in
                    self?.handleRelayEvent(relayEvent)
                }
                .store(in: &cancellables)
            
            // Connect
            relayPool?.connect()
            
            // Wait a bit for connections, then subscribe
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self, let pool = self.relayPool else { return }
                
                let connectedCount = pool.relays.filter { $0.state == .connected }.count
                if connectedCount > 0 {
                    self.isConnected = true
                    self.connectionStatus = .connected
                    self.subscribeToAllData()
                    nostrLogger.info("Connected to \(connectedCount) relays")
                } else {
                    self.connectionStatus = .error("Failed to connect to relays")
                    nostrLogger.warning("No relays connected")
                }
            }
            
        } catch {
            nostrLogger.error("Failed to create relay pool: \(error.localizedDescription)")
            connectionStatus = .error(error.localizedDescription)
        }
    }
    
    private func observeRelayChanges() {
        // Observe AppStorage changes for relay URLs
        relayURLsObserver = NotificationCenter.default.publisher(
            for: UserDefaults.didChangeNotification
        )
        .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.handleRelayURLsChanged()
        }
    }
    
    private func handleRelayURLsChanged() {
        guard isConnected else { return }
        
        let newURLs = savedURLs
        let currentURLs = relayPool?.relays.map { $0.url } ?? []
        
        // Check if URLs actually changed
        if Set(newURLs) != Set(currentURLs) {
            nostrLogger.info("Relay URLs changed, reconnecting...")
            stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.start()
            }
        }
    }
    
    // MARK: - Private Methods - Subscriptions
    
    private func subscribeToAllData() {
        guard let pubkey = currentUserPubkey else { return }
        
        subscribeToProfile(pubkey: pubkey)
        subscribeToContacts(pubkey: pubkey)
        subscribeToPrivateMessages(pubkey: pubkey)
    }
    
    private func subscribeToProfile(pubkey: String) {
        guard let filter = Filter(authors: [pubkey], kinds: [0], limit: 1) else {
            nostrLogger.error("Failed to create profile filter")
            return
        }
        
        let subId = relayPool?.subscribe(with: filter) ?? ""
        subscriptions.insert(subId)
        nostrLogger.info("Subscribed to profile with id: \(subId)")
    }
    
    private func subscribeToContacts(pubkey: String) {
        guard let filter = Filter(authors: [pubkey], kinds: [3], limit: 1) else {
            nostrLogger.error("Failed to create contacts filter")
            return
        }
        
        let subId = relayPool?.subscribe(with: filter) ?? ""
        subscriptions.insert(subId)
        nostrLogger.info("Subscribed to contacts with id: \(subId)")
    }
    
    private func subscribeToContactProfiles(pubkeys: [String]) {
        guard !pubkeys.isEmpty else { return }
        
        // Subscribe in batches of 50 to avoid overwhelming relays
        let batchSize = 50
        for batch in stride(from: 0, to: pubkeys.count, by: batchSize) {
            let endIndex = min(batch + batchSize, pubkeys.count)
            let batchPubkeys = Array(pubkeys[batch..<endIndex])
            
            guard let filter = Filter(authors: batchPubkeys, kinds: [0], limit: batchSize) else {
                continue
            }
            
            let subId = relayPool?.subscribe(with: filter) ?? ""
            subscriptions.insert(subId)
            nostrLogger.info("Subscribed to \(batchPubkeys.count) contact profiles")
        }
    }
    
    private func subscribeToPrivateMessages(pubkey: String) {
        // Subscribe to NIP-4 legacy encrypted direct messages (kind 4)
        // These are messages where we are either sender or recipient
        guard let nip4Filter = Filter(kinds: [4], pubkeys: [pubkey], limit: 100) else {
            nostrLogger.error("Failed to create NIP-4 filter")
            return
        }
        
        let nip4SubId = relayPool?.subscribe(with: nip4Filter) ?? ""
        subscriptions.insert(nip4SubId)
        nostrLogger.info("Subscribed to NIP-4 messages with id: \(nip4SubId)")
        
        // Subscribe to NIP-17 gift-wrapped messages (kind 1059)
        // These are addressed to our pubkey via p-tag
        guard let nip17Filter = Filter(kinds: [1059], pubkeys: [pubkey], limit: 100) else {
            nostrLogger.error("Failed to create NIP-17 filter")
            return
        }
        
        let nip17SubId = relayPool?.subscribe(with: nip17Filter) ?? ""
        subscriptions.insert(nip17SubId)
        nostrLogger.info("Subscribed to NIP-17 gift wraps with id: \(nip17SubId)")
    }
    
    // MARK: - Private Methods - Event Handling
    
    private func handleRelayEvent(_ relayEvent: RelayEvent) {
        nostrLogger.debug("Received event: kind=\(relayEvent.event.kind.rawValue), id=\(relayEvent.event.id)")
        
        // Handle MetadataEvent (kind 0)
        if let metadataEvent = relayEvent.event as? MetadataEvent {
            handleMetadataEvent(metadataEvent)
        }
        
        // Handle FollowListEvent (kind 3)
        if let followListEvent = relayEvent.event as? FollowListEvent {
            handleFollowListEvent(followListEvent)
        }
        
        // Handle NIP-4 Legacy Encrypted Direct Messages (kind 4)
        if relayEvent.event.kind == .legacyEncryptedDirectMessage {
            handleNIP4Message(relayEvent.event)
        }
        
        // Handle NIP-17 Gift Wrapped Messages (kind 1059)
        if let giftWrapEvent = relayEvent.event as? GiftWrapEvent {
            handleNIP17GiftWrap(giftWrapEvent)
        }
    }
    
    private func handleMetadataEvent(_ event: MetadataEvent) {
        let pubkey = event.pubkey
        
        nostrLogger.info("Processing metadata event for pubkey: \(pubkey)")
        
        // Check if it's the current user's profile
        if pubkey == currentUserPubkey {
            if currentProfile != nil {
                currentProfile?.update(from: event)
            } else {
                currentProfile = NostrProfile(
                    pubkey: pubkey,
                    name: event.name,
                    displayName: event.displayName,
                    about: event.about,
                    pictureURL: event.pictureURL?.absoluteString,
                    bannerPictureURL: event.bannerPictureURL?.absoluteString,
                    nostrAddress: event.nostrAddress,
                    lightningAddress: event.lightningAddress,
                    websiteURL: event.websiteURL?.absoluteString,
                    isBot: event.isBot
                )
            }
            nostrLogger.info("Updated current user profile")
        } else {
            // It's a contact's profile
            var profile = contactProfiles[pubkey] ?? NostrProfile(pubkey: pubkey)
            profile.update(from: event)
            contactProfiles[pubkey] = profile
            nostrLogger.info("Updated contact profile for \(pubkey)")
        }
        
        // Save to cache after updating
        saveToCache()
    }
    
    private func handleFollowListEvent(_ event: FollowListEvent) {
        guard event.pubkey == currentUserPubkey else { return }
        
        nostrLogger.info("Processing follow list event with \(event.followedPubkeys.count) contacts")
        
        // Clear existing contacts
        contacts.removeAll()
        
        // Add new contacts
        for pubkeyTag in event.followedPubkeyTags {
            let contactPubkey = pubkeyTag.value
            let petname = pubkeyTag.otherParameters.indices.contains(0) ? pubkeyTag.otherParameters[0] : nil
            let relayURL = pubkeyTag.otherParameters.indices.contains(1) ? pubkeyTag.otherParameters[1] : nil
            
            let contact = NostrContact(
                ownerPubkey: event.pubkey,
                contactPubkey: contactPubkey,
                petname: petname,
                relayURL: relayURL
            )
            contacts.append(contact)
        }
        
        nostrLogger.info("Loaded \(self.contacts.count) contacts into memory")
        
        // Save to cache after updating contacts
        saveToCache()
        
        // Subscribe to contact profiles
        subscribeToContactProfiles(pubkeys: event.followedPubkeys)
    }
    
    // MARK: - Private Methods - Message Decryption
    
    private func handleNIP4Message(_ event: NostrEvent) {
        guard let keypair = currentUserKeypair,
              let myPubkey = currentUserPubkey else {
            nostrLogger.error("Cannot decrypt NIP-4 message: no keypair available")
            return
        }
        
        // Determine sender and recipient
        // If we sent it, the p-tag contains the recipient
        // If we received it, the author is the sender
        let senderPubkey: String
        let recipientPubkey: String
        
        if event.pubkey == myPubkey {
            // We sent this message
            guard let pTag = event.tags.first(where: { $0.name == "p" }) else {
                nostrLogger.error("NIP-4 message missing recipient p-tag")
                return
            }
            senderPubkey = myPubkey
            recipientPubkey = pTag.value
        } else {
            // We received this message
            senderPubkey = event.pubkey
            recipientPubkey = myPubkey
        }
        
        // Get sender's public key for decryption
        guard let senderPublicKey = PublicKey(hex: senderPubkey) else {
            nostrLogger.error("Invalid sender public key in NIP-4 message")
            return
        }
        
        // Decrypt the message using NIP-4 legacy decryption
        do {
            // Create a helper that conforms to LegacyDirectMessageEncrypting
            struct DecryptHelper: LegacyDirectMessageEncrypting {}
            let helper = DecryptHelper()
            
            let decryptedContent = try helper.legacyDecrypt(
                encryptedContent: event.content,
                privateKey: keypair.privateKey,
                publicKey: senderPublicKey
            )
            
            // Create and store the message
            let message = PrivateMessage(
                id: event.id,
                type: .nip4,
                sender: senderPubkey,
                recipient: recipientPubkey,
                content: decryptedContent,
                createdAt: event.createdAt
            )
            
            // Avoid duplicates
            if !privateMessages.contains(where: { $0.id == message.id }) {
                privateMessages.append(message)
                privateMessages.sort { $0.createdAt > $1.createdAt }
                nostrLogger.info("Decrypted and stored NIP-4 message from \(senderPubkey.prefix(8))...")
            }
            
        } catch {
            nostrLogger.error("Failed to decrypt NIP-4 message: \(error.localizedDescription)")
        }
    }
    
    private func handleNIP17GiftWrap(_ giftWrap: GiftWrapEvent) {
        guard let keypair = currentUserKeypair,
              let myPubkey = currentUserPubkey else {
            nostrLogger.error("Cannot unwrap NIP-17 message: no keypair available")
            return
        }
        
        do {
            // Unwrap the gift wrap to get the seal
            let seal = try giftWrap.unwrappedSeal(using: keypair.privateKey)
            
            // Unseal to get the rumor (the actual direct message)
            let rumor = try seal.unsealedRumor(using: keypair.privateKey)
            
            // Parse as DirectMessageEvent if it's kind 14
            let senderPubkey = rumor.pubkey
            let recipientPubkey = myPubkey // Gift wraps are sent to us
            let content = rumor.content
            
            // Extract subject if it exists (NIP-17 feature)
            let subject = rumor.tags.first(where: { $0.name == "subject" })?.value
            
            // Create and store the message
            let message = PrivateMessage(
                id: rumor.id,
                type: .nip17,
                sender: senderPubkey,
                recipient: recipientPubkey,
                content: content,
                createdAt: rumor.createdAt,
                subject: subject
            )
            
            // Avoid duplicates
            if !privateMessages.contains(where: { $0.id == message.id }) {
                privateMessages.append(message)
                privateMessages.sort { $0.createdAt > $1.createdAt }
                nostrLogger.info("Unwrapped and stored NIP-17 message from \(senderPubkey.prefix(8))...")
            }
            
        } catch {
            nostrLogger.error("Failed to unwrap NIP-17 gift wrap: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Cache Management
    
    private func loadFromCache() {
        // Load profiles
        contactProfiles = NostrCache.shared.loadProfiles()
        
        // Load contacts
        contacts = NostrCache.shared.loadContacts()
        
        // Try to load current user profile if we have a pubkey
        if let pubkey = currentUserPubkey ?? NostrCache.shared.getCurrentUserPubkey() {
            currentProfile = contactProfiles[pubkey]
        }
        
        nostrLogger.info("Loaded from cache: currentProfile=\(self.currentProfile != nil), contacts=\(self.contacts.count), profiles=\(self.contactProfiles.count)")
    }
    
    private func saveToCache() {
        // Save profiles (including current user profile if exists)
        var allProfiles = contactProfiles
        if let currentProfile = currentProfile {
            allProfiles[currentProfile.pubkey] = currentProfile
        }
        NostrCache.shared.saveProfiles(allProfiles)
        
        // Save contacts
        NostrCache.shared.saveContacts(contacts)
        
        nostrLogger.info("Saved to cache: profiles=\(allProfiles.count), contacts=\(self.contacts.count)")
    }
    
    // MARK: - Helper Methods
    
    private func parseKeypair(from keyString: String) -> Keypair? {
        let normalized = keyString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if normalized.lowercased().hasPrefix("nsec") {
            return Keypair(nsec: normalized)
        } else {
            return Keypair(hex: normalized)
        }
    }
}
