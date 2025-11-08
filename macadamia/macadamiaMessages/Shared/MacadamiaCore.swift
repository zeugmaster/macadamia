import Foundation
import SwiftData
import CashuSwift
import OSLog

// MARK: - Shared Logger
let coreLogger = Logger(subsystem: "macadamia Core", category: "Shared")

// MARK: - Essential Error Types
enum MacadamiaCoreError: Error, LocalizedError {
    case insufficientFunds
    case mintNotFound
    case tokenGenerationFailed
    case invalidAmount
    case databaseError(String)
    
    var errorDescription: String? {
        switch self {
        case .insufficientFunds:
            return "Insufficient funds"
        case .mintNotFound:
            return "Mint not found"
        case .tokenGenerationFailed:
            return "Failed to generate token"
        case .invalidAmount:
            return "Invalid amount"
        case .databaseError(let message):
            return "Database error: \(message)"
        }
    }
}

// MARK: - Core Wallet Operations
extension AppSchemaV1.Wallet {
    /// Get total balance across all mints
    func totalBalance() -> Int {
        return mints.filter { !$0.hidden }.reduce(0) { sum, mint in
            sum + (mint.proofs?.filter { $0.state == .valid }.sum ?? 0)
        }
    }
    
    /// Get available mints for sending
    var availableMints: [Mint] {
        return mints.filter { !$0.hidden && !($0.proofs?.isEmpty ?? true) }
    }
}

// MARK: - Core Mint Operations  
extension AppSchemaV1.Mint {
    /// Get balance for this specific mint
    func balance() -> Int {
        return proofs?.filter { $0.state == .valid }.sum ?? 0
    }
    
    /// Check if mint has sufficient balance for amount
    func hasSufficientBalance(for amount: Int) -> Bool {
        return balance() >= amount
    }
}

// MARK: - Array Extensions
extension Array where Element == AppSchemaV1.Proof {
    var sum: Int {
        return self.reduce(0) { $0 + $1.amount }
    }
}

// MARK: - Simplified Alert Structure
struct SimpleAlert {
    let title: String
    let message: String
    
    init(title: String, message: String) {
        self.title = title
        self.message = message
    }
    
    init(error: Error) {
        self.title = "Error"
        self.message = error.localizedDescription
    }
}
