import Foundation
import CryptoKit
import NostrSDK
import Combine
import OSLog

fileprivate let backupLogger = Logger(subsystem: "macadamia", category: "MintListBackup")

enum MintListBackupError: Error {
    case invalidSeed
    case keyDerivationFailed
    case encryptionFailed
    case noRelaysConnected
    case noBackupFound
    /// No relay acknowledged the event before the timeout.
    case notConfirmed
    /// Every relay that was asked rejected the event.
    case rejected(String)
}

private struct MintListPayload: Codable {
    let mints: [String]
    let timestamp: Int
}

private struct Crypto: NIP44v2Encrypting {}

// MARK: - Backup Status

/// Tracks when each wallet's mint list was last accepted by a relay and whether
/// a backup is currently in flight. Dates are kept in `UserDefaults`, keyed by
/// wallet ID, so this needs no schema change.
@MainActor
final class MintListBackupStatus: ObservableObject {

    static let shared = MintListBackupStatus()

    private static let defaultsKey = "mintListBackupDates"

    @Published private(set) var lastBackupDates: [UUID: Date]
    @Published private var inFlightCounts: [UUID: Int] = [:]

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.dictionary(forKey: Self.defaultsKey) as? [String: Double] ?? [:]
        var dates: [UUID: Date] = [:]
        for (key, timestamp) in stored {
            if let id = UUID(uuidString: key) {
                dates[id] = Date(timeIntervalSince1970: timestamp)
            }
        }
        self.lastBackupDates = dates
    }

    func lastBackup(for wallet: Wallet) -> Date? {
        lastBackupDates[wallet.walletID]
    }

    func isBackingUp(_ wallet: Wallet) -> Bool {
        (inFlightCounts[wallet.walletID] ?? 0) > 0
    }

    func recordSuccess(for walletID: UUID, at date: Date = Date()) {
        lastBackupDates[walletID] = date
        var stored: [String: Double] = [:]
        for (id, date) in lastBackupDates {
            stored[id.uuidString] = date.timeIntervalSince1970
        }
        defaults.set(stored, forKey: Self.defaultsKey)
    }

    fileprivate func beginBackup(for walletID: UUID) {
        inFlightCounts[walletID, default: 0] += 1
    }

    fileprivate func endBackup(for walletID: UUID) {
        let remaining = (inFlightCounts[walletID] ?? 1) - 1
        inFlightCounts[walletID] = remaining > 0 ? remaining : nil
    }
}

// MARK: - Publish Confirmation

/// Collects relay `OK` responses for one published event so the caller can tell
/// whether at least one relay actually stored it.
private final class PublishConfirmation: RelayDelegate, @unchecked Sendable {

    private let eventID: String
    private let lock = NSLock()
    private var accepted = false
    private var rejections: [String] = []

    init(eventID: String) {
        self.eventID = eventID
    }

    func relayStateDidChange(_ relay: Relay, state: Relay.State) {}

    func relay(_ relay: Relay, didReceive event: RelayEvent) {}

    func relay(_ relay: Relay, didReceive response: RelayResponse) {
        guard case .ok(let id, let success, let message) = response, id == eventID else { return }
        lock.withLock {
            if success {
                accepted = true
            } else {
                rejections.append(message.message.isEmpty ? "\(message.prefix)" : message.message)
            }
        }
    }

    /// Returns once any relay accepts the event. Throws if every relay that was
    /// asked rejected it, or if none confirmed within the timeout.
    func waitForAcceptance(from relayCount: Int, timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let (accepted, rejections) = lock.withLock { (self.accepted, self.rejections) }
            if accepted { return }
            if relayCount > 0 && rejections.count >= relayCount {
                throw MintListBackupError.rejected(rejections.first ?? "")
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        if let rejection = lock.withLock({ rejections.first }) {
            throw MintListBackupError.rejected(rejection)
        }
        throw MintListBackupError.notConfirmed
    }
}

// MARK: - Mint List Backup

enum MintListBackup {

    private static let crypto = Crypto()

    // MARK: - Public Interface

    /// Encrypts the mint list, publishes it and waits until at least one relay
    /// confirms it stored the event.
    static func publish(mints: [URL], seedHex: String) async throws {
        let keypair = try deriveKeypair(from: seedHex)

        let payload = MintListPayload(
            mints: mints.map(\.absoluteString),
            timestamp: Int(Date().timeIntervalSince1970)
        )
        let json = String(data: try JSONEncoder().encode(payload), encoding: .utf8)!

        let encrypted = try crypto.encrypt(
            plaintext: json,
            privateKeyA: keypair.privateKey,
            publicKeyB: keypair.publicKey
        )

        let event = try NostrEvent.Builder(kind: EventKind(rawValue: 30078))
            .content(encrypted)
            .appendTags(
                NostrSDK.Tag(name: .identifier, value: "mint-list"),
                NostrSDK.Tag(name: "client", value: "macadamia")
            )
            .build(signedBy: keypair)

        let confirmation = PublishConfirmation(eventID: event.id)
        let pool = try RelayPool(relayURLs: Set(relayURLs), delegate: confirmation)
        try await waitForConnection(pool: pool, timeout: 10)
        defer { pool.disconnect() }

        let connectedRelays = pool.relays.filter { $0.state == .connected }.count
        pool.publishEvent(event)
        try await confirmation.waitForAcceptance(from: connectedRelays, timeout: 5)
        backupLogger.info("Published mint list backup with \(mints.count) mint(s)")
    }

    /// Publishes the wallet's visible mints and records the time once a relay
    /// has confirmed the event. Throws if no relay accepted it.
    @MainActor
    static func backUp(_ wallet: Wallet) async throws {
        let urls = wallet.mints
            .filter { $0.hidden == false }
            .sorted { ($0.userIndex ?? 0) < ($1.userIndex ?? 0) }
            .map(\.url)
        let seedHex = wallet.seed
        let walletID = wallet.walletID
        let status = MintListBackupStatus.shared

        status.beginBackup(for: walletID)
        defer { status.endBackup(for: walletID) }

        try await publish(mints: urls, seedHex: seedHex)
        status.recordSuccess(for: walletID)
    }

    /// Fire-and-forget variant used after the mint list changes. Failures are
    /// only logged; the user can retry from the seed phrase screen.
    @MainActor
    static func publishCurrentList(for wallet: Wallet) {
        Task {
            do {
                try await backUp(wallet)
            } catch {
                backupLogger.warning("mint list backup publish failed silently: \(error)")
            }
        }
    }

    static func retrieve(seedHex: String) async throws -> [URL] {
        let keypair = try deriveKeypair(from: seedHex)

        let pool = try RelayPool(relayURLs: Set(relayURLs))
        try await waitForConnection(pool: pool, timeout: 10)

        guard let filter = Filter(
            authors: [keypair.publicKey.hex],
            kinds: [30078],
            tags: ["d": ["mint-list"]]
        ) else {
            pool.disconnect()
            throw MintListBackupError.keyDerivationFailed
        }

        let subscriptionId = pool.subscribe(with: filter)
        backupLogger.info("Subscribed to mint list backup events")

        var bestEvent: NostrEvent?
        let cancellable = pool.events.sink { relayEvent in
            guard relayEvent.subscriptionId == subscriptionId else { return }
            if bestEvent == nil || relayEvent.event.createdAt > bestEvent!.createdAt {
                bestEvent = relayEvent.event
            }
        }

        // Wait for events: up to 8s total, but exit early 2s after first event
        var firstEventAt: Date?
        for _ in 0..<16 { // 16 * 500ms = 8s max
            try await Task.sleep(for: .milliseconds(500))
            if bestEvent != nil && firstEventAt == nil {
                firstEventAt = Date()
            }
            if let t = firstEventAt, Date().timeIntervalSince(t) >= 2 {
                break
            }
        }

        cancellable.cancel()
        pool.closeSubscription(with: subscriptionId)
        pool.disconnect()

        guard let event = bestEvent else {
            throw MintListBackupError.noBackupFound
        }

        backupLogger.info("Found mint list backup event")

        let decrypted = try crypto.decrypt(
            payload: event.content,
            privateKeyA: keypair.privateKey,
            publicKeyB: keypair.publicKey
        )

        let payload = try JSONDecoder().decode(MintListPayload.self, from: Data(decrypted.utf8))
        return payload.mints.compactMap { URL(string: $0) }
    }

    // MARK: - Private Helpers

    private static func deriveKeypair(from seedHex: String) throws -> Keypair {
        guard let seedData = hexToData(seedHex), seedData.count == 64 else {
            throw MintListBackupError.invalidSeed
        }

        let separator = Data("cashu-mint-backup".utf8)
        let combined = seedData + separator
        let hash = SHA256.hash(data: combined)
        let privateKeyHex = hash.compactMap { String(format: "%02x", $0) }.joined()

        guard let keypair = Keypair(hex: privateKeyHex) else {
            throw MintListBackupError.keyDerivationFailed
        }

        return keypair
    }

    private static var relayURLs: [URL] {
        if let data = UserDefaults.standard.data(forKey: "savedURLs"),
           let urls = try? JSONDecoder().decode([URL].self, from: data) {
            return urls
        }
        return defaultRelayURLs
    }

    private static func waitForConnection(pool: RelayPool, timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if pool.relays.contains(where: { $0.state == .connected }) {
                return
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        pool.disconnect()
        throw MintListBackupError.noRelaysConnected
    }

    private static func hexToData(_ hex: String) -> Data? {
        guard hex.count.isMultiple(of: 2) else { return nil }
        let chars = Array(hex)
        var data = Data(capacity: hex.count / 2)
        for i in stride(from: 0, to: hex.count, by: 2) {
            guard let byte = UInt8(String(chars[i]) + String(chars[i + 1]), radix: 16) else {
                return nil
            }
            data.append(byte)
        }
        return data
    }
}
