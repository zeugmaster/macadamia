//
//  data.swift
//  macadamia-cli
//
//  Created by zeugmaster on 14.11.23.
//

import OSLog
import Foundation

fileprivate var logger = Logger(subsystem: "zeugmaster.macadamia", category: "database")

//enum DatabaseError: Error {
//    case fileReadError
//    case filePathError
//}

public class Database: Codable, CustomStringConvertible {
    var proofs:[Proof]
    var pendingProofs:[Proof]
    var mints:[Mint]
    
    var transactions:[Transaction]
    
    var mnemonic:String?
    var seed:String?
    
//    private var loaded = false
    
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
    
    public var description: String {
        "Proofs: \(proofs.count), Mints: \(mints.count), Transactions:\(transactions.count), Seed is \(seed != nil ? "SET" : "NOT SET")"
    }
    
    private static func getFilePath() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("Database.json")
    }
    
    static func loadFromFile() -> Database {
        if FileManager.default.fileExists(atPath: Database.getFilePath().path()) {
            do {
                let data = try Data(contentsOf: Database.getFilePath())
                let db = try JSONDecoder().decode(Database.self, from: data)
                return db
            } catch {
                // if the file is there but could not be read (big yikes) do not return a new empty db,
                // because it will be saved and override the old, potentially valuable db
                //FIXME: this needs to be completely reworked to NOT return a fresh db or at least back up the old
                logger.error("loadFromFile() could not read database file, altough it is present")
                return Database()
            }
        } else {
            // if there is no database file present we create an empty one and return it
            return Database()
        }
    }
    
    func saveToFile() {
        let encoder = JSONEncoder()
        do {
//            guard loaded else {
//                logger.warning("Trying to save database to file before ever having loaded from file, saving aborted")
//                return
//            }
            guard (!proofs.isEmpty && !mints.isEmpty && !transactions.isEmpty) else {
                logger.warning("writing a db without proofs or mints or transaction is sus af, returning")
                return
            }
            encoder.outputFormatting = .prettyPrinted
            logger.debug("Database before saving: \(self)")
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
