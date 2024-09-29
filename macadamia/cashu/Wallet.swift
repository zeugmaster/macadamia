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
    
    @Relationship(inverse: \Proof.wallet)
    var proofs:[Proof]
    
    let dateCreated:Date
    var events:[Event]
    
    init(seed: String? = nil) {
        self.seed = seed
        self.dateCreated = Date()
        self.mints = []
        self.proofs = []
        self.events = []
    }
}

@Model
final class Mint:MintRepresenting {
    
    var url: URL
    var keysets: [CashuSwift.Keyset]
    var info: MintInfo?
    var nickName:String?
    var dateAdded:Date
    
//    @Relationship(inverse: \Wallet.mints)
    var wallet: Wallet?
    
    @Relationship(inverse: \Proof.mint)
    var proofs:[Proof]
    
    required init(url: URL, keysets: [CashuSwift.Keyset]) {
        self.url = url
        self.keysets = keysets
        self.dateAdded = Date()
        self.proofs = []
    }
}


struct MintInfo: Codable {
    let name: String
    let pubkey: String
    let version: String
    let shortDescription: String?
    let longDescription: String?
    let imageURL:URL?
    
    init(with mintInfo:CashuSwift.MintInfo) {
        self.name = mintInfo.name
        self.pubkey = mintInfo.pubkey
        self.version = mintInfo.version
        self.shortDescription = mintInfo.descriptionShort
        self.longDescription = mintInfo.descriptionLong
        self.imageURL = nil
    }
}

@Model
final class Proof:ProofRepresenting {
    
    var keysetID: String
    var C: String
    var secret: String
    var amount: Int
    var state:Proof.State
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
        self.dateCreated = Date()
    }
    
    enum State:Codable {
        case valid
        case pending
        case spent
    }
}

@Model
final class Event {
    let date: Date
    let unit: Unit
    let shortDescription: String
    let visible: Bool
    let kind: Kind
    
    enum Kind: Codable {
        case pendingMint
        case mint
        case send
        case receive
        case pendingMelt
        case melt
        case restore
        case drain
    }
    
    // Kind specific properties
    var bolt11MintQuote: CashuSwift.Bolt11.MintQuote?
    var bolt11MeltQuote: CashuSwift.Bolt11.MeltQuote?
    var amount: Double?
    var expiration: Date?
    var longDescription: String?
    var proofs:[Proof]?
    var memo: String?
    var tokenString: String?
    var redeemed: Bool?
    
    init(date: Date, unit: Unit, shortDescription: String, visible: Bool, kind: Kind, bolt11MintQuote: CashuSwift.Bolt11.MintQuote? = nil, bolt11MeltQuote: CashuSwift.Bolt11.MeltQuote? = nil, amount: Double? = nil, expiration: Date? = nil, longDescription: String? = nil, proofs: [Proof]? = nil, memo: String? = nil, tokenString: String? = nil, redeemed: Bool? = nil) {
        self.date = date
        self.unit = unit
        self.shortDescription = shortDescription
        self.visible = visible
        self.kind = kind
        self.bolt11MintQuote = bolt11MintQuote
        self.bolt11MeltQuote = bolt11MeltQuote
        self.amount = amount
        self.expiration = expiration
        self.longDescription = longDescription
        self.proofs = proofs
        self.memo = memo
        self.tokenString = tokenString
        self.redeemed = redeemed
    }
    
    static func pendingMintEvent(unit:Unit, shortDescription: String, visible:Bool = true, quote:CashuSwift.Bolt11.MintQuote, amount:Double, expiration:Date) -> Event {
        Event(date: Date(), unit: unit, shortDescription: shortDescription, visible: visible, kind: .pendingMint, bolt11MintQuote: quote, amount: amount, expiration: expiration)
    }
}

enum Unit: String, Codable, CaseIterable {
    case sat = "sat"
    case usd = "usd"
    case eur = "eur"
    case other = "other"
    
    init?(_ string: String?) {
        if let match = Unit.allCases.first(where: { $0.rawValue.lowercased() == string?.lowercased() }) {
            self = match
        } else {
            return nil
        }
    }
}
