import Foundation
import OSLog

fileprivate let cacheLogger = Logger(subsystem: "macadamia", category: "NostrCache")

/// A file-based cache manager for Nostr data using JSON serialization
/// Simplified for wallet-specific key management
class NostrCache {
    static let shared = NostrCache()
    
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    
    private init() {
        // Use app group container if available, otherwise use default
        let appGroupID = "group.com.cypherbase.macadamia"
        
        if let groupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            cacheDirectory = groupURL.appendingPathComponent("NostrCache")
        } else {
            // Fallback to app's caches directory
            let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            cacheDirectory = cachesURL.appendingPathComponent("NostrCache")
        }
        
        // Create cache directory if it doesn't exist
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        
        cacheLogger.info("NostrCache initialized at: \(self.cacheDirectory.path)")
    }
    
    // MARK: - File URLs
    
    private var currentUserPubkeyFileURL: URL {
        cacheDirectory.appendingPathComponent("current_user.txt")
    }
    
    // MARK: - Current User Tracking
    
    /// Get the cached current user pubkey
    func getCurrentUserPubkey() -> String? {
        guard let data = try? Data(contentsOf: currentUserPubkeyFileURL),
              let pubkey = String(data: data, encoding: .utf8) else {
            return nil
        }
        return pubkey
    }
    
    /// Set the current user pubkey
    func setCurrentUserPubkey(_ pubkey: String) {
        do {
            try pubkey.data(using: .utf8)?.write(to: currentUserPubkeyFileURL)
            cacheLogger.info("Saved current user pubkey: \(pubkey.prefix(8))...")
        } catch {
            cacheLogger.error("Failed to save current user pubkey: \(error.localizedDescription)")
        }
    }
    
    /// Check if the current user has changed and clear cache if so
    func checkAndClearIfUserChanged(currentPubkey: String) {
        if let cachedPubkey = getCurrentUserPubkey(), cachedPubkey != currentPubkey {
            cacheLogger.info("User changed from \(cachedPubkey.prefix(8))... to \(currentPubkey.prefix(8))..., clearing cache")
            clearAll()
        }
        setCurrentUserPubkey(currentPubkey)
    }
    
    // MARK: - Clear Cache
    
    func clearAll() {
        do {
            // Remove all cache files
            if fileManager.fileExists(atPath: currentUserPubkeyFileURL.path) {
                try fileManager.removeItem(at: currentUserPubkeyFileURL)
                cacheLogger.info("Cleared current user cache")
            }
            
            cacheLogger.info("All Nostr cache cleared")
        } catch {
            cacheLogger.error("Failed to clear cache: \(error.localizedDescription)")
        }
    }
}
