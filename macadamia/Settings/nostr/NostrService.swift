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
}


class NostrService: ObservableObject, EventCreating, MetadataCoding {
    
    enum ConnectionState {
        case noneConnected, partiallyConnected(Int), allConnected(Int)
    }
    
    // MARK: - Reactive Properties (In-Memory)
    
    @Published var connectionStates = [URL: Relay.State]()
    
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
//    private var subscriptions: Set<String> = [] // will be needed later for message checking
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
                }
                .store(in: &cancellables)
        }
        
        relayPool?.connect()
    }
    
    func disconnect() {
        
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
