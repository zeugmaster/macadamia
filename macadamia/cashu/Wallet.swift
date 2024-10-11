import CashuSwift
import Foundation
import SwiftData

@Model
final class Wallet {
    let seed: String?

    let name: String?

    @Relationship(inverse: \Mint.wallet)
    var mints: [Mint]

    @Relationship(inverse: \Proof.wallet)
    var proofs: [Proof]

    let dateCreated: Date

    @Relationship(inverse: \Event.wallet)
    var events: [Event]

    init(seed: String? = nil) {
        self.seed = seed
        dateCreated = Date()
        mints = []
        proofs = []
        events = []
    }
}

@Model
final class Mint: MintRepresenting {
    var url: URL
    var keysets: [CashuSwift.Keyset]
    var info: MintInfo?
    var nickName: String?
    var dateAdded: Date

//    @Relationship(inverse: \Wallet.mints)
    var wallet: Wallet?

    @Relationship(inverse: \Proof.mint)
    var proofs: [Proof]

    required init(url: URL, keysets: [CashuSwift.Keyset]) {
        self.url = url
        self.keysets = keysets
        dateAdded = Date()
        proofs = []
    }
}

struct MintInfo: Codable {
    let name: String
    let pubkey: String
    let version: String
    let shortDescription: String?
    let longDescription: String?
    let imageURL: URL?

    init(with mintInfo: CashuSwift.MintInfo) {
        name = mintInfo.name
        pubkey = mintInfo.pubkey
        version = mintInfo.version
        shortDescription = mintInfo.descriptionShort
        longDescription = mintInfo.descriptionLong
        imageURL = nil
    }
}

@Model
final class Proof: ProofRepresenting {
    var keysetID: String
    var C: String
    var secret: String
    var amount: Int
    var state: Proof.State
    var unit: Unit

    var dateCreated: Date

//    @Relationship(inverse: \Mint.proofs)
    var mint: Mint

//    @Relationship(inverse: \Wallet.proofs)
    var wallet: Wallet

    init(keysetID: String, C: String, secret: String, unit: Unit, state: State, amount: Int, mint: Mint, wallet: Wallet) {
        self.keysetID = keysetID
        self.C = C
        self.secret = secret
        self.amount = amount
        self.state = state
        self.mint = mint
        self.wallet = wallet
        dateCreated = Date()
        self.unit = unit
    }

    init(_ proofRepresenting: ProofRepresenting, unit: Unit, state: State, mint: Mint, wallet: Wallet) {
        keysetID = proofRepresenting.keysetID
        C = proofRepresenting.C
        amount = proofRepresenting.amount
        secret = proofRepresenting.secret
        self.wallet = wallet
        self.mint = mint
        self.unit = unit
        self.state = state
        dateCreated = Date()
    }

    enum State: Codable {
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
    var visible: Bool
    let kind: Kind
    let wallet: Wallet

    var bolt11MintQuote: CashuSwift.Bolt11.MintQuote?
    var bolt11MeltQuote: CashuSwift.Bolt11.MeltQuote?
    var amount: Double?
    var expiration: Date?
    var longDescription: String?
    var proofs: [Proof]?
    var memo: String?
    var tokenString: String?
    var redeemed: Bool?

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

    init(date: Date, unit: Unit, shortDescription: String, visible: Bool, kind: Kind, wallet: Wallet, bolt11MintQuote: CashuSwift.Bolt11.MintQuote? = nil, bolt11MeltQuote: CashuSwift.Bolt11.MeltQuote? = nil, amount: Double? = nil, expiration: Date? = nil, longDescription: String? = nil, proofs: [Proof]? = nil, memo: String? = nil, tokenString: String? = nil, redeemed: Bool? = nil) {
        self.date = date
        self.unit = unit
        self.shortDescription = shortDescription
        self.visible = visible
        self.kind = kind
        self.wallet = wallet
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

    static func pendingMintEvent(unit: Unit, shortDescription: String, visible: Bool = true, wallet: Wallet, quote: CashuSwift.Bolt11.MintQuote, amount: Double, expiration: Date) -> Event {
        Event(date: Date(), unit: unit, shortDescription: shortDescription, visible: visible, kind: .pendingMint, wallet: wallet, bolt11MintQuote: quote, amount: amount, expiration: expiration)
    }

    static func mintEvent(unit: Unit, shortDescription: String, visible: Bool = true, wallet: Wallet, amount: Double) -> Event {
        Event(date: Date(), unit: unit, shortDescription: shortDescription, visible: visible, kind: .mint, wallet: wallet, amount: amount)
    }

    static func sendEvent(unit: Unit, shortDescription: String, visible: Bool = true, wallet: Wallet, amount: Double, longDescription: String, proofs: [Proof], memo: String, tokenString: String, redeemed: Bool = false) -> Event {
        Event(date: Date(), unit: unit, shortDescription: shortDescription, visible: visible, kind: .send, wallet: wallet, amount: amount, longDescription: longDescription, proofs: proofs, memo: memo, tokenString: tokenString, redeemed: redeemed)
    }

    static func receiveEvent(unit: Unit, shortDescription: String, visible: Bool = true, wallet: Wallet, amount: Double, longDescription: String, proofs: [Proof], memo: String, tokenString: String, redeemed: Bool) -> Event {
        Event(date: Date(), unit: unit, shortDescription: shortDescription, visible: visible, kind: .receive, wallet: wallet, amount: amount, longDescription: longDescription, proofs: proofs, memo: memo, tokenString: tokenString, redeemed: redeemed)
    }

    static func pendingMeltEvent(unit: Unit, shortDescription: String, visible: Bool = true, wallet: Wallet, quote _: CashuSwift.Bolt11.MeltQuote, amount: Double, expiration: Date, longDescription: String, proofs: [Proof]) -> Event {
        Event(date: Date(), unit: unit, shortDescription: shortDescription, visible: visible, kind: .pendingMelt, wallet: wallet, amount: amount, expiration: expiration, longDescription: longDescription, proofs: proofs)
    }

    static func meltEvent(unit: Unit, shortDescription: String, visible: Bool = true, wallet: Wallet, amount: Double) -> Event {
        Event(date: Date(), unit: unit, shortDescription: shortDescription, visible: visible, kind: .melt, wallet: wallet, amount: amount)
    }
}

enum Unit: String, Codable, CaseIterable {
    case sat
    case usd
    case eur
    case other

    init?(_ string: String?) {
        if let match = Unit.allCases.first(where: { $0.rawValue.lowercased() == string?.lowercased() }) {
            self = match
        } else {
            return nil
        }
    }
}
