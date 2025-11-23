import Foundation
import Security
import NostrSDK

enum NostrKeychainError: Error {
    case invalidData
    case unableToStore
    case unableToRetrieve
    case notFound
    case unableToDelete
    case duplicateItem
    
    var localizedDescription: String {
        switch self {
        case .invalidData:
            return "Invalid key data"
        case .unableToStore:
            return "Unable to store key in Keychain"
        case .unableToRetrieve:
            return "Unable to retrieve key from Keychain"
        case .notFound:
            return "Key not found in Keychain"
        case .unableToDelete:
            return "Unable to delete key from Keychain"
        case .duplicateItem:
            return "Key already exists in Keychain"
        }
    }
}

class NostrKeychain {
    
    private static let service = "com.macadamia.nostr"
    private static let account = "nsec"
    
    /// Saves the Nostr nsec key to Keychain (local only, not synced to iCloud)
    /// - Parameter nsec: The nsec key string to save
    /// - Throws: NostrKeychainError if the operation fails
    static func saveNsec(_ nsec: String) throws {
        guard let data = nsec.data(using: .utf8) else {
            throw NostrKeychainError.invalidData
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false // Explicitly disable iCloud sync
        ]
        
        // Try to add the item
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecDuplicateItem {
            // Item already exists, update it instead
            try updateNsec(nsec)
        } else if status != errSecSuccess {
            throw NostrKeychainError.unableToStore
        }
    }
    
    /// Updates an existing Nostr nsec key in Keychain
    /// - Parameter nsec: The new nsec key string
    /// - Throws: NostrKeychainError if the operation fails
    private static func updateNsec(_ nsec: String) throws {
        guard let data = nsec.data(using: .utf8) else {
            throw NostrKeychainError.invalidData
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]
        
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        
        if status != errSecSuccess {
            throw NostrKeychainError.unableToStore
        }
    }
    
    /// Retrieves the Nostr nsec key from Keychain
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
    
    /// Checks if an nsec key exists in Keychain
    /// - Returns: true if a key exists, false otherwise
    static func hasNsec() -> Bool {
        do {
            _ = try getNsec()
            return true
        } catch {
            return false
        }
    }
    
    /// Deletes the Nostr nsec key from Keychain
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
    
    /// Gets the npub (public key in bech32 format) derived from the stored nsec
    /// - Returns: The npub string
    /// - Throws: NostrKeychainError if the key cannot be retrieved or parsed
    static func getNpub() throws -> String {
        let nsec = try getNsec()
        let normalized = nsec.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let keypair: Keypair?
        if normalized.lowercased().hasPrefix("nsec") {
            keypair = Keypair(nsec: normalized)
        } else {
            keypair = Keypair(hex: normalized)
        }
        
        guard let keypair = keypair else {
            throw NostrKeychainError.invalidData
        }
        
        return keypair.publicKey.npub
    }
    
    /// Gets the nprofile (public key with relay hints in bech32 format) derived from the stored nsec
    /// - Parameter relays: Optional array of relay URLs to include in the nprofile
    /// - Returns: The nprofile string
    /// - Throws: NostrKeychainError if the key cannot be retrieved or parsed, or TLVCodingError if encoding fails
    static func getNprofile(relays: [String]? = nil) throws -> String {
        let nsec = try getNsec()
        let normalized = nsec.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let keypair: Keypair?
        if normalized.lowercased().hasPrefix("nsec") {
            keypair = Keypair(nsec: normalized)
        } else {
            keypair = Keypair(hex: normalized)
        }
        
        guard let keypair = keypair else {
            throw NostrKeychainError.invalidData
        }
        
        // Create metadata with pubkey and optional relays
        let metadata = Metadata(pubkey: keypair.publicKey.hex, relays: relays)
        
        // Encode as nprofile using MetadataCoding
        struct MetadataEncoder: MetadataCoding {}
        let encoder = MetadataEncoder()
        
        do {
            return try encoder.encodedIdentifier(with: metadata, identifierType: .profile)
        } catch {
            throw NostrKeychainError.invalidData
        }
    }
}

