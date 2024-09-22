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
final class Wallet {
    let seed:String?
    
    let name:String?
    
    @Relationship(inverse: \Mint.wallet)
    var mints:[Mint]
    
    var proofs:[Proof]
    let dateCreated:Date
    var events:[Event]
    
    init(seed: String? = nil) {
        self.seed = seed
        self.dateCreated = Date()
    }
}

@Model
final class Mint:MintRepresenting {
    var url: URL
    
    var keysets: [CashuSwift.Keyset]
    
    var info: CashuSwift.MintInfo?
    
    var nickName:String?
    
    var dateAdded:Date
    
//    @Relationship(inverse: \Wallet.mints)
    var wallet: Wallet
    
    @Relationship(inverse: \Proof.mint)
    var proofs:[Proof]
    
    required init(url: URL, keysets: [CashuSwift.Keyset]) {
        self.url = url
        self.keysets = keysets
        self.dateAdded = Date()
    }
}

@Model
final class Proof:ProofRepresenting {
    
    var keysetID: String
    var C: String
    var secret: String
    var amount: Int
    var state:State
    var unit:Unit
    
    var dateCreated:Date
    
//    @Relationship(inverse: \Mint.proofs)
    var mint:Mint
    
//    @Relationship(inverse: \Wallet.proofs)
    var wallet:Wallet
    
    init(keysetID: String, C: String, secret: String, unit:Unit, state:State, amount: Int, mint:Mint, wallet: Wallet) {
        self.keysetID = keysetID
        self.C = C
        self.secret = secret
        self.amount = amount
        self.state = state
        self.mint = mint
        self.wallet = wallet
        self.dateCreated = Date()
        self.unit = unit
    }
    
    init(_ proofRepresenting:ProofRepresenting, unit:Unit, state:State, mint: Mint, wallet:Wallet) {
        self.keysetID = proofRepresenting.keysetID
        self.C = proofRepresenting.C
        self.amount = proofRepresenting.amount
        self.secret = proofRepresenting.secret
        self.wallet = wallet
        self.mint = mint
        self.unit = unit
        self.state = state
    }
    
    enum State {
        case valid
        case pending
        case spent
    }
}

//@Model
class Event: Identifiable {
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
    let quote:CashuSwift.Bolt11.MintQuote
    let amount:Double
    let expiration:Date
    
    init(quote: CashuSwift.Bolt11.MintQuote, amount: Double, expiration: Date, unit: Unit, shortDescription:String, visible:Bool = true) {
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
    let quote:CashuSwift.Bolt11.MeltQuote
    let amount:Double
    let expiration:Date
    
    init(quote: CashuSwift.Bolt11.MeltQuote, amount: Double, expiration: Date, visible:Bool = true) {
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

enum Unit:String, CaseIterable {
    case sat = "sat"
    case usd = "usd"
    case eur = "eur"
    case other = "other"
    
    init?(_ string:String?) {
        if let match = Unit.allCases.first(where: { $0.rawValue.lowercased() == string?.lowercased() }) {
            self = match
        } else {
            return nil
        }
    }
}

