//
//  data.swift
//  macadamia-cli
//
//  Created by Dario Lass on 14.11.23.
//

import Foundation

public class Database: Codable {
    
    var proofs:[Proof]
    var pendingProofs:[Proof]
    var mints:[Mint]
    var pendingOutputs:[Output]
    
    var mnemonic:String?
    var seed:String?
    var secretDerivationCounter:Int
    
    init(proofs: [Proof] = [], 
         pendingProofs: [Proof] = [],
         mints: [Mint] = [],
         pendingOutputs: [Output] = [],
         mnemonic: String? = nil,
         secretDerivationCounter:Int = 0) {
        
        self.proofs = proofs
        self.pendingProofs = pendingProofs
        self.mints = mints
        self.pendingOutputs = pendingOutputs
        self.mnemonic = mnemonic
        self.secretDerivationCounter = secretDerivationCounter
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
        } catch {
            print("whoops, failed to write db to file")
        }
    }
    
    func retrieveProofs(from mint:Mint, amount:Int) throws -> (proofs:[Proof], sum:Int) {
        //load all mint keysets
        print("looking for proofs from \(mint.url) with total amount: \(amount)")
        var sum = 0
        var collected = [Proof]()
        for proof in self.proofs {
            for ks in mint.allKeysets! {
                if ks.id == proof.id {
                    collected.append(proof)
                    sum += proof.amount
                    break // no need to check for the other keyset_ids
                }
            }
            if sum >= amount {
                return (collected, sum)
            }
        }
        throw Wallet.WalletError.insufficientFunds(mint: mint)
    }
    
    func removeProofsFromValid(proofsToRemove:[Proof]) {
        let new = proofs.filter { item1 in
                !proofsToRemove.contains { item2 in
                item1 == item2
            }
        }
        self.proofs = new
    }
    
    func mintForKeysetID(id:String) -> Mint? {
        if let foundMint = self.mints.first(where: { mint in
            mint.allKeysets!.contains(where: { keyset in
                keyset.id == id
            })
        }) {
            return foundMint
        } else {
            return nil
        }
    }
}
