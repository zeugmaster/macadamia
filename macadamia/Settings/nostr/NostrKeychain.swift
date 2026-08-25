//
//  NostrKeychain.swift
//  macadamia
//
//  Read/delete access to the legacy single-key keychain storage. Kept only for
//  NostrKeyMigrator's one-time import: keychain items survive app uninstalls, so
//  receive keys now live in the database instead. No new keys are ever written here.
//

import Foundation
import Security

enum NostrKeychainError: Error {
    case invalidData
    case unableToRetrieve
    case notFound
    case unableToDelete

    var localizedDescription: String {
        switch self {
        case .invalidData:
            return "Invalid key data"
        case .unableToRetrieve:
            return "Unable to retrieve key from Keychain"
        case .notFound:
            return "Key not found in Keychain"
        case .unableToDelete:
            return "Unable to delete key from Keychain"
        }
    }
}

class NostrKeychain {

    private static let service = "com.macadamia.nostr"
    private static let account = "nsec"

    /// Retrieves the legacy Nostr nsec key from Keychain
    /// - Returns: The nsec key string if found
    /// - Throws: NostrKeychainError if the key is not found or retrieval fails
    static func getNsec() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            throw NostrKeychainError.notFound
        } else if status != errSecSuccess {
            throw NostrKeychainError.unableToRetrieve
        }

        guard let data = result as? Data,
              let nsec = String(data: data, encoding: .utf8) else {
            throw NostrKeychainError.invalidData
        }

        return nsec
    }

    /// Checks if a legacy nsec key exists in Keychain
    /// - Returns: true if a key exists, false otherwise
    static func hasNsec() -> Bool {
        do {
            _ = try getNsec()
            return true
        } catch {
            return false
        }
    }

    /// Deletes the legacy Nostr nsec key from Keychain
    /// - Throws: NostrKeychainError if deletion fails
    static func deleteNsec() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let status = SecItemDelete(query as CFDictionary)

        if status != errSecSuccess && status != errSecItemNotFound {
            throw NostrKeychainError.unableToDelete
        }
    }
}
