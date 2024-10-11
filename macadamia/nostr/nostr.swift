//
//  nostr.swift
//  nostr-test
//
//  Created by zeugmaster on 21.12.23.
//

import Combine
import NostrSDK
import OSLog
import SwiftUI

private var logger = Logger(subsystem: "zeugmaster.macadamia", category: "nostr")

class Profile: Equatable, CustomStringConvertible, Codable {
    var description: String {
        let description = "\(npub.prefix(12)) name: \(name ?? "nil")"
        return description
    }

    static func == (lhs: Profile, rhs: Profile) -> Bool {
        lhs.pubkey == rhs.pubkey
    }

    let pubkey: String
    let npub: String
    var name: String?
    var pictureURL: URL?

    var tokenMessages: [String]?

    init(pubkey: String, npub: String, name: String? = nil, pictureURL: URL? = nil, tokenMessages: [String]? = nil) {
        self.pubkey = pubkey
        self.npub = npub
        self.name = name
        self.pictureURL = pictureURL
        self.tokenMessages = tokenMessages
    }
}

class Message {
    let senderPubkey: String
    var decryptedContent: String

    init(senderPubkey: String, decryptedContent: String) {
        self.senderPubkey = senderPubkey
        self.decryptedContent = decryptedContent
    }
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

class NostrService: EventCreating {
    static let shared = NostrService()

    private var eventsCancellable: AnyCancellable?
    private var stateCancellable: AnyCancellable?
    private var relayError: String?
    var state: Relay.State = .notConnected

    var relays = [Relay]()
    var relayStates = [String: Relay.State]()

    // both should only be initialzed once to prevent unexpected behaviour and conflicting states
    private var keyManager = KeyManager()
    var dataManager = NostrDataManager()

    // MARK: - Key handling

    func setPrivateKey(privateKey: String) throws {
        try keyManager.setPrivateKey(privateKey: privateKey)
    }

    // MARK: - Initializer

    private init() {
        logger.debug("Initializing ContactService instance")

        do {
            relays = try dataManager.relayURLlist.map { urlString in
                // TODO: check for proper URL initialization
                try Relay(url: URL(string: urlString)!)
            }
        } catch {}
    }

    /// Provides the user profile either from saved keypair or cache or nil if none are set
    var userProfile: Profile? {
        if dataManager.userProfile != nil {
            return dataManager.userProfile
        } else if let pubkey = keyManager.keypair?.publicKey {
            return Profile(pubkey: pubkey.hex, npub: pubkey.npub)
        } else {
            return nil
        }
    }

    /// Try to establish a websocket connection to relay
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

    var connectedRelays: [Relay] {
        return relays.filter { $0.state == Relay.State.connected }
    }

    /// Fetch contact list events. Returns cleaned list of `[Profile]`
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

        // cast generic NostrEvent as ContactListEvent
        guard let followListEvent = latest as? FollowListEvent else {
            let message = "Could not cast list of NostrEvent to ContactListEvent. Events: "
            logger.error("\(message)\(String(describing: events), privacy: .public)")
            throw ContactServiceError.relayQueryError
        }

        // followlist also contains duplicates and self-follow
        // which need to be removed
        // TODO: ensure order is kept when doing Array(Set(x))
        var contactPubkeys = Array(Set(followListEvent.followedPubkeys))
        contactPubkeys.removeAll(where: { $0 == keyManager.keypair?.publicKey.hex })

        // returns the array of pubkeys and tries to also supply public keys as npub
        return contactPubkeys.map { pubkey in
            guard let pk = PublicKey(hex: pubkey) else {
                logger.warning("Could not create PublicKey object from hex: \(pubkey)")
                return Profile(pubkey: pubkey, npub: "")
            }
            return Profile(pubkey: pk.hex, npub: pk.npub)
        }
    }

    func loadInfo(for profiles: [Profile], of user: Profile? = nil) async throws {
        guard keyManager.keypair?.publicKey.hex != nil else {
            throw ContactServiceError.noPrivateKeyError
        }

        if profiles.isEmpty {
            logger.warning("loadInfo: input array was emtpy, returning empty")
        }

        // create an array of all the pubkeys so we can query the relays all at once
        var pubkeys = profiles.map { $0.pubkey }
        if let user = user {
            pubkeys.append(user.pubkey)
        }

        // kind 0 for profile metadata
        let filter = Filter(authors: pubkeys, kinds: [0])
        let events = try await loadEventsWithFilter(filter: filter, from: connectedRelays)

        guard let unique = events.deduplicated() as? [SetMetadataEvent] else {
            let message = "Could not cast list of NostrEvent to ContactListEvent. Events: "
            logger.error("\(message)\(String(describing: events), privacy: .public)")
            throw ContactServiceError.relayQueryError
        }

        // TODO: check for outdated events for the same user
        for profile in profiles {
            let pe = unique.first(where: { $0.pubkey == profile.pubkey })
            profile.pictureURL = pe?.userMetadata?.pictureURL
            if let name = pe?.userMetadata?.name, name.count > 0 {
                profile.name = name
            }
        }

        if let user = user {
            let upe = unique.first(where: { $0.pubkey == user.pubkey })
            user.pictureURL = upe?.userMetadata?.pictureURL
            if let name = upe?.userMetadata?.name, name.count > 0 {
                user.name = name
            }
        }
    }

    func checkInbox() async throws -> [Message] {
        guard keyManager.keypair?.publicKey.hex != nil else {
            throw ContactServiceError.noPrivateKeyError
        }

        // loads all message events adressed to OUR  public key (incoming messages)
        let filter = Filter(kinds: [4], pubkeys: [keyManager.keypair!.publicKey.hex])

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

    /// `async` call to to load all events from multiple relays with a specified filter
    /// Will likely contain duplicates.
    private func loadEventsWithFilter(filter: Filter,
                                      from relays: [Relay]) async throws -> [NostrEvent]
    {
        return try await withCheckedThrowingContinuation { continuation in
            loadEventsWithFilter(filter: filter, from: relays) { completion in
                switch completion {
                case let .success(events):
                    continuation.resume(returning: events)
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /* potential solution for multi relay query
     TODO: make sure relays actually are connected */
    /// will produce duplicate entries
    private func loadEventsWithFilter(filter: Filter,
                                      from relays: [Relay],
                                      completion: @escaping (Result<[NostrEvent], Error>) -> Void)
    {
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
                    .sink(receiveCompletion: { completionResult in
                              switch completionResult {
                              case let .failure(error):
                                  completion(.failure(error))
                                  group.leave()
                              case .finished:
                                  group.leave()
                              }
                          },
                          receiveValue: { event in
                              events.insert(event, at: 0)
                          })
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

    func sendMessage(to contact: Profile, content: String) throws {
        guard keyManager.keypair != nil else {
            throw ContactServiceError.noPrivateKeyError
        }
        guard let pubkey = PublicKey(hex: contact.pubkey) else {
            throw ContactServiceError.invalidKeyError
        }

        let message = try directMessage(withContent: content,
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
    private var privateKeyHexString: String?

    private var privateKey: String? {
        set {
            // set and write to file
            privateKeyHexString = newValue
            writeKeyStringToDisk(keyString: privateKeyHexString!)
        }
        get {
            // if nil check disk, if unsuccessful return nil
            if privateKeyHexString == nil {
                let saved = keyStringFromDisk()
                privateKeyHexString = saved
                return saved
            } else {
                return privateKeyHexString
            }
        }
    }

    /// Takes a nostr private key either as HEX or bech32 with leading `nsec`
    func setPrivateKey(privateKey: String) throws {
        let pk: PrivateKey?
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

    /// Return nil if keypair has not been set through `setPrivateKey` and not an disk
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

    private func writeKeyStringToDisk(keyString: String) {
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

class NostrDataManager: Codable {
    private var _relayURLlist = [String]()
    private var _userProfile: Profile?

    private var defaultRelaysURLs = ["wss://relay.damus.io",
                                     "wss://nostr.wine",
                                     "wss://purplepag.es",
                                     "wss://nos.lol",
                                     "wss://relay.snort.social"]

    init() {
        // load from file
        guard let ndm = readDataFromFile() else {
            // use init values

            _relayURLlist = defaultRelaysURLs
            _userProfile = nil
            return
        }

        _relayURLlist = ndm._relayURLlist
        _userProfile = ndm.userProfile
    }

    var relayURLlist: [String] {
        return _relayURLlist
    }

    var userProfile: Profile? {
        return _userProfile
    }

    func addRelay(with urlString: String) {
        _relayURLlist.append(urlString)
        saveDataToFile()
    }

    func removeRelay(with urlString: String) {
        _relayURLlist.removeAll(where: { $0 == urlString })
        saveDataToFile()
    }

    func updateUserProfile(with profile: Profile) {
        _userProfile = profile
        saveDataToFile()
    }

    func resetUserProfile() {
        _userProfile = nil
        saveDataToFile()
    }

    func resetAll() {
        _relayURLlist = defaultRelaysURLs
        _userProfile = nil

        do {
            try FileManager.default.removeItem(at: filePath)
        } catch {
            logger.warning("""
             Filemanager could not remove file from path
             \(filePath.absoluteString). error: \(error)
            """)
        }
    }

    private func saveDataToFile() {
        do {
            let data = try JSONEncoder().encode(self)
            try data.write(to: filePath)
            logger.debug("Successfully wrote nostr date to disk.")
        } catch {
            logger.error("Unable to write nostr data to disk. error: \(error, privacy: .public)")
        }
    }

    private func readDataFromFile() -> NostrDataManager? {
        do {
            let data = try Data(contentsOf: filePath)
            logger.debug("Successfully read nostr data from disk. Path: \(filePath.absoluteString)")
            let ndm = try JSONDecoder().decode(NostrDataManager.self, from: data)
            return ndm
        } catch {
            logger.warning("Could not read nostr data from disk. (might not be set yet. \(error)")
            return nil
        }
    }

    private var filePath: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("nostr-data.json")
    }
}

extension Array where Element == NostrEvent {
    /// Removes duplicates from input list by comparing `id`
    func deduplicated() -> [NostrEvent] {
        var seenIDs = Set<String>()
        let result = filter { seenIDs.insert($0.id).inserted }

        return result
    }

    /// Sorts the array of NostrEvents by their unix timestamp and returns the latest
    func latest() -> NostrEvent? {
        var input = self
        input.sort { $0.createdAt > $1.createdAt }
        return input.first
    }
}

extension Array where Element == Message {
    func uniqueSenders() -> [Profile] {
        let uniqueSenders = Set(map { $0.senderPubkey })
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
