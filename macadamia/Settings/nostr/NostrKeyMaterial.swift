//
//  NostrKeyMaterial.swift
//  macadamia
//
//  Helpers for the raw hex key material stored in NostrKeypair rows.
//  Lives outside PersistentModelV1 because the model file is compiled into
//  the messages extension, which does not link NostrSDK.
//

import Foundation
import NostrSDK

enum NostrKeyMaterial {

    /// Parses a private key in nsec1… bech32 or 64-character hex form.
    static func parseKeypair(_ keyString: String) -> Keypair? {
        let normalized = keyString.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.lowercased().hasPrefix("nsec") {
            return Keypair(nsec: normalized)
        } else {
            return Keypair(hex: normalized)
        }
    }

    /// Encodes an nprofile identifier from a hex public key and relay hints.
    static func nprofile(publicKeyHex: String, relays: [String]) throws -> String {
        struct MetadataEncoder: MetadataCoding {}
        let metadata = Metadata(pubkey: publicKeyHex, relays: relays)
        return try MetadataEncoder().encodedIdentifier(with: metadata, identifierType: .profile)
    }

    /// NIP-59 backdates a gift wrap's `created_at` by up to two days.
    static let giftWrapTimestampJitter: TimeInterval = 2 * 24 * 60 * 60

    /// Builds the kind-1059 subscription filter for a set of active receive keys,
    /// or nil when there is nothing to listen for. While a legacy (keychain-imported)
    /// key is active, `since` is omitted because its message history predates the
    /// import date.
    static func giftWrapFilter(activePubkeys: [String],
                               earliestCreation: Date?,
                               containsLegacy: Bool) -> Filter? {
        guard !activePubkeys.isEmpty else { return nil }

        var since: Int?
        if !containsLegacy, let earliestCreation {
            since = Int(earliestCreation.addingTimeInterval(-giftWrapTimestampJitter).timeIntervalSince1970)
        }

        return Filter(kinds: [EventKind.giftWrap.rawValue],
                      pubkeys: activePubkeys,
                      since: since)
    }
}
