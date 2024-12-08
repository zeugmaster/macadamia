import CashuSwift
import Foundation
import SwiftData

typealias Wallet = AppSchemaV1.Wallet
typealias Mint = AppSchemaV1.Mint
typealias Proof = AppSchemaV1.Proof
typealias Event = AppSchemaV1.Event
typealias Unit = AppSchemaV1.Unit

enum AppSchemaV1: VersionedSchema {
    
    static var versionIdentifier = Schema.Version(1,0,0)
    
    static var models: [any PersistentModel.Type] {
        [Wallet.self,
         Mint.self,
         Proof.self,
         Event.self]
    }
    
    @Model
    final class Wallet {
        
        @Attribute(.unique)
        var walletID: UUID
        
        var mnemonic: String
        var seed: String
        var active: Bool
        var name: String?

        @Relationship(inverse: \Mint.wallet)
        var mints: [Mint]

        var proofs: [Proof]
        var dateCreated: Date

        @Relationship(deleteRule: .cascade ,inverse: \Event.wallet)
        var events: [Event]

        init(mnemonic: String, seed: String, active:Bool = true) {
            self.walletID = UUID()
            self.mnemonic = mnemonic
            self.seed = seed
            self.active = active
            self.dateCreated = Date()
            self.mints = []
            self.proofs = []
            self.events = []
        }
    }

    @Model
    final class Mint: MintRepresenting {
        
        @Attribute(.unique)
        var mintID: UUID
        
        var url: URL
        var keysets: [CashuSwift.Keyset]
        var nickName: String?
        var dateAdded: Date
        
        var lastDismissedMOTDHash: String?
     
        var wallet: Wallet?
        
        var userIndex: Int?

        var proofs: [Proof]?

        required init(url: URL, keysets: [CashuSwift.Keyset]) {
            self.mintID = UUID()
            self.url = url
            self.keysets = keysets
            self.dateAdded = Date()
            self.proofs = []
        }
        
        var displayName: String {
            self.nickName ?? self.url.host() ?? self.url.absoluteString
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
        
        private static func selectWithoutFee(amount: Int, of proofs:[Proof]) -> [Proof]? {
            
            guard amount >= 0 else {
                logger.error("input selection amount can not be negative")
                return nil
            }
            
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
            
            guard amount >= 0 else {
                logger.error("input selection amount can not be negative")
                return nil
            }
            
            func fee(_ proofs:[Proof]) -> Int {
                ((proofs.reduce(0) { $0 + $1.inputFeePPK } + 999) / 1000)
            }
            
            guard var proofsSelected = selectWithoutFee(amount: amount, of: proofs) else {
                return nil
            }
                        
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
                keyset.derivationCounter += n
                self.keysets[index] = keyset
            }
        }
    }

    @Model
    final class Proof: ProofRepresenting {
        @Attribute(.unique)
        var proofID: UUID
        
        var keysetID: String
        var C: String
        var secret: String
        var amount: Int
        var state: Proof.State
        var unit: Unit
        
        var inputFeePPK:Int

        var dateCreated: Date

        @Relationship(inverse: \Mint.proofs)
        var mint: Mint?

        @Relationship(inverse: \Wallet.proofs)
        var wallet: Wallet?

        init(keysetID: String, C: String, secret: String, unit: Unit, inputFeePPK:Int, state: State, amount: Int, mint: Mint, wallet: Wallet) {
            self.proofID = UUID()
            self.keysetID = keysetID
            self.C = C
            self.secret = secret
            self.amount = amount
            self.state = state
            self.mint = mint
            self.wallet = wallet
            self.dateCreated = Date()
            self.unit = unit
            self.inputFeePPK = inputFeePPK
        }

        init(_ proofRepresenting: ProofRepresenting, unit: Unit, inputFeePPK:Int, state: State, mint: Mint, wallet: Wallet) {
            self.proofID = UUID()
            self.keysetID = proofRepresenting.keysetID
            self.C = proofRepresenting.C
            self.amount = proofRepresenting.amount
            self.secret = proofRepresenting.secret
            self.wallet = wallet
            self.mint = mint
            self.unit = unit
            self.inputFeePPK = inputFeePPK
            self.state = state
            self.dateCreated = Date()
        }

        enum State: Codable, Comparable {
            case valid
            case pending
            case spent
        }
    }

    @Model
    final class Event {
        @Attribute(.unique)
        var eventID: UUID
        
        var date: Date
        var unit: Unit
        var shortDescription: String
        var visible: Bool
        var kind: Kind
        var wallet: Wallet?
        
        var bolt11MintQuote: CashuSwift.Bolt11.MintQuote?
        var bolt11MeltQuoteData: Data? // SwiftData is unable to serialize CashuSwift.Bolt11.MeltQuote so we do it ourselves
        
        var amount: Int?
        var expiration: Date?
        var longDescription: String?
        var proofs: [Proof]?
        var memo: String?
        
//        @Attribute(.transformable)
        var tokens: [TokenInfo]?
        
        var mints: [Mint]?
        
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
        
        init(date: Date,
             unit: Unit,
             shortDescription: String,
             visible: Bool,
             kind: Kind,
             wallet: Wallet,
             bolt11MintQuote: CashuSwift.Bolt11.MintQuote? = nil,
             bolt11MeltQuote: CashuSwift.Bolt11.MeltQuote? = nil,
             amount: Int? = nil,
             expiration: Date? = nil,
             longDescription: String? = nil,
             proofs: [Proof]? = nil,
             memo: String? = nil,
             tokens: [TokenInfo]? = nil,
             minta: [Mint]? = nil,
             redeemed: Bool? = nil) {
            
            self.eventID = UUID()
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
            self.tokens = tokens
            self.mints = minta
            self.redeemed = redeemed
        }
        
        var bolt11MeltQuote: CashuSwift.Bolt11.MeltQuote? {
            get {
                guard let data = bolt11MeltQuoteData else { return nil }
                return try? JSONDecoder().decode(CashuSwift.Bolt11.MeltQuote.self, from: data)
            }
            set {
                bolt11MeltQuoteData = try? JSONEncoder().encode(newValue)
            }
        }
        
        static func pendingMintEvent(unit: Unit,
                                     shortDescription: String,
                                     visible: Bool = true,
                                     wallet: Wallet,
                                     quote: CashuSwift.Bolt11.MintQuote,
                                     amount: Int,
                                     expiration: Date,
                                     mint: Mint) -> Event {
            Event(date: Date(),
                  unit: unit,
                  shortDescription: shortDescription,
                  visible: visible,
                  kind: .pendingMint,
                  wallet: wallet,
                  bolt11MintQuote: quote,
                  amount: amount,
                  expiration: expiration,
                  minta: [mint]
            )
        }
        
        static func mintEvent(unit: Unit,
                              shortDescription: String,
                              visible: Bool = true,
                              wallet: Wallet,
                              quote: CashuSwift.Bolt11.MintQuote,
                              mint: Mint,
                              amount: Int) -> Event {
            Event(date: Date(),
                  unit: unit,
                  shortDescription: shortDescription,
                  visible: visible,
                  kind: .mint,
                  wallet: wallet,
                  bolt11MintQuote: quote,
                  amount: amount,
                  minta: [mint]
            )
        }
        
        static func sendEvent(unit: Unit,
                              shortDescription: String,
                              visible: Bool = true,
                              wallet: Wallet,
                              amount: Int,
                              longDescription: String,
                              proofs: [Proof],
                              memo: String,
                              tokens: [TokenInfo],
                              mint: Mint,
                              redeemed: Bool = false) -> Event {
            Event(date: Date(),
                  unit: unit,
                  shortDescription: shortDescription,
                  visible: visible,
                  kind: .send,
                  wallet: wallet,
                  amount: amount,
                  longDescription: longDescription,
                  proofs: proofs,
                  memo: memo,
                  tokens: tokens,
                  minta: [mint],
                  redeemed: redeemed
            )
        }
        
        static func receiveEvent(unit: Unit,
                                 shortDescription: String,
                                 visible: Bool = true,
                                 wallet: Wallet,
                                 amount: Int,
                                 longDescription: String,
                                 proofs: [Proof],
                                 memo: String,
                                 mints: [Mint],
                                 tokens: [TokenInfo],
                                 redeemed: Bool) -> Event {
            Event(date: Date(),
                  unit: unit,
                  shortDescription: shortDescription,
                  visible: visible,
                  kind: .receive,
                  wallet: wallet,
                  amount: amount,
                  longDescription: longDescription,
                  proofs: proofs,
                  memo: memo,
                  tokens: tokens,
                  minta: mints,
                  redeemed: redeemed
            )
        }
        
        static func pendingMeltEvent(unit: Unit,
                                     shortDescription: String,
                                     visible: Bool = true,
                                     wallet: Wallet,
                                     quote: CashuSwift.Bolt11.MeltQuote,
                                     amount: Int,
                                     expiration: Date,
                                     mints: [Mint]) -> Event {
            Event(date: Date(),
                  unit: unit,
                  shortDescription: shortDescription,
                  visible: visible,
                  kind: .pendingMelt,
                  wallet: wallet,
                  bolt11MeltQuote: quote,
                  amount: amount,
                  expiration: expiration,
                  minta: mints
            )
        }
        
        static func meltEvent(unit: Unit,
                              shortDescription: String,
                              visible: Bool = true,
                              wallet: Wallet,
                              amount: Int,
                              longDescription: String,
                              mints:[Mint]) -> Event {
            Event(date: Date(),
                  unit: unit,
                  shortDescription: shortDescription,
                  visible: visible,
                  kind: .melt,
                  wallet: wallet,
                  amount: amount,
                  longDescription: longDescription,
                  minta: mints
            )
        }
        
        static func drainEvent(shortDescription: String,
                               visible:Bool = true,
                               wallet: Wallet,
                               tokens: [TokenInfo]) -> Event {
            Event(date: Date(),
                  unit: .other,
                  shortDescription: shortDescription,
                  visible: visible,
                  kind: .drain,
                  wallet: wallet,
                  tokens: tokens)
        }
        
        static func restoreEvent(shortDescription: String,
                                 visible: Bool = true,
                                 wallet: Wallet,
                                 longDescription: String) -> Event {
            Event(date: Date(),
                  unit: .other,
                  shortDescription: shortDescription,
                  visible: visible,
                  kind: .restore,
                  wallet: wallet,
                  longDescription: longDescription)
        }
    }

    enum Unit: String, Codable, CaseIterable {
        
        case sat
        case usd
        case eur
        case other // TODO: this should have an associated string as catch all for non standard currency codes
        case none

        init?(_ string: String?) {
            if let match = Unit.allCases.first(where: { $0.rawValue.lowercased() == string?.lowercased() }) {
                self = match
            } else {
                return nil
            }
        }
    }
}


