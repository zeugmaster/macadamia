//
//  model.swift
//  macadamia-cli
//
//  Created by Dario Lass on 01.12.23.
//

import Foundation
import CryptoKit

class Output: Codable {
    let amount: Int
    let output: String
    let secret: String
    let blindingFactor: String
    
    init(amount: Int, output: String, secret: String, blindingFactor: String) {
        self.amount = amount
        self.output = output
        self.secret = secret
        self.blindingFactor = blindingFactor
    }
}

class Promise {
    let amount: Int
    let promise: String
    let id: String
    let blindingFactor:String
    let secret: String
    
    init(amount: Int, promise: String, id: String, blindingFactor: String, secret: String) {
        self.amount = amount
        self.promise = promise
        self.id = id
        self.blindingFactor = blindingFactor
        self.secret = secret
    }
}

class Proof: Codable, Equatable, CustomStringConvertible {
    
    static func == (lhs: Proof, rhs: Proof) -> Bool {
        if lhs.C == rhs.C {
            return true
        } else {
            return false
        }
    }
    
    let id: String
    let amount: Int
    let secret: String
    let C: String
    
    var description: String {
        return "Proof: ...\(C.suffix(6)) secret: ...\(secret.suffix(8)) amount: \(amount)"
    }
    
    init(id: String, amount: Int, secret: String, C: String) {
        self.id = id
        self.amount = amount
        self.secret = secret
        self.C = C
    }
}

//TODO: one mint can have one URL, but multiple <Keysets> with keys and keyset_ids
class Mint: Codable {
    let url: URL
    var keySets: [Keyset]
    
    
    init(url: URL, keySets: [Keyset]) {
        self.url = url
        self.keySets = keySets
    }
    
    static func calculateKeysetID(keyset:Dictionary<String,String>) -> String {
        let sortedValues = keyset.sorted { (firstElement, secondElement) -> Bool in
            guard let firstKey = UInt(firstElement.key), let secondKey = UInt(secondElement.key) else {
                return false
            }
            return firstKey < secondKey
        }.map { $0.value }
        //print(sortedValues)
        
        let concat = sortedValues.joined()
        let hashData = Data(SHA256.hash(data: concat.data(using: .utf8)!))
        let id = hashData.base64EncodedString().prefix(12)
        return String(id)
    }
}
struct Keyset: Codable {
    let keysetID: String
    let keys: Dictionary<String, String>? //me might need ID while not having access to old keys
}

struct PaymentRequest: Codable {
    let pr: String
    let hash: String
    
    static func satAmountFromEncodedPR(pr:String) -> Int? {
        guard let range = pr.range(of: "1", options: .backwards) else {
            return nil
        }
        let endIndex = range.lowerBound
        let hrp = String(pr[..<endIndex])
        if hrp.prefix(4) == "lnbc" {
            var num = hrp.dropFirst(4)
            let multiplier = num.popLast()
            guard var n = Double(num) else {
                return nil
            }
            switch multiplier {
            case "m": n *= 100000
            case "u": n *= 100
            case "n": n *= 0.1
            case "p": n *= 0.0001
            default: return nil
            }
            return n >= 1 ? Int(n) : nil
        } else {
            return nil
        }
    }
}

struct MeltRequest: Codable {
    let proofs: [Proof]
    let pr: String
}
struct MeltRequestResponse: Codable {
    let paid: Bool
    let preimage: String?
}

struct Output_JSON: Codable {
    let amount: Int
    let B_: String
}
struct Token_Container: Codable {
    let token: [Token_JSON]
    let memo: String?
}
struct Token_JSON: Codable {
    let mint: String
    var proofs: [Proof]
}

