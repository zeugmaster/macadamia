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

// Type aliases to avoid conflicts with SwiftUI.Tag
typealias NostrTag = NostrSDK.Tag
typealias NostrTagName = NostrSDK.TagName

// MARK: - Nostr Data Models (In-Memory)

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
    
    @Published var relays: [NostrRelay] = []
    @Published var isConnected: Bool = false
    @Published var connectionStatus: ConnectionStatus = .disconnected
    
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
        nostrLogger.info("NostrService initialized")
        
        // Check if user has a key - if not, clear any stale cache
        if !NostrKeychain.hasNsec() {
            nostrLogger.info("No Nostr key found, clearing any stale cache")
//            NostrCache.shared.clearAll()
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
//        NostrCache.shared.checkAndClearIfUserChanged(currentPubkey: keypair.publicKey.hex)
        
        // Connect to relays
        connectToRelays()
    }
    
    func stop() {
        nostrLogger.info("Stopping NostrService")
        
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
        
        // Update connection status
        isConnected = false
        connectionStatus = .disconnected
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
        
        isConnected = false
        connectionStatus = .disconnected
        currentUserPubkey = nil
        currentUserKeypair = nil
        
        // Clear the cache files
//        NostrCache.shared.clearAll()
        
        nostrLogger.info("All Nostr data and cache cleared")
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
            
            // Wait a bit for connections
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self, let pool = self.relayPool else { return }
                
                let connectedCount = pool.relays.filter { $0.state == .connected }.count
                if connectedCount > 0 {
                    self.isConnected = true
                    self.connectionStatus = .connected
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
    
    // MARK: - Private Methods - Event Handling
    
    private func handleRelayEvent(_ relayEvent: RelayEvent) {
        // Minimal event handling - can be extended for future nostr features
        nostrLogger.debug("Received event: kind=\(relayEvent.event.kind.rawValue), id=\(relayEvent.event.id)")
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
