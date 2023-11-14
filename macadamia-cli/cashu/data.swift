//
//  data.swift
//  macadamia-cli
//
//  Created by Dario Lass on 14.11.23.
//

import Foundation

struct Database: Codable {
    var tokens = [Token_JSON]()
}

class TokenStore {
    private var database:Database
    
    private func getFileURL() -> URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        return paths[0].appendingPathComponent("Database.json")
    }
    
    init() {
        self.database = Database()
        //check wether db file is present
        if FileManager.default.fileExists(atPath: getFileURL().path()) {
            self.database = load()!
        } else {
            print("No database file yet")
        }
    }
    
    func addToken(token:Token_JSON) {
        print("trying to save token to db: \(token)")
        self.database.tokens.append(token)
        self.save(data: self.database)
    }
    
    
    //TODO: mint selection
    //FIXME: not ready
    func retrieveProofsForAmount(amount:Int) -> [Proofs_JSON]? {
        //check if we have enough total in the db
        var accumulatedAmount: Int = 0
        var selectedProofs: [Proofs_JSON] = []
        var workingDB = self.database
        outerLoop: for token in self.database.tokens {
            for proof in token.proofs {
                accumulatedAmount += proof.amount
                selectedProofs.append(proof)
                
                if accumulatedAmount >= amount {
                    break outerLoop
                }
            }
        }
        guard accumulatedAmount >= amount else {
            print("Target amount of \(amount) was not reached. Only accumulated \(accumulatedAmount).")
            return nil
        }
        print("Target amount reached or exceeded with a total of \(accumulatedAmount).")
        return selectedProofs
    }
    

    private func save(data: Database) {
        let url = getFileURL()
        do {
            let encoded = try JSONEncoder().encode(data)
            try encoded.write(to: url)
            print("wrote data to URL: \(url)")
        } catch {
            print("Failed to write JSON data: \(error.localizedDescription)")
        }
    }
    private func load() -> Database? {
        let url = getFileURL()
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode(Database.self, from: data)
            return decoded
        } catch {
            print("Failed to read JSON data: \(error.localizedDescription)")
            return nil
        }
    }
}
