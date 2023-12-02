//
//  model.swift
//  macadamia-cli
//
//  Created by Dario Lass on 01.12.23.
//

import Foundation

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

class Proof: Codable {
    let id: String
    let amount: Int
    let secret: String
    let C: String
    
    init(id: String, amount: Int, secret: String, C: String) {
        self.id = id
        self.amount = amount
        self.secret = secret
        self.C = C
    }
}
