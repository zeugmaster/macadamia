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
extension Mint {
    /// Get balance for this specific mint
    func balance() -> Int {
        return proofs?.filter { $0.state == .valid }.sum ?? 0
    }
    
    /// Check if mint has sufficient balance for amount
    func hasSufficientBalance(for amount: Int) -> Bool {
        return balance() >= amount
    }
}

// MARK: - Core Token Generation
extension Mint {
    /// Simplified token generation for extension use
    @MainActor
    func generateToken(amount: Int, memo: String, allProofs: [Proof], completion: @escaping (Result<String, Error>) -> Void) {
        
        guard let wallet = self.wallet else {
            completion(.failure(MacadamiaCoreError.databaseError("Mint has no associated wallet")))
            return
        }
        
        // Select proofs
        guard let selection = self.select(allProofs: allProofs, amount: amount, unit: .sat) else {
            completion(.failure(MacadamiaCoreError.insufficientFunds))
            return
        }
        
        // Generate token using existing send operation
        self.send(proofs: selection.selected, targetAmount: amount, memo: memo) { result in
            switch result {
            case .success(let (token, _, _)):
                // Serialize token to string
                do {
                    let tokenString = try token.serialize(to: .V4)
                    completion(.success(tokenString))
                } catch {
                    completion(.failure(MacadamiaCoreError.tokenGenerationFailed))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}

// MARK: - Array Extensions
extension Array where Element == Proof {
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
