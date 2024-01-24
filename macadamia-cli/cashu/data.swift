//
//  data.swift
//  macadamia-cli
//
//  Created by zeugmaster on 14.11.23.
//

import OSLog
import Foundation

fileprivate var logger = Logger(subsystem: "zeugmaster.macadamia", category: "database")

public class Database: Codable {
    var proofs:[Proof]
    var pendingProofs:[Proof]
    var mints:[Mint]
    
    var transactions:[Transaction]
    
    var mnemonic:String?
    var seed:String?
    
    private init(proofs: [Proof] = [], 
         pendingProofs: [Proof] = [],
         transactions:[Transaction] = [],
         mints: [Mint] = [],
         mnemonic: String? = nil) {
        
        self.proofs = proofs
        self.pendingProofs = pendingProofs
        self.transactions = transactions
        self.mints = mints
        self.mnemonic = mnemonic
    }
    
    private static func getFilePath() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("Database.json")
    }
    
    static func loadFromFile() -> Database {
        do {
            let data = try Data(contentsOf: Database.getFilePath())
            let db = try JSONDecoder().decode(Database.self, from: data)
            return db
        } catch {
            return Database()
        }
    }
    
    func saveToFile() {
        let encoder = JSONEncoder()
        do {
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(self)
            try data.write(to: Database.getFilePath())
            logger.debug("Saved wallet database to file.")
        } catch {
            print("whoops, failed to write db to file")
        }
    }
    
    ///Removes all proofs, pass phrase, seed from database except for the list of known mints
    func reset() {
        logger.debug("Resetting database...")
        proofs = []
        pendingProofs = []
        mnemonic = nil
        seed = nil
        transactions = []
        saveToFile()
    }
    
    func addProofsToValid(proofs:[Proof]) {
        
    }
    
    func retrieveProofs(from mint: Mint, amount: Int?) throws -> (proofs: [Proof], sum: Int) {
        // Load all mint keysets
        var sum = 0
        var collected = [Proof]()
        for proof in self.proofs {
            for ks in mint.allKeysets {
                if ks.id == proof.id {
                    collected.append(proof)
                    sum += proof.amount
                    break // No need to check for the other keyset_ids
                }
            }
            // Check if the sum meets the required amount if amount is not nil
            if let amount = amount, sum >= amount {
                logger.debug("Copied proofs from valid: \(collected, privacy: .public)")
                return (collected, sum)
            }
        }
        // If amount is nil, return all collected proofs
        if amount == nil {
            return (collected, sum)
        }
        // If the function hasn't returned yet, it means the required amount was not met
        throw WalletError.insufficientFunds(mintURL: mint.url.absoluteString)
    }

    func removeProofsFromValid(proofsToRemove:[Proof]) {
        logger.debug("Removing proofs from valid: \(proofsToRemove, privacy: .public)")
        let new = proofs.filter { item1 in
                !proofsToRemove.contains { item2 in
                item1 == item2
            }
        }
        self.proofs = new
    }
    
    func mintForKeysetID(id:String) -> Mint? {
        if let foundMint = self.mints.first(where: { mint in
            mint.allKeysets.contains(where: { keyset in
                keyset.id == id
            })
        }) {
            return foundMint
        } else {
            return nil
        }
    }
}
