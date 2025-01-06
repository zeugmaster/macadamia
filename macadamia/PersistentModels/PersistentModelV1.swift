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

        init(keysetID: String,
             C: String,
             secret: String,
             unit: Unit,
             inputFeePPK:Int,
             state: State,
             amount: Int,
             mint: Mint,
             wallet: Wallet) {
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

        init(_ proofRepresenting: ProofRepresenting,
             unit: Unit,
             inputFeePPK:Int,
             state: State,
             mint: Mint,
             wallet: Wallet) {
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
        
        @available(*, deprecated, message: "deprecated in V1 Schema. macadamia uses other event information to build tokens (mint(s), proofs, memo)")
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
             token: CashuSwift.Token? = nil,
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
            self.tokens = tokens        // TODO: REMOVE TOGETHER WITH DRAIN FUNCTION
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


