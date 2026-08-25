@testable import macadamia
import XCTest
import SwiftData
import Security
import NostrSDK
import CashuSwift

/// Tests for the per-request nostr receive keys: schema migration, the one-time
/// keychain migrator, filter construction, nprofile relay embedding, multi-key
/// unseal routing and the persisted message ledger.
final class NostrKeyTests: XCTestCase {

    // MARK: - Helpers

    private static let legacyService = "com.macadamia.nostr"
    private static let legacyAccount = "nsec"

    /// Mirrors the removed NostrKeychain.saveNsec so tests can plant a legacy item.
    private func plantLegacyKeychainItem(_ value: String) {
        removeLegacyKeychainItem()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.legacyService,
            kSecAttrAccount as String: Self.legacyAccount,
            kSecValueData as String: Data(value.utf8)
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        XCTAssertEqual(status, errSecSuccess, "planting the legacy keychain item must succeed")
    }

    private func removeLegacyKeychainItem() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.legacyService,
            kSecAttrAccount as String: Self.legacyAccount
        ]
        SecItemDelete(query as CFDictionary)
    }

    @MainActor
    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([Wallet.self, Proof.self, Mint.self, Event.self,
                             NostrKeypair.self, NostrMessage.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    // MARK: - Schema migration

    /// Writes a store shaped like the schema BEFORE NostrKeypair/NostrMessage existed
    /// (the current four models ARE that schema — they are unchanged), then opens it
    /// with all six models: the exact upgrade existing users perform. Must
    /// lightweight-migrate without a throw and keep legacy rows intact.
    @MainActor
    func testLightweightMigrationAddsNostrModels() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macadamia-nostrkey-migration-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
            }
        }

        // 1) Write the pre-change store using only the four existing models.
        do {
            let container = try ModelContainer(for: Wallet.self, Proof.self, Mint.self, Event.self,
                                               configurations: ModelConfiguration(url: storeURL))
            let context = ModelContext(container)
            let wallet = Wallet(mnemonic: "m", seed: "s")
            context.insert(wallet)
            let mint = Mint(url: URL(string: "http://localhost:3338")!, keysets: [])
            mint.wallet = wallet
            context.insert(mint)
            try context.save()
        }

        // 2) Open the SAME store with the full schema including the new models.
        do {
            let container = try ModelContainer(for: Wallet.self, Proof.self, Mint.self, Event.self,
                                               NostrKeypair.self, NostrMessage.self,
                                               configurations: ModelConfiguration(url: storeURL))
            let context = ModelContext(container)

            let wallet = try XCTUnwrap(try context.fetch(FetchDescriptor<Wallet>()).first)
            XCTAssertEqual(wallet.mnemonic, "m", "legacy rows must survive the migration")
            XCTAssertEqual(try context.fetch(FetchDescriptor<Mint>()).count, 1)
            XCTAssertTrue(try context.fetch(FetchDescriptor<NostrKeypair>()).isEmpty)

            // 3) The new models are usable in the migrated store.
            let keypair = NostrKeypair(privateKeyHex: String(repeating: "a", count: 64),
                                       publicKeyHex: String(repeating: "b", count: 64),
                                       paymentId: "req1",
                                       wallet: wallet)
            context.insert(keypair)
            context.insert(NostrMessage(messageID: "rumor-1", outcome: .redeemed, keypair: keypair))
            try context.save()
        }

        // 4) Reopen once more: rows and the raw-string-backed outcome must survive on disk.
        let container = try ModelContainer(for: Wallet.self, Proof.self, Mint.self, Event.self,
                                           NostrKeypair.self, NostrMessage.self,
                                           configurations: ModelConfiguration(url: storeURL))
        let context = ModelContext(container)

        let keypair = try XCTUnwrap(try context.fetch(FetchDescriptor<NostrKeypair>()).first)
        XCTAssertEqual(keypair.paymentId, "req1")
        XCTAssertFalse(keypair.isLegacy)
        XCTAssertNotNil(keypair.wallet)
        XCTAssertEqual(keypair.messages.count, 1)
        XCTAssertEqual(keypair.messages.first?.outcome, .redeemed)

        // Cascade: deleting the keypair removes its ledger rows.
        context.delete(keypair)
        try context.save()
        XCTAssertTrue(try context.fetch(FetchDescriptor<NostrMessage>()).isEmpty)
    }

    // MARK: - Keychain migrator

    @MainActor
    func testMigratorImportsLegacyKeyAndEmptiesKeychain() throws {
        defer { removeLegacyKeychainItem() }

        let legacyKeypair = try XCTUnwrap(Keypair())
        plantLegacyKeychainItem(legacyKeypair.privateKey.nsec)

        let context = try makeInMemoryContext()
        context.insert(Wallet(mnemonic: "m", seed: "s"))
        try context.save()

        NostrKeyMigrator.run(context: context)

        let imported = try XCTUnwrap(try context.fetch(FetchDescriptor<NostrKeypair>()).first)
        XCTAssertEqual(imported.privateKeyHex, legacyKeypair.privateKey.hex, "nsec must be normalized to hex")
        XCTAssertEqual(imported.publicKeyHex, legacyKeypair.publicKey.hex)
        XCTAssertTrue(imported.isLegacy)
        XCTAssertNil(imported.paymentId)
        XCTAssertNotNil(imported.wallet)
        XCTAssertTrue(imported.isActive, "the imported key gets a fresh activity window")
        XCTAssertFalse(NostrKeychain.hasNsec(), "the keychain item must be gone after a successful import")

        // Running again must be a no-op (this is what prevents repeated migrations).
        NostrKeyMigrator.run(context: context)
        XCTAssertEqual(try context.fetch(FetchDescriptor<NostrKeypair>()).count, 1)
    }

    @MainActor
    func testMigratorNormalizesHexFormatKey() throws {
        defer { removeLegacyKeychainItem() }

        let legacyKeypair = try XCTUnwrap(Keypair())
        plantLegacyKeychainItem(legacyKeypair.privateKey.hex) // stored as raw hex, not nsec

        let context = try makeInMemoryContext()
        context.insert(Wallet(mnemonic: "m", seed: "s"))
        try context.save()

        NostrKeyMigrator.run(context: context)

        let imported = try XCTUnwrap(try context.fetch(FetchDescriptor<NostrKeypair>()).first)
        XCTAssertEqual(imported.privateKeyHex, legacyKeypair.privateKey.hex)
        XCTAssertEqual(imported.publicKeyHex, legacyKeypair.publicKey.hex)
        XCTAssertFalse(NostrKeychain.hasNsec())
    }

    @MainActor
    func testMigratorDiscardsStaleKeyOnFreshInstall() throws {
        defer { removeLegacyKeychainItem() }

        let legacyKeypair = try XCTUnwrap(Keypair())
        plantLegacyKeychainItem(legacyKeypair.privateKey.nsec)

        // No wallet in the database: this is the reinstall-with-stale-keychain case.
        let context = try makeInMemoryContext()

        NostrKeyMigrator.run(context: context)

        XCTAssertTrue(try context.fetch(FetchDescriptor<NostrKeypair>()).isEmpty,
                      "a stale key from a previous install must not be imported into a fresh wallet")
        XCTAssertFalse(NostrKeychain.hasNsec(), "the stale item must be deleted so it cannot resurface")
    }

    @MainActor
    func testMigratorDeletesUnparseableKey() throws {
        defer { removeLegacyKeychainItem() }

        plantLegacyKeychainItem("not-a-key")

        let context = try makeInMemoryContext()
        context.insert(Wallet(mnemonic: "m", seed: "s"))
        try context.save()

        NostrKeyMigrator.run(context: context)

        XCTAssertTrue(try context.fetch(FetchDescriptor<NostrKeypair>()).isEmpty)
        XCTAssertFalse(NostrKeychain.hasNsec())
    }

    @MainActor
    func testMigratorIsNoOpWithoutKeychainItem() throws {
        removeLegacyKeychainItem()

        let context = try makeInMemoryContext()
        context.insert(Wallet(mnemonic: "m", seed: "s"))
        try context.save()

        NostrKeyMigrator.run(context: context)

        XCTAssertTrue(try context.fetch(FetchDescriptor<NostrKeypair>()).isEmpty)
    }

    // MARK: - Filter construction and key lifetime

    func testGiftWrapFilterConstruction() throws {
        XCTAssertNil(NostrKeyMaterial.giftWrapFilter(activePubkeys: [], earliestCreation: nil, containsLegacy: false),
                     "no keys means nothing to subscribe to")

        let pubkeyA = String(repeating: "a", count: 64)
        let pubkeyB = String(repeating: "b", count: 64)
        let earliest = Date(timeIntervalSince1970: 1_700_000_000)

        let filter = try XCTUnwrap(NostrKeyMaterial.giftWrapFilter(activePubkeys: [pubkeyA, pubkeyB],
                                                                   earliestCreation: earliest,
                                                                   containsLegacy: false))

        // Inspect through the Codable representation to avoid relying on property names.
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(filter)) as? [String: Any])
        XCTAssertEqual(json["kinds"] as? [Int], [1059])
        XCTAssertEqual(Set(json["#p"] as? [String] ?? []), Set([pubkeyA, pubkeyB]))
        XCTAssertEqual(json["since"] as? Int, 1_700_000_000 - 2 * 86400,
                       "since must back off by the NIP-59 timestamp jitter window")

        // A legacy key's history predates its import date, so since must be omitted.
        let legacyFilter = try XCTUnwrap(NostrKeyMaterial.giftWrapFilter(activePubkeys: [pubkeyA],
                                                                         earliestCreation: earliest,
                                                                         containsLegacy: true))
        let legacyJson = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacyFilter)) as? [String: Any])
        XCTAssertNil(legacyJson["since"])
    }

    @MainActor
    func testKeypairActiveLifetimeCutoff() throws {
        let context = try makeInMemoryContext()
        let key = NostrKeypair(privateKeyHex: String(repeating: "a", count: 64),
                               publicKeyHex: String(repeating: "b", count: 64),
                               paymentId: nil,
                               wallet: nil)
        context.insert(key)

        key.dateCreated = Date().addingTimeInterval(-89 * 86400)
        XCTAssertTrue(key.isActive)

        key.dateCreated = Date().addingTimeInterval(-91 * 86400)
        XCTAssertFalse(key.isActive)
    }

    // MARK: - nprofile relay embedding

    func testNprofileEmbedsGivenRelaysAndSurvivesNUT26Roundtrip() throws {
        struct Decoder: MetadataCoding {}

        let keypair = try XCTUnwrap(Keypair())
        let relays = ["wss://example-relay.test", "wss://second-relay.test"]

        let nprofile = try NostrKeyMaterial.nprofile(publicKeyHex: keypair.publicKey.hex, relays: relays)

        let metadata = try Decoder().decodedMetadata(from: nprofile)
        XCTAssertEqual(metadata.pubkey, keypair.publicKey.hex)
        XCTAssertEqual(metadata.relays ?? [], relays)
        for defaultRelay in defaultRelayURLs {
            XCTAssertFalse(metadata.relays?.contains(defaultRelay.absoluteString) ?? false,
                           "hardcoded default relays must not leak into the payment request")
        }

        // The nprofile must survive the creq encoding round trip.
        let request = CashuSwift.PaymentRequest(paymentId: "abc123",
                                                amount: 21,
                                                unit: "sat",
                                                singleUse: false,
                                                mints: nil,
                                                description: nil,
                                                transports: [CashuSwift.Transport(type: CashuSwift.Transport.TransportType.nostr,
                                                                                  target: nprofile)],
                                                lockingCondition: nil)
        let decodedRequest = try NUT26.decode(try NUT26.encode(request))
        let decodedTarget = try XCTUnwrap(decodedRequest.transports?.first?.target)
        let decodedMetadata = try Decoder().decodedMetadata(from: decodedTarget)
        XCTAssertEqual(decodedMetadata.pubkey, keypair.publicKey.hex)
        XCTAssertEqual(decodedMetadata.relays ?? [], relays)
    }

    // MARK: - Multi-key unseal routing

    func testGiftWrapRoutesToAddressedKeyOnly() throws {
        struct WrapFactory: EventCreating {}

        let keyA = try XCTUnwrap(Keypair())
        let keyB = try XCTUnwrap(Keypair())
        let sender = try XCTUnwrap(Keypair())
        let content = "routing test payload"

        let dmBuilder = DirectMessageEvent.Builder()
        dmBuilder.content(content)
        dmBuilder.appendTags(NostrSDK.Tag(name: TagName.pubkey.rawValue, value: keyB.publicKey.hex))
        let directMessage = dmBuilder.build(pubkey: sender.publicKey)

        let giftWrap = try WrapFactory().giftWrap(withDirectMessageEvent: directMessage,
                                                  toRecipient: keyB.publicKey,
                                                  signedBy: sender)

        // The "p" tag routing used by NostrService.handleIncomingEvent
        XCTAssertTrue(giftWrap.referencedPubkeys.contains(keyB.publicKey.hex))
        XCTAssertFalse(giftWrap.referencedPubkeys.contains(keyA.publicKey.hex))

        // Only the addressed key can unseal
        let rumor = try XCTUnwrap(try giftWrap.unsealedRumor(using: keyB.privateKey))
        XCTAssertEqual(rumor.content, content)
        XCTAssertEqual(rumor.pubkey, sender.publicKey.hex)
        XCTAssertNil(try? giftWrap.unsealedRumor(using: keyA.privateKey))
    }

    // MARK: - Message ledger

    @MainActor
    func testLedgerOutcomeSemanticsAndDedup() throws {
        let context = try makeInMemoryContext()

        XCTAssertTrue(NostrMessage.Outcome.redeemed.isTerminal)
        XCTAssertTrue(NostrMessage.Outcome.spent.isTerminal)
        XCTAssertFalse(NostrMessage.Outcome.unknownMint.isTerminal)
        XCTAssertFalse(NostrMessage.Outcome.failed.isTerminal)

        let keypair = NostrKeypair(privateKeyHex: String(repeating: "a", count: 64),
                                   publicKeyHex: String(repeating: "b", count: 64),
                                   paymentId: "req1",
                                   wallet: nil)
        context.insert(keypair)
        context.insert(NostrMessage(messageID: "rumor-1", outcome: .unknownMint, keypair: keypair))
        try context.save()

        // Retryable outcomes can be upgraded in place.
        let row = try XCTUnwrap(try context.fetch(FetchDescriptor<NostrMessage>()).first)
        row.outcome = .redeemed
        row.eventID = UUID()
        try context.save()
        XCTAssertEqual(keypair.messages.filter { $0.outcome == .redeemed }.count, 1)

        // The unique messageID upserts instead of duplicating.
        context.insert(NostrMessage(messageID: "rumor-1", outcome: .spent, keypair: keypair))
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<NostrMessage>()).count, 1)
    }
}
