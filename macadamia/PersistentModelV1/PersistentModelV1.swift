import CashuSwift
import Foundation
import SwiftData
import secp256k1

typealias Wallet = AppSchemaV1.Wallet
typealias Mint = AppSchemaV1.Mint
typealias Proof = AppSchemaV1.Proof
typealias Event = AppSchemaV1.Event
typealias Unit = AppSchemaV1.Unit
typealias BlankOutputSet = AppSchemaV1.BlankOutputSet

class DatabaseManager {
    static let shared = DatabaseManager()
    
    private(set) var container: ModelContainer
    
    private init() {
        let schema = Schema([
            Wallet.self,
            Proof.self,
            Mint.self,
            Event.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
    
    func newContext() -> ModelContext {
        return ModelContext(container)
    }
}

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
        
        var privateKeyData: Data?

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
        
        func balance(of unit: Unit = .sat, state: Proof.State = .valid) -> Int {
            var sum = 0
            for mint in self.mints.filter({ $0.hidden == false }) {
                sum += mint.proofs?.filter({ $0.unit == unit && $0.state == state }).sum ?? 0
            }
            return sum
        }
        
        var publicKeyString: String? {
            guard let data = self.privateKeyData,
                  let key = try? secp256k1.Signing.PrivateKey(dataRepresentation: data) else {
                return nil
            }
            return String(bytes: key.publicKey.dataRepresentation)
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
        
        var events: [Event]?
        
        var hidden: Bool = false

        required init(url: URL, keysets: [CashuSwift.Keyset]) {
            self.mintID = UUID()
            self.url = url
            self.keysets = keysets
            self.dateAdded = Date()
            self.proofs = []
        }
        
        init(_ representation: MintRepresenting) {
            self.mintID = UUID()
            self.url = representation.url
            self.keysets = representation.keysets
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
        
        var dleq: CashuSwift.DLEQ?
        
        var state: Proof.State
        var unit: Unit
        
        var inputFeePPK:Int

        var dateCreated: Date

        @Relationship(inverse: \Mint.proofs)
        var mint: Mint?

        @Relationship(inverse: \Wallet.proofs)
        var wallet: Wallet?
        
        @MainActor
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

        @MainActor
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
            self.dleq = proofRepresenting.dleq
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
        
        var token: CashuSwift.Token?
        
        @Relationship(deleteRule: .noAction, inverse: \Mint.events)
        var mints: [Mint]?
        
        // Persistence for NUT-08 blank outputs and secrets, blinding factors to allow for melt operation repeatability
        // another case where SwiftData refuses to store the "complex" codable struct
        // so we need to (de-) serialize it ourselves
        var blankOutputData: Data?
        
        var redeemed: Bool?
        
        enum Kind: Codable {
            case pendingMint
            case mint
            case send
            case receive
            case pendingReceive
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
             token: CashuSwift.Token? = nil,
             expiration: Date? = nil,
             longDescription: String? = nil,
             proofs: [Proof]? = nil,
             memo: String? = nil,
             mints: [Mint]? = nil,
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
            self.token = token
            self.expiration = expiration
            self.longDescription = longDescription
            self.proofs = proofs
            self.memo = memo
            self.mints = Array(mints ?? [])
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
        
        var blankOutputs: BlankOutputSet? {
            get {
                guard let data = blankOutputData else { return nil }
                return try? JSONDecoder().decode(BlankOutputSet.self, from: data)
            }
            set {
                blankOutputData = try? JSONEncoder().encode(newValue)
            }
        }
    }
    
    struct BlankOutputSet: Codable {
        let outputs: [CashuSwift.Output]
        let blindingFactors: [String]
        let secrets: [String]
        
        enum CodingKeys: String, CodingKey {
            case outputs
            case blindingFactors
            case secrets
        }
        
        init(tuple: (outputs: [CashuSwift.Output], blindingFactors: [String], secrets: [String]), event: Event? = nil) {
            self.outputs = tuple.outputs
            self.blindingFactors = tuple.blindingFactors
            self.secrets = tuple.secrets
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
    
    ///Insert the specified list of SwiftData model objects into the model context and save the new state.
    @MainActor
    static func insert(_ models: [any PersistentModel], into modelContext: ModelContext) {
        models.forEach({ modelContext.insert($0) })
        do {
            try modelContext.save()
            logger.info("successfully added \(models.count) object\(models.count == 1 ? "" : "s") to the database.")
        } catch {
            logger.error("Saving SwiftData model context failed with error: \(error)")
        }
    }
    
    @MainActor
    static func addMint(_ mint: MintRepresenting,
                        to context: ModelContext,
                        hidden: Bool = false,
                        proofs: [ProofRepresenting]? = nil) throws -> Mint {
        
        guard let activeWallet = try context.fetch(FetchDescriptor<Wallet>()).first(where: { $0.active == true }) else {
            throw macadamiaError.databaseError("Unable to fetch active wallet.")
        }
        
        let mints = activeWallet.mints
        
        if let mint = mints.first(where: { $0.matches(mint) }) {
            logger.info("mint \(mint.url) is already in the database")
            if mint.hidden != hidden { mints.setHidden(hidden, for: mint) }
            addProofs(proofs, to: mint)
            return mint
        } else {
            let newMint = Mint(mint)
            newMint.wallet = activeWallet
            newMint.hidden = hidden
            newMint.userIndex = hidden ? 10000 : mints.count + 1 // + 1 because mints does not contain the new mint yet FIXME: not ideal
            context.insert(newMint)
            addProofs(proofs, to: newMint)
            try context.save()
            logger.info("added new mint with URL \(mint.url.absoluteString)")
            return newMint
        }
        
        func addProofs(_ proofs: [ProofRepresenting]?, to mint: Mint) {
            if let proofs,
               let mintProofs = mint.proofs,
               let keyset = mint.keysets.first(where: { $0.keysetID == proofs.first?.keysetID }) {
                let inputFee = keyset.inputFeePPK
                var internalProofs = [Proof]()
                for p in proofs {
                    if !mintProofs.contains(where: { $0.matches(p) }) { // inefficient duplicate check
                        internalProofs.append(Proof(p, unit: Unit(keyset.unit) ?? .sat,
                                                    inputFeePPK: inputFee,
                                                    state: .valid,
                                                    mint: mint,
                                                    wallet: activeWallet))
                    }
                }
                mint.proofs?.append(contentsOf: internalProofs)
                internalProofs.forEach({ context.insert($0) })
            }
        }
    }
}

extension Array where Element == Mint {
    func setHidden(_ hidden: Bool, for mint: Mint) {
        guard self.contains(mint) else {
            // log...
            return
        }
        
        mint.hidden = hidden
         
        let visible = self.filter({ $0.hidden == false })
                          .sorted(by: { $0.userIndex ?? 0 < $1.userIndex ?? 0})
        
        mint.userIndex = hidden ? 10000 : visible.count
        for i in 0..<visible.count {
            visible[i].userIndex = i
        }
    }
}

// TODO: MOVE TO LIBRARY
extension CashuSwift.Token {
    func sum() -> Int {
        var amount = 0
        for prooflist in self.proofsByMint.values {
            for p in prooflist {
                amount += p.amount
            }
        }
        return amount
    }
}

extension CashuSwift.Keyset: @retroactive Equatable {
    public static func == (lhs: CashuSwift.Keyset, rhs: CashuSwift.Keyset) -> Bool {
        lhs.keys == rhs.keys
    }
}

extension MintRepresenting {
    ///Checks whether two mints are the same by making sure they have the same URL (for now) and share at least one keyset
    ///For use instead of `==` which checks `PersistentIdentifiers` only
    func matches(_ mint: MintRepresenting) -> Bool {
        self.url == mint.url && // TODO: remove to allow for changing DNS
        self.keysets.contains(where: mint.keysets.contains) // TODO: efficiency via Hashable conformance
    }
}

extension Array where Element == Proof {
    func sendable() -> [CashuSwift.Proof] {
        self.map { p in
            CashuSwift.Proof(p)
        }
    }
}

extension Array where Element == Proof {
    func setState(_ state: Proof.State) {
        self.forEach { $0.state = state }
    }
}

extension ProofRepresenting {
    func matches(_ proof: ProofRepresenting) -> Bool {
        self.keysetID == proof.keysetID && self.C == proof.C
    }
}
