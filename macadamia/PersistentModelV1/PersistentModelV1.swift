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
    
    // App group identifier - update this with your actual app group ID
    private static let appGroupID = "group.com.cypherbase.macadamia"
    
    private init() {
        let schema = Schema([
            Wallet.self,
            Proof.self,
            Mint.self,
            Event.self,
        ])
        
        // Try to use app group container
        var modelConfiguration: ModelConfiguration
        
        if let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: DatabaseManager.appGroupID) {
            logger.info("App group container found at: \(appGroupURL.path)")
            
            // Ensure Library/Application Support directory exists to avoid CoreData verbose errors
            let libraryURL = appGroupURL.appendingPathComponent("Library")
            let appSupportURL = libraryURL.appendingPathComponent("Application Support")
            if !FileManager.default.fileExists(atPath: appSupportURL.path) {
                do {
                    try FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
                    logger.info("Created Application Support directory in app group")
                } catch {
                    logger.error("Failed to create Application Support directory: \(error)")
                }
            }
            
            // Check if we need to migrate
            DatabaseManager.performMigrationIfNeeded(to: appGroupURL, appGroupID: DatabaseManager.appGroupID)
            
            modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                groupContainer: .identifier(DatabaseManager.appGroupID)
            )
            logger.info("Using app group database")
        } else {
            logger.warning("App group container not found, using default location")
            modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        }
        
        do {
            container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            logger.info("DatabaseManager initialized successfully")
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }
    
    private static func performMigrationIfNeeded(to appGroupURL: URL, appGroupID: String) {
        let migrationKey = "DatabaseMigratedToAppGroup"
        let userDefaults = UserDefaults(suiteName: appGroupID) ?? UserDefaults.standard
        
        // Check if already migrated
        if userDefaults.bool(forKey: migrationKey) {
            logger.info("Database already migrated to app group")
            return
        }
        
        // Find default database location
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, 
                                                       in: .userDomainMask).first else {
            logger.info("Could not find application support directory")
            return
        }
        
        let defaultStoreURL = appSupport.appendingPathComponent("default.store")
        let fileManager = FileManager.default
        
        // Check if default store exists
        if !fileManager.fileExists(atPath: defaultStoreURL.path) {
            logger.info("No existing database found at default location, starting fresh")
            userDefaults.set(true, forKey: migrationKey)
            return
        }
        
        // Perform migration
        do {
            logger.info("Starting database migration from: \(defaultStoreURL.path)")
            
            // SwiftData expects the database in Library/Application Support within the app group
            let libraryURL = appGroupURL.appendingPathComponent("Library")
            let appSupportURL = libraryURL.appendingPathComponent("Application Support")
            let targetStoreURL = appSupportURL.appendingPathComponent("default.store")
            
            // Create the directory structure if needed
            if !fileManager.fileExists(atPath: appSupportURL.path) {
                try fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
                logger.info("Created Application Support directory in app group")
            }
            
            // Copy the main store file
            if fileManager.fileExists(atPath: targetStoreURL.path) {
                try fileManager.removeItem(at: targetStoreURL)
            }
            try fileManager.copyItem(at: defaultStoreURL, to: targetStoreURL)
            logger.info("Copied database file to app group Application Support")
            
            // Copy associated files (.store-shm, .store-wal)
            let storeDir = defaultStoreURL.deletingLastPathComponent()
            let storeName = defaultStoreURL.deletingPathExtension().lastPathComponent
            
            for suffix in ["-shm", "-wal"] {
                let sourceFile = storeDir.appendingPathComponent("\(storeName).store\(suffix)")
                if fileManager.fileExists(atPath: sourceFile.path) {
                    let targetFile = appSupportURL.appendingPathComponent("\(storeName).store\(suffix)")
                    try? fileManager.copyItem(at: sourceFile, to: targetFile)
                    logger.info("Copied \(suffix) file")
                }
            }
            
            // Mark migration as complete
            userDefaults.set(true, forKey: migrationKey)
            userDefaults.synchronize()
            
            logger.info("Database migration completed successfully")
            
            // Create backup by renaming old files
            let backupURL = defaultStoreURL.appendingPathExtension("backup")
            try? fileManager.moveItem(at: defaultStoreURL, to: backupURL)
            logger.info("Created backup of original database")
            
        } catch {
            logger.error("Failed to migrate database: \(error)")
            // Don't mark as migrated so we can retry
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
        
        private var infoData: Data?
        private var infoLastUpdated = Date.now

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
        
        func balance(for unit: Unit) -> Int {
            self.proofs?.filter({ $0.unit == unit })
                        .filter({ $0.state == .valid })
                        .sum ?? 0
        }
        
        var displayName: String {
            self.nickName ?? self.url.host() ?? self.url.absoluteString
        }
        
        @MainActor
        var supportsMPP: Bool {
            if let infoData {
                guard let info = try? JSONDecoder().decode(CashuSwift.Mint.Info.self,
                                                           from: infoData) else { return false }
                return info.nuts?.nut15 != nil
            } else {
                return false // it might support MPP we don't know for sure so default to NO
            }
        }
        
        func loadInfo(invalidateCache: Bool = false) async throws -> CashuSwift.Mint.Info? {
            let oneDayAgo: Date = Date().addingTimeInterval(-86400)
            
            if let infoData {
                if infoLastUpdated < oneDayAgo || invalidateCache {
                    return try await updatedInfo()
                } else {
                    return try JSONDecoder().decode(CashuSwift.Mint.Info.self, from: infoData)
                }
            } else {
                return try await updatedInfo()
            }
            
            func updatedInfo() async throws -> CashuSwift.Mint.Info {
                let info = try await CashuSwift.loadMintInfo(from: CashuSwift.Mint(self))
                try await MainActor.run {
                    infoData = try JSONEncoder().encode(info)
                    infoLastUpdated = Date.now
                }
                return info
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
        private var bolt11MeltQuoteData: Data? // SwiftData is unable to serialize CashuSwift.Bolt11.MeltQuote so we do it ourselves
        
        var amount: Int?
        var expiration: Date?
        var longDescription: String?
        
        var proofs: [Proof]?
        
        var memo: String?
        
        var token: CashuSwift.Token?
        
        @Relationship(deleteRule: .noAction, inverse: \Mint.events)
        var mints: [Mint]?
        
        var preImage: String?
        
        // Persistence for NUT-08 blank outputs and secrets, blinding factors to allow for melt operation repeatability
        // another case where SwiftData refuses to store the "complex" codable struct
        // so we need to (de-) serialize it ourselves
        var blankOutputData: Data?
        
        var redeemed: Bool?
        
        var groupingID: UUID?
        
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
             preImage: String? = nil,
             redeemed: Bool? = nil,
             groupingID: UUID? = nil) {
            
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
            self.groupingID = groupingID
            self.preImage = preImage
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
        
        func tuple() -> (outputs: [CashuSwift.Output], blindingFactors: [String], secrets: [String]) {
            (outputs, blindingFactors, secrets)
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
        
        guard mint.keysets.allSatisfy(\.validID) else {
            throw macadamiaError.mintVerificationError("This mint is using invalid keyset IDs, you should not trust it.")
        }
        
        if let colliding = mints.filter({ $0.hidden == false }).keysetCollisions(with: mint) {
                         throw macadamiaError.mintVerificationError("This mint's keysets collide with \(colliding.map({ $0.displayName }).joined(separator: ", ")). It should not be used and might not be trustworthy.")
        }
        
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
    
    func keysetCollisions(with mint: MintRepresenting) -> [Mint]? {
        
        let mintIDs = Set(mint.keysets.map(\.keysetID))
        let mintNumerical = Set(try! mintIDs.map({ try CashuSwift.numericalRepresentation(of: $0) }))
        
        var collidingMints: [Mint] = []
        
        for existingMint in self {
            let existingIDs = Set(existingMint.keysets.map(\.keysetID))
            let existingNumerical = Set(try! existingIDs.map({ try CashuSwift.numericalRepresentation(of: $0) }))
            
            // Check for direct ID collision or numerical representation collision
            if !existingIDs.isDisjoint(with: mintIDs) || !existingNumerical.isDisjoint(with: mintNumerical) {
                collidingMints.append(existingMint)
            }
        }
        
        return collidingMints.isEmpty ? nil : collidingMints
    }
    
    func containsKeysetCollision(with mint: MintRepresenting) -> Bool {
        return keysetCollisions(with: mint) != nil
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
