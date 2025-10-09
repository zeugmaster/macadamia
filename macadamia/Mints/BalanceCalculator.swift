//
//  BalanceCalculator.swift
//  macadamia
//
//  Generic balance distribution calculator
//

import Foundation

struct BalanceCalculator<ID: Hashable> {
    
    struct Transaction {
        let from: ID
        let to: ID
        let amount: Int
    }
    
    /// Calculates the optimal set of transactions to balance accounts according to target deltas
    /// - Parameter deltas: Dictionary mapping account IDs to their delta (positive = needs to receive, negative = needs to send)
    /// - Returns: Array of transactions that will balance all accounts
    static func calculateTransactions(for deltas: Dictionary<ID, Int>) -> [Transaction] {
        var transactions: [Transaction] = []
        
        // Separate accounts into sources (negative delta - need to send) and targets (positive delta - need to receive)
        var sources = deltas.compactMap { (id, delta) -> (id: ID, available: Int)? in
            delta < 0 ? (id: id, available: -delta) : nil
        }
        var targets = deltas.compactMap { (id, delta) -> (id: ID, needed: Int)? in
            delta > 0 ? (id: id, needed: delta) : nil
        }
        
        // Sort sources and targets by amount (descending) for better matching
        sources.sort { $0.available > $1.available }
        targets.sort { $0.needed > $1.needed }
        
        var sourceIndex = 0
        var targetIndex = 0
        
        while sourceIndex < sources.count && targetIndex < targets.count {
            let source = sources[sourceIndex]
            let target = targets[targetIndex]
            
            // Calculate transfer amount
            let amountToTransfer = min(source.available, target.needed)
            
            if amountToTransfer > 0 {
                // Create transaction
                transactions.append(Transaction(
                    from: source.id,
                    to: target.id,
                    amount: amountToTransfer
                ))
                
                // Update remaining amounts
                sources[sourceIndex].available -= amountToTransfer
                targets[targetIndex].needed -= amountToTransfer
                
                // Move to next source if current is exhausted
                if sources[sourceIndex].available == 0 {
                    sourceIndex += 1
                }
                
                // Move to next target if current is satisfied
                if targets[targetIndex].needed == 0 {
                    targetIndex += 1
                }
            }
        }
        
        return transactions
    }
}

