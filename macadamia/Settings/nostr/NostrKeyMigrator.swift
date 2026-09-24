//
//  NostrKeyMigrator.swift
//  macadamia
//
//  One-time migration of the legacy single nostr key out of the iOS Keychain
//  and into the database. Keychain items survive app uninstalls, which is how
//  a fresh wallet used to resurrect an old key and its entire message history;
//  NostrKeypair rows share the wallet's lifecycle instead.
//

import Foundation
import SwiftData
import OSLog

fileprivate let migratorLogger = Logger(subsystem: "macadamia", category: "NostrKeyMigrator")

enum NostrKeyMigrator {

    /// Runs the one-time keychain-to-database migration. Idempotent by construction:
    /// the keychain item is the trigger, it is only deleted after the imported row is
    /// safely saved, and once it is gone every subsequent call is a no-op.
    @MainActor
    static func run(context: ModelContext) {
        guard let storedKey = try? NostrKeychain.getNsec() else {
            // Steady state after migration, and every fresh install going forward
            return
        }

        guard let keypair = NostrKeyMaterial.parseKeypair(storedKey) else {
            migratorLogger.warning("Legacy nostr key in keychain is unparseable, deleting it")
            deleteKeychainItem()
            return
        }

        let wallets = (try? context.fetch(FetchDescriptor<Wallet>())) ?? []

        guard !wallets.isEmpty else {
            // A keychain key without any wallet means this is a fresh install that
            // inherited a stale item from a previous installation. Importing it would
            // resurrect the old key's message history, so discard it instead.
            migratorLogger.info("Found stale legacy nostr key without a wallet (fresh install), deleting it without import")
            deleteKeychainItem()
            return
        }

        let publicKeyHex = keypair.publicKey.hex
        let descriptor = FetchDescriptor<NostrKeypair>(predicate: #Predicate<NostrKeypair> { $0.publicKeyHex == publicKeyHex })
        let alreadyImported = (try? context.fetch(descriptor).first) != nil

        if !alreadyImported {
            let wallet = wallets.first(where: { $0.active }) ?? wallets.first
            // dateCreated defaults to now, giving outstanding payment requests that
            // embed this key another full activity window after the update
            let row = NostrKeypair(privateKeyHex: keypair.privateKey.hex,
                                   publicKeyHex: publicKeyHex,
                                   paymentId: nil,
                                   isLegacy: true,
                                   wallet: wallet)
            context.insert(row)

            do {
                try context.save()
                migratorLogger.info("Imported legacy nostr key into the database")
            } catch {
                // Keep the keychain item so the next launch retries the import
                migratorLogger.error("Failed to save imported legacy nostr key, will retry on next launch: \(error)")
                context.delete(row)
                return
            }
        }

        // Only reached after the key is safely in the database (or was already there
        // from a previous partial run). Deleting the item is what makes this migration
        // one-time and stops the key from outliving the app.
        deleteKeychainItem()
    }

    private static func deleteKeychainItem() {
        do {
            try NostrKeychain.deleteNsec()
            migratorLogger.info("Deleted legacy nostr key from keychain")
        } catch {
            migratorLogger.error("Failed to delete legacy nostr key from keychain: \(error)")
        }
    }
}
