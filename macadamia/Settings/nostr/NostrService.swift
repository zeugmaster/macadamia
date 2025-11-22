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

class NostrService: ObservableObject, EventCreating {
    
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
    
    func sendNIP17(from nsec: String, to receiverNpub: String, message: String) {
        
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
