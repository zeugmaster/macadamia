//
//  Wallet.swift
//  macadamia
//
//  Created by zm on 27.08.24.
//

import Foundation
import CashuSwift
import SwiftData

@Model
class Wallet {
    @Attribute(.unique) let seed:String
    var mints:[Mint]
    var validProofs:[Proof]
    var spentProofs:[Proof]
    let dateCreated:Date
    var events:[Event]
    
    init(seed: String, mints: [Mint], validProofs: [Proof], spentProofs: [Proof], dateCreated:Date) {
        self.seed = seed
        self.mints = mints
        self.validProofs = validProofs
        self.spentProofs = spentProofs
        self.dateCreated = dateCreated
    }
}

@Model
class Event {
    @Attribute(.unique) let id:UUID
    let date:Date
    let unit:Unit
    var shortDescription:String
    var visible:Bool
    
    init(unit: Unit, shortDescription:String, visible:Bool) {
        self.id = UUID()
        self.date = Date()
        self.unit = unit
        self.shortDescription = shortDescription
        self.visible = visible
    }
}

@Model
final class PendingMintEvent: Event {
    let quote:Bolt11.MintQuote
    let amount:Double
    let expiration:Date
    
    init(quote: Bolt11.MintQuote, amount: Double, expiration: Date, unit: Unit, shortDescription:String, visible:Bool = true) {
        self.quote = quote
        self.amount = amount
        self.expiration = expiration
        super.init(unit: unit,
                   shortDescription: shortDescription,
                   visible: visible)
    }
}

@Model
final class MintEvent: Event {
    let amount:Double
    let longDescription:String
    
    init(amount: Double, longDescription: String, unit: Unit, shortDescription:String, visible:Bool = true) {
        self.amount = amount
        self.longDescription = longDescription
        super.init(unit: unit, shortDescription: shortDescription,
                   visible: visible)
    }
}

@Model
final class SendEvent: Event {
    let amount:Double
    let longDescription:String
    var redeemed:Bool
    let proofs:[Proof]
    let memo:String?
    
    init(amount: Double, longDescription: String, redeemed: Bool, proofs: [Proof], unit: Unit, shortDescription:String, visible:Bool = true) {
        self.amount = amount
        self.longDescription = longDescription
        self.redeemed = redeemed
        self.proofs = proofs
        super.init(unit: unit, 
                   shortDescription: shortDescription,
                   visible: visible)
    }
}

@Model
final class ReceiveEvent: Event {
    let amount:Double
    let longDescription:String
    let memo:String?
    
    init(amount: Double, longDescription: String, unit: Unit, shortDescription:String, visible:Bool = true) {
        self.amount = amount
        self.longDescription = longDescription
        super.init(unit: unit,
                   shortDescription: shortDescription,
                   visible: visible)
    }
}

@Model
final class PendingMeltEvent: Event {
    let quote:Bolt11.MeltQuote
    let amount:Double
    let expiration:Date
    
    init(quote: Bolt11.MeltQuote, amount: Double, expiration: Date, visible:Bool = true) {
        self.quote = quote
        self.amount = amount
        self.expiration = expiration
        super.init(unit: unit,
                   shortDescription: shortDescription, visible: visible)
    }
}

@Model
final class MeltEvent: Event {
    let amount:Double
    let longDescription:String
    
    init(amount: Double, longDescription: String, visible:Bool = true) {
        self.amount = amount
        self.longDescription = longDescription
        super.init(unit: unit, shortDescription: shortDescription, visible: visible)
    }
}

@Model
final class RestoreEvent: Event {
    let longDescription:String
    
    init(longDescription: String) {
        self.longDescription = longDescription
        super.init(unit: unit, shortDescription: shortDescription, visible: visible)
    }
}

enum Unit {
    case sat
    case usd
    case eur
    case mixed
    case other
}
