import CashuSwift
import Foundation
import SwiftData

@Model
final class Wallet {
    var seed: String?

    var name: String?

    @Relationship(inverse: \Mint.wallet)
    var mints: [Mint]

    @Relationship(inverse: \Proof.wallet)
    var proofs: [Proof]

    var dateCreated: Date

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
 
    var wallet: Wallet?

    @Relationship(inverse: \Proof.mint)
    var proofs: [Proof]

    required init(url: URL, keysets: [CashuSwift.Keyset]) {
        self.url = url
        self.keysets = keysets
        self.dateAdded = Date()
        self.proofs = []
    }
    
    func select(allProofs:[Proof], amount:Int, unit:Unit) -> (selected:[Proof], fee:Int)? {
        
        let validProofsOfUnit = allProofs.filter({ $0.unit == unit && $0.state == .valid && $0.mint == self})
        
        guard !validProofsOfUnit.isEmpty else {
            return nil
        }
        
        if validProofsOfUnit.allSatisfy({ $0.inputFeePPK == 0 }) {
            if let selection = Mint.selectWithoutFee(amount: amount, of: validProofsOfUnit) {
                return (selection, 0)
            } else {
                return nil
            }
        } else {
            return Mint.selectIncludingFee(amount: amount, of: validProofsOfUnit)
        }
    }
    
    func proofs(for amount:Int, with unit: Unit) -> (selected:[Proof], fee:Int)? {
        
        let validProofsOfUnit = proofs.filter({ $0.unit == unit && $0.state == .valid })
        
        guard !validProofsOfUnit.isEmpty else {
            return nil
        }
        
        if validProofsOfUnit.allSatisfy({ $0.inputFeePPK == 0 }) {
            if let selection = Mint.selectWithoutFee(amount: amount, of: validProofsOfUnit) {
                return (selection, 0)
            } else {
                return nil
            }
        } else {
            return Mint.selectIncludingFee(amount: amount, of: validProofsOfUnit)
        }
    }
    
    private static func selectWithoutFee(amount: Int, of proofs:[Proof]) -> [Proof]? {
        
        let totalAmount = proofs.reduce(0) { $0 + $1.amount }
        if totalAmount < amount {
            return nil
        }
        
        // dp[s] will store a subset of proofs that sum up to s
        var dp = Array<[Proof]?>(repeating: nil, count: totalAmount + 1)
        dp[0] = []
        
        for proof in proofs {
            let amount = proof.amount
            if amount > totalAmount {
                continue
            }
            for s in stride(from: totalAmount, through: amount, by: -1) {
                if let previousSubset = dp[s - amount], dp[s] == nil {
                    dp[s] = previousSubset + [proof]
                }
            }
        }
        
        // Find the minimal total amount that is at least the target amount
        for s in amount...totalAmount {
            if let subset = dp[s] {
                return subset
            }
        }
        
        return nil
    }
    
    private static func selectIncludingFee(amount: Int, of proofs:[Proof]) -> (selected:[Proof], fee:Int)? {
        
        // TODO: BRUTE FORCE CHECK FOR POSSIBLE
        
        func fee(_ proofs:[Proof]) -> Int {
            ((proofs.reduce(0) { $0 + $1.inputFeePPK } + 999) / 1000)
        }
        
        guard var proofsSelected = selectWithoutFee(amount: amount, of: proofs) else {
            return nil
        }
        
//        proofsSelected.sort(by: { $0.amount > $1.amount })
        
        var proofsRest:[Proof] = proofs.filter({ !proofsSelected.contains($0) })
        
        proofsRest.sort(by: { $0.amount < $1.amount })
        
        while proofsSelected.sum < amount + fee(proofsSelected) {
            if proofsRest.isEmpty {
                // TODO: LOG INSUFFICIENT FUNDS
                return nil
            } else {
                proofsSelected.append(proofsRest.removeFirst())
            }
        }
        
        return (proofsSelected, fee(proofsSelected))
    }
    
    func increaseDerivationCounterForKeysetWithID(_ keysetID:String, by n:Int) {
        if let index = self.keysets.firstIndex(where: { $0.keysetID == keysetID }) {
            var keyset = self.keysets[index]
            proofs.forEach({ $0.inputFeePPK = keyset.inputFeePPK })
            keyset.derivationCounter += n
            self.keysets[index] = keyset
        }
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
    
    var inputFeePPK:Int

    var dateCreated: Date

//    @Relationship(inverse: \Mint.proofs)
    var mint: Mint?

//    @Relationship(inverse: \Wallet.proofs)
    var wallet: Wallet?

    init(keysetID: String, C: String, secret: String, unit: Unit, inputFeePPK:Int, state: State, amount: Int, mint: Mint?, wallet: Wallet?) {
        self.keysetID = keysetID
        self.C = C
        self.secret = secret
        self.amount = amount
        self.state = state
        self.mint = mint
        self.wallet = wallet
        dateCreated = Date()
        self.unit = unit
        self.inputFeePPK = inputFeePPK
    }

    init(_ proofRepresenting: ProofRepresenting, unit: Unit, inputFeePPK:Int, state: State, mint: Mint, wallet: Wallet) {
        self.keysetID = proofRepresenting.keysetID
        self.C = proofRepresenting.C
        self.amount = proofRepresenting.amount
        self.secret = proofRepresenting.secret
        self.wallet = wallet
        self.mint = mint
        self.unit = unit
        self.inputFeePPK = inputFeePPK
        self.state = state
        dateCreated = Date()
    }

    enum State: Codable, Comparable {
        case valid
        case pending
        case spent
    }
}

@Model
final class Event {
    var date: Date
    var unit: Unit
    var shortDescription: String
    var visible: Bool
    var kind: Kind
    var wallet: Wallet

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

    static func pendingMeltEvent(unit: Unit, shortDescription: String, visible: Bool = true, wallet: Wallet, quote: CashuSwift.Bolt11.MeltQuote, amount: Double, expiration: Date, longDescription: String) -> Event {
        Event(date: Date(), unit: unit, shortDescription: shortDescription, visible: visible, kind: .pendingMelt, wallet: wallet, bolt11MeltQuote: quote, amount: amount, expiration: expiration, longDescription: longDescription)
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
