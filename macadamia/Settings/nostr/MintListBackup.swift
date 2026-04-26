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
}

private struct MintListPayload: Codable {
    let mints: [String]
    let timestamp: Int
}

private struct Crypto: NIP44v2Encrypting {}

enum MintListBackup {

    private static let crypto = Crypto()

    // MARK: - Public Interface

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

        let pool = try RelayPool(relayURLs: Set(relayURLs))
        try await waitForConnection(pool: pool, timeout: 10)

        pool.publishEvent(event)
        backupLogger.info("Published mint list backup with \(mints.count) mint(s)")

        try await Task.sleep(for: .seconds(1))
        pool.disconnect()
    }

    @MainActor
    static func publishCurrentList(for wallet: Wallet) {
        let urls = wallet.mints
            .filter { $0.hidden == false }
            .sorted { ($0.userIndex ?? 0) < ($1.userIndex ?? 0) }
            .map(\.url)
        let seedHex = wallet.seed
        Task.detached {
            do {
                try await publish(mints: urls, seedHex: seedHex)
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
