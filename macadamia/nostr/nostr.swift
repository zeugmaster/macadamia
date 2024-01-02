//
//  nostr.swift
//  nostr-test
//
//  Created by Dario Lass on 21.12.23.
//

import SwiftUI
import NostrSDK
import OSLog
import Combine

#warning("change to appropriate subsystem")
var logger = Logger(subsystem: "zeugmaster.nostr-test", category: "nostr")

class Profile: Equatable, CustomStringConvertible, ObservableObject {
    var description: String {
        let description = "\(npub.prefix(12)) name: \(name ?? "nil")"
        return description
    }
    
    static func == (lhs: Profile, rhs: Profile) -> Bool {
        lhs.pubkey == rhs.pubkey
    }
    
    let pubkey:String
    let npub:String
    var name:String?
    var pictureURL:URL?
    
    init(pubkey: String, npub: String, name: String? = nil, pictureURL: URL? = nil) {
        self.pubkey = pubkey
        self.npub = npub
        self.name = name
        self.pictureURL = pictureURL
    }
    
}

struct Message {
    let senderPubkey:String
    let decryptedContent:String
}

enum ContactServiceError: Error {
    case invalidRelayURLError
    case invalidKeyError
    case relayConnectionError
    case noPrivateKeyError
    case invalidEventType
    case timeout
    case relayQueryError
}

class ContactService: EventCreating {
    
    let relayURLs = ["wss://relay.damus.io",
                     "wss://nostr.wine",
                     "wss://filter.nostr.wine/npub1f742zec57c6qk9ajfr8wyjn0s4vrfzh4hesyj2yqplvj5wrfydxsjprpa3?broadcast=true&global=all",
                     "wss://purplepag.es",
                     "wss://nos.lol",
                     "wss://zeugmaster.com",
                     "wss://relay.snort.social"]
    
    private var eventsCancellable: AnyCancellable?
    private var stateCancellable: AnyCancellable?
    private var relayError: String?
    var state: Relay.State = .notConnected
            
    var relays = [Relay]()
    var relayStates = Dictionary<String,Relay.State>()
    var userProfile:Profile?
    
    var keyManager = KeyManager()
    var relayListManager = RelayListManager()
    
    //MARK: - Key handling
    func setPrivateKey(privateKey:String) throws {
        try keyManager.setPrivateKey(privateKey: privateKey)
    }
    
    //MARK: - Initializer
    init() throws {
        logger.debug("Initializing ContactService instance")
                
        relays = try relayURLs.map({ urlString in
            //TODO: check for proper URL initialization
            try Relay(url: URL(string: urlString)!)
        })
    }
    
    ///Try to establish a websocket connection to relay
    func connectAll() {
        for r in relays {
            r.connect()
            _ = r.$state
                .receive(on: DispatchQueue.main)
                .sink { newState in
                    self.relayStates[r.url.absoluteString] = newState
                }
        }
    }
    
    func disconnectAll() {
        for connectedRelay in connectedRelays {
            connectedRelay.disconnect()
        }
    }
    
    var connectedRelays:[Relay] {
        get {
            return relays.filter({ $0.state == Relay.State.connected })
        }
    }
    
    ///Fetch contact list events. Returns cleaned list of `[Profile]`
    func fetchContactList() async throws -> [Profile] {
        
        guard let pubkeyhex = keyManager.keypair?.publicKey.hex else {
            throw ContactServiceError.noPrivateKeyError
        }
        
        // kind "3" for follow list events
        let filter = Filter(authors: [pubkeyhex], kinds: [3])
        let events = try await loadEventsWithFilter(filter: filter, from: connectedRelays)
        
        guard !events.isEmpty else {
            logger.warning("Follower list from relay is empty.")
            return []
        }
        
        // de-dup and get latest (newest) event
        let latest = events.deduplicated().latest()
        
        //cast generic NostrEvent as ContactListEvent
        guard let followListEvent = latest as? FollowListEvent else {
            let message = "Could not cast list of NostrEvent to ContactListEvent. Events: "
            logger.error("\(message)\(String(describing: events), privacy: .public)")
            throw ContactServiceError.relayQueryError
        }

        // followlist also contains duplicates and self-follow
        // which need to be removed
        // TODO: ensure order is kept when doing Array(Set(x))
        var contactPubkeys = Array(Set(followListEvent.followedPubkeys))
        contactPubkeys.removeAll(where: {$0 == keyManager.keypair?.publicKey.hex})
        
        // returns the array of pubkeys and tries to also supply public keys as npub
        return contactPubkeys.map { pubkey in
            guard let pk = PublicKey(hex: pubkey) else {
                logger.warning("Could not create PublicKey object from hex: \(pubkey)")
                return Profile(pubkey: pubkey, npub: "")
            }
            return Profile(pubkey: pk.hex, npub: pk.npub)
        }
    }
    
    func loadInfo(for profiles:[Profile]) async throws {
        
        guard keyManager.keypair?.publicKey.hex != nil else {
            throw ContactServiceError.noPrivateKeyError
        }
        
        if profiles.isEmpty {
            logger.warning("loadInfo: input array was emtpy, returning empty")
        }
        
        // create an array of all the pubkeys so we can query the relays all at once
        let pubkeys = profiles.map { $0.pubkey }
        
        // kind 0 for profile metadata
        let filter = Filter(authors: pubkeys, kinds: [0])
        let events = try await loadEventsWithFilter(filter: filter, from: connectedRelays)
        
        guard let unique = events.deduplicated() as? [SetMetadataEvent] else {
            let message = "Could not cast list of NostrEvent to ContactListEvent. Events: "
            logger.error("\(message)\(String(describing: events), privacy: .public)")
            throw ContactServiceError.relayQueryError
        }
        
        //TODO: check for outdated events for the same user
        for profile in profiles {
            let pe = unique.first(where: {$0.pubkey == profile.pubkey })
            profile.pictureURL = pe?.userMetadata?.pictureURL
            if let name = pe?.userMetadata?.name, name.count > 0 {
                profile.name = name
            }
        }
    }
    
    func checkInbox() async throws -> [Message] {
        
        guard keyManager.keypair?.publicKey.hex != nil else {
            throw ContactServiceError.noPrivateKeyError
        }
        
        //loads all message events adressed to OUR  public key (incoming messages)
        let filter = Filter(kinds: [4],pubkeys:[keyManager.keypair!.publicKey.hex])
                
        let events = try await loadEventsWithFilter(filter: filter, from: connectedRelays)
        
        guard let messageEvents = events.deduplicated() as? [DirectMessageEvent] else {
            let message = "Could not cast list of NostrEvent to ContactListEvent. Events: "
            logger.error("\(message)\(String(describing: events), privacy: .public)")
            throw ContactServiceError.relayQueryError
        }
        
        let messages = try messageEvents.map { me in
            let content = try me.decryptedContent(using: keyManager.keypair!.privateKey,
                                                  publicKey: PublicKey(hex: me.pubkey)!)
            return Message(senderPubkey: me.pubkey, decryptedContent: content)
        }
         
        return messages
    }
    
    ///`async` call to to load all events from multiple relays with a specified filter
    ///Will likely contain duplicates.
    private func loadEventsWithFilter(filter:Filter,
                                      from relays:[Relay]) async throws -> [NostrEvent] {
        
        return try await withCheckedThrowingContinuation { continuation in
            loadEventsWithFilter(filter: filter, from: relays) { completion in
                switch completion {
                case .success(let events):
                    continuation.resume(returning: events)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /* potential solution for multi relay query
     TODO: make sure relays actually are connected */
    ///will produce duplicate entries
    private func loadEventsWithFilter(filter: Filter,
                                      from relays: [Relay],
                                      completion: @escaping (Result<[NostrEvent], Error>) -> Void) {
        let fs = String(describing: filter)
        logger.info("Attempting to load nostr events with filter: \(fs, privacy: .public)")
        var events = [NostrEvent]()
        var subscriptions = Set<AnyCancellable>()
        let subscriptionQueue = DispatchQueue(label: "zeugmaster.nostr-test.nostrRelaySubscriptionQueue")

        let group = DispatchGroup()
        for relay in relays {
            group.enter()
            do {
                let subscriptionId = try relay.subscribe(with: filter)

                relay.events
                    .receive(on: DispatchQueue.main)
                    .compactMap { $0.event }
                    .sink(
                        receiveCompletion: { completionResult in
                            switch completionResult {
                            case .failure(let error):
                                completion(.failure(error))
                                group.leave()
                            case .finished:
                                group.leave()
                            }
                        },
                        receiveValue: { event in
                            events.insert(event, at: 0)
                        }
                    )
                    .store(in: &subscriptions)

                // Schedule to close the subscription after the timeout
                DispatchQueue.global().asyncAfter(deadline: .now() + 1) { // 1 second timeout
                    subscriptionQueue.sync {
                        subscriptions.forEach { $0.cancel() }
                    }
                    try? relay.closeSubscription(with: subscriptionId)
                    group.leave()
                }
            } catch {
                completion(.failure(error))
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(.success(events))
        }
    }

    
    func sendMessage(to contact:Profile) throws {
        
        guard keyManager.keypair != nil else {
            throw ContactServiceError.noPrivateKeyError
        }
        guard let pubkey = PublicKey(hex: contact.pubkey) else {
            throw ContactServiceError.invalidKeyError
        }
        
        let message = try directMessage(withContent: "This is a test.",
                                    toRecipient: pubkey,
                                    signedBy: keyManager.keypair!)
        
        for relay in connectedRelays {
            do {
                try relay.publishEvent(message)
            } catch {
                print("could not post to \(relay) because of \(error)")
            }
        }
        
    }
    
}

class KeyManager {
    
    private var privateKeyHexString:String?
    
    private var privateKey:String? {
        set {
            //set and write to file
            privateKeyHexString = newValue
            writeKeyStringToDisk(keyString: privateKeyHexString!)
        }
        get {
            //if nil check disk, if unsuccessful return nil
            if privateKeyHexString == nil {
                let saved = keyStringFromDisk()
                privateKeyHexString = saved
                return saved
            } else {
                return privateKeyHexString
            }
        }
    }
    
    ///Takes a nostr private key either as HEX or bech32 with leading `nsec`
    func setPrivateKey(privateKey:String) throws {
        let pk:PrivateKey?
        if privateKey.lowercased().hasPrefix("nsec") {
            pk = PrivateKey(nsec: privateKey)
        } else {
            pk = PrivateKey(hex: privateKey)
        }
        guard pk != nil else {
            throw ContactServiceError.invalidKeyError
        }
        self.privateKey = pk?.hex
    }
    
    ///Return nil if keypair has not been set through `setPrivateKey` and not an disk
    var keypair: Keypair? {
        if let privateKey = privateKey, let pk = PrivateKey(hex: privateKey) {
            return Keypair(privateKey: pk)
        } else {
            return nil
        }
    }
    
    private func keyStringFromDisk() -> String? {
        if let data = try? Data(contentsOf: KeyManager.getFilePath()) {
            logger.debug("Successfully read key string from disk.")
            return String(data: data, encoding: .utf8)
        } else {
            logger.warning("Could not read key string from disk. (might not be set yet.")
            return nil
        }
    }
    
    private func writeKeyStringToDisk(keyString:String) {
        do {
            let data = keyString.data(using: .utf8)
            try data?.write(to: KeyManager.getFilePath(),
                            options: [.atomic, .completeFileProtection])
            logger.debug("Successfully wrote key string to disk.")
        } catch {
            logger.error("Unable to write key string to disk. error: \(error, privacy: .public)")
        }
    }
    
    private static func getFilePath() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("nostr-key")
    }
}

class RelayListManager {
    
}

extension Array where Element == NostrEvent {
    
    ///Removes duplicates from input list by comparing `id`
    func deduplicated() -> [NostrEvent] {
        
        var seenIDs = Set<String>()
        let result = filter { seenIDs.insert($0.id).inserted }
        
        return result
    }
    
    ///Sorts the array of NostrEvents by their unix timestamp and returns the latest
    func latest() -> NostrEvent? {
        var input = self
        input.sort { $0.createdAt > $1.createdAt }
        return input.first
    }
}

extension Array where Element == Message {
    func uniqueSenders() -> [Profile] {
        let uniqueSenders = Set(self.map({ $0.senderPubkey }))
        var profiles: [Profile] = []

        for sender in uniqueSenders {
            guard let pubkey = PublicKey(hex: sender) else {
                logger.warning(".uniqueSenders: could not turn hex public key into object")
                continue
            }
            profiles.append(Profile(pubkey: pubkey.hex, npub: pubkey.npub))
        }

        return profiles
    }
}
