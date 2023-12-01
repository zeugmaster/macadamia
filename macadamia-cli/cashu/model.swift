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
