import Foundation
import CryptoKit
import secp256k1
import BIP39
import OSLog

fileprivate var logger = Logger(subsystem: "zeugmaster.macadamia", category: "cashu")

enum WalletError: Error {
    case invalidMnemonicError
    case tokenDeserializationError(String)
    case tokenSerializationError(detail:String)
    case tokenStateCheckError(String)
    case unknownMintError //TODO: should not be treated like an error
    case missingMintKeyset
    case insufficientFunds(mintURL:String)
    case invalidInvoiceError
    case invalidSplitAmounts
    case restoreError(detail:String)
    case mintError(detail: String)
}

class Wallet {
    
    static let shared = Wallet()
    
    var database = Database.loadFromFile() //TODO: set to private
    
    private init() {
        if self.database.mnemonic == nil {
            let randomMnemonic = Mnemonic()
            self.database.mnemonic = randomMnemonic.phrase.joined(separator: " ")
            self.database.seed = String(bytes: randomMnemonic.seed)
            self.database.saveToFile()
            print("wallet initialized")
        }
    }
    
    func updateMints() async throws {
        
        //add default mint
        if self.database.mints.isEmpty {
            let url = URL(string: "https://mint.macadamia.cash")!
            try await addMint(with: url)
        }
        
        //if the wallet was already initialized we add macadamia mint anyway and make it first on the list, default
        if !database.mints.contains(where: {$0.url.absoluteString == "https://mint.macadamia.cash"}) {
            try await addMint(with: URL(string: "https://mint.macadamia.cash")!, at: 0)
        }
        
        for mint in self.database.mints {
            try await refreshMintDetails(mint: mint)
        }
        self.database.saveToFile()
    }
    
    /// Add a mint to the database of known mints
    /// - Parameter url: The URL of the mint
    func addMint(with url:URL, at index:Int? = nil) async throws {
        guard database.mints.contains(where: {$0.url == url}) == false else {
            return
        }
        let allKeysetIDs = try await Network.loadAllKeysetIDs(mintURL: url)
        let activeKeysetDict = try await Network.loadKeyset(mintURL: url, keysetID: nil)
        
        // patch to allow for mintInfo that we can not yet decode
        var mintInfo = try? await Network.mintInfo(mintURL: url)
        if mintInfo == nil {
            mintInfo = MintInfo(name: "", pubkey: "", version: "", contact: [[""]], nuts: [], parameter: [:])
        }
        
        var keysets = [Keyset]()
        var activeKeyset:Keyset?
        for id in allKeysetIDs.keysets {
            let keysetDict = try await Network.loadKeyset(mintURL: url, keysetID: id)
            let keyset = Keyset(id: id, keys: keysetDict, derivationCounter: 0)
            keysets.append(keyset)
            if keysetDict == activeKeysetDict {
                activeKeyset = keyset
            }
            print(id)
        }
        guard activeKeyset != nil else {
            throw WalletError.missingMintKeyset
        }
        if index == nil {
            database.mints.append(Mint(url: url,
                                       activeKeyset: activeKeyset!,
                                       allKeysets: keysets,
                                       info: mintInfo!))
        } else {
            var i = index!
            if !database.mints.indices.contains(i) {
                logger.warning("Passed out of bounds index to function .addMint, adding mint at index 0 instead")
                i = 0
            }
            database.mints.insert(Mint(url: url,
                                       activeKeyset: activeKeyset!,
                                       allKeysets: keysets,
                                       info: mintInfo!),
                                  at: i)
        }
        
        database.saveToFile()
    }
    
    func removeMint(with url:URL) {
        guard let mint = database.mints.first(where: { $0.url == url}) else {
            return
        }
        do {
            let (proofs, sum) = try database.retrieveProofs(from: mint, amount: nil)
            database.removeProofsFromValid(proofsToRemove: proofs)
            logger.debug("Wallet removed proofs of mint \"\(url.absoluteString)\" with a total sum of \(sum)")
        } catch {
            // nothing really to do here. if the mint didn't have proofs, nothing to remove
            logger.info("Wallet did not find proofs for mint \"\(url.absoluteString)\" when deleting.")
        }
        database.mints.removeAll(where: { $0 == mint })
        database.saveToFile()
    }
    
    private func refreshMintDetails(mint:Mint) async throws {
        let allKeysetIDs = try await Network.loadAllKeysetIDs(mintURL: mint.url)
        let activeKeysetDict = try await Network.loadKeyset(mintURL: mint.url, keysetID: nil)
        for id in allKeysetIDs.keysets {
            if mint.allKeysets.contains(where: {$0.id == id}) {
                continue //if the keyset is already known, skip to the next
            }
            //if it is NOT KNOWN, download it, add it, set its derivationCounter to 0
            let keysetDict = try await Network.loadKeyset(mintURL: mint.url, keysetID: id)
            let keyset = Keyset(id: id, keys: keysetDict, derivationCounter: 0)
            mint.allKeysets.append(keyset)
            if keysetDict == activeKeysetDict {
                mint.activeKeyset = keyset
            }
        }
    }
    
    //MARK: - BALANCE CHECK
    func balance(mint:Mint? = nil) -> Int {
        var sum:Int = 0
        if mint == nil {
            sum = database.proofs.reduce(0) { $0 + $1.amount }
        } else {
            for proof in database.proofs {
                if mint!.allKeysets.contains(where: {$0.id == proof.id}) {
                    sum += proof.amount
                }
            }
        }
        return sum
    }
    
    //MARK: - Mint
    func getQuote(from mint:Mint,for amount:Int) async throws -> QuoteRequestResponse {
        let quote = try await Network.requestQuote(for: amount, from: mint)
        return quote
    }
    
    func requestMint(from mint:Mint, for quote:QuoteRequestResponse, with amount:Int) async throws {
        let (outputs, bfs, secrets) = generateDeterministicOutputs(counter: mint.activeKeyset.derivationCounter,
                                                                   seed: self.database.seed!,
                                                                   amounts: splitIntoBase2Numbers(n: amount),
                                                                   keysetID: mint.activeKeyset.id)
        mint.activeKeyset.derivationCounter += outputs.count
        let promises = try await Network.requestSignature(mint: mint,
                                                          outputs: outputs,
                                                          amount: amount,
                                                          invoiceHash: quote.hash)
        let proofs = unblindPromises(promises: promises,
                                     blindingFactors: bfs,
                                     secrets: secrets,
                                     mintPublicKeys: mint.activeKeyset.keys)
        database.proofs.append(contentsOf: proofs)
        let t = Transaction(timeStamp: ISO8601DateFormatter().string(from: Date()),
                            unixTimestamp: Date().timeIntervalSince1970,
                            amount: amount,
                            type: .lightning,
                            invoice: quote.pr)
        database.transactions.insert(t, at: 0)
        database.saveToFile()
    }
    
    //MARK: Send
    //FIXME: terrible redundancy and lackluster control flow
    func sendTokens(from mint:Mint, amount:Int, memo:String?) async throws -> String {
        let (proofs, sum) = try database.retrieveProofs(from: mint, amount: amount)
        
        let proofsToSend:[Proof]
        
        if amount == sum {
            self.database.removeProofsFromValid(proofsToRemove: proofs)
            self.database.saveToFile()
            proofsToSend = proofs
        } else if amount < sum {
            let (new, change) = try await split(mint: mint, totalProofs: proofs, at: amount)
            database.proofs.append(contentsOf: change)
            proofsToSend = new
        } else {
            throw WalletError.unknownMintError
        }
        
        database.removeProofsFromValid(proofsToRemove: proofs)
        database.saveToFile()
        
        do {
            let token = try serializeProofs(proofs: proofsToSend, memo: memo)
            let t = Transaction(timeStamp: ISO8601DateFormatter().string(from: Date()),
                                unixTimestamp: Date().timeIntervalSince1970,
                                amount: amount * -1,
                                type: .cashu,
                                pending: true,
                                token: token,
                                proofs: proofsToSend)
            database.transactions.insert(t, at: 0)
            
            return token
        } catch {
            database.proofs.append(contentsOf: proofsToSend)
            print(proofsToSend)
            database.saveToFile()
            throw error
        }
    }
    
    //MARK: - Receive
    func receiveToken(tokenString:String) async throws {
        let parts = try deserializeToken(token: tokenString).token
        
        for part in parts {
            try await receiveTokenPart(part: part, of: tokenString)
        }
    }
    
    func receiveTokenPart(part:Token_JSON, of token:String) async throws {
        var amounts = [Int]()
        for p in part.proofs {
            amounts.append(p.amount)
        }
        guard let mint = database.mints.first(where: { $0.url.absoluteString == part.mint }) else {
            throw WalletError.unknownMintError
        }
        
        let keyset = mint.activeKeyset
        let (newOutputs, bfs, secrets) = generateDeterministicOutputs(counter: mint.activeKeyset.derivationCounter,
                                                                      seed: database.seed!,
                                                                      amounts: amounts,
                                                                      keysetID: keyset.id)
        mint.activeKeyset.derivationCounter += newOutputs.count
        let newPromises = try await Network.split(for: mint, proofs: part.proofs, outputs: newOutputs)
        let newProofs = unblindPromises(promises: newPromises,
                                        blindingFactors: bfs,
                                        secrets: secrets,
                                        mintPublicKeys: keyset.keys)
        self.database.proofs.append(contentsOf: newProofs)
        let t = Transaction(timeStamp: ISO8601DateFormatter().string(from: Date()),
                            unixTimestamp: Date().timeIntervalSince1970,
                            amount: newProofs.reduce(0){ $0 + $1.amount },
                            type: .cashu,
                            token: token,
                            proofs: newProofs)
        database.transactions.insert(t, at: 0)
        self.database.saveToFile()
    }
    
    //MARK: State check
    func check(mint:Mint, proofs:[Proof]) async throws -> (spendable:[Bool], pending:[Bool]) {
        if proofs.isEmpty { return ([], []) }
        let result = try await Network.check(mintURL: mint.url.absoluteURL, proofs: proofs)
        return (result.spendable, result.pending)
    }
    
    //MARK: - Melt
    /// Sends a request to the mint to melt proofs with the amount of the invoice plus a calculated fee.
    /// - Parameters:
    ///   - mint: the mint
    ///   - invoice: a Lightning Network invoice the mint is supposed to pay
    /// - Returns: a Boolean to indicate wether the invoice was paid successfully or not (e.g. due to a timeout)
    func melt(mint:Mint, invoice:String) async throws -> Bool {
        let invoiceAmount = try QuoteRequestResponse.satAmountFromInvoice(pr: invoice)
        let fee = try await Network.checkFee(mint: mint, invoice: invoice)
        
        let (proofs, _) = try database.retrieveProofs(from: mint, amount: invoiceAmount+fee)
        // if this fails error is thrown and execution ends proofs are discarded and original remains in DB
        
        let (new, change) = try await split(mint: mint, totalProofs: proofs, at: invoiceAmount+fee)
        // if this fails copied proofs are discarded but originals remain ->
        // if executes -> make sure new AND change proofs are written back to DB
        //        print("-------------->" + String(describing: proofs))
        database.removeProofsFromValid(proofsToRemove: proofs)
        database.proofs.append(contentsOf: change)
        database.saveToFile()
        
        do {
            let meltReqResponse = try await Network.melt(mint: mint, meltRequest: MeltRequest(proofs: new, pr: invoice))
            // TODO: doesn't properly handle errors
            if meltReqResponse.paid {
                let t = Transaction(timeStamp: ISO8601DateFormatter().string(from: Date()),
                                    unixTimestamp: Date().timeIntervalSince1970,
                                    amount: (invoiceAmount+fee) * -1,
                                    type: .lightning,
                                    invoice: invoice)
                database.transactions.insert(t, at: 0)
                return true
            } else {
                database.proofs.append(contentsOf: new) //putting the proofs back
                database.saveToFile()
                return false
            }
        } catch {
            database.proofs.append(contentsOf: new) //putting the proofs back
            database.saveToFile()
            return false
        }
    }
    
    
    //MARK: - Restore
    func restoreWithMnemonic(mnemonic:String) async throws {
        
        // if the new (old) mnemonic is invalid, return before causing any permanent damage
        guard let newMnemonic = try? BIP39.Mnemonic(phrase: mnemonic.components(separatedBy: .whitespacesAndNewlines)) else {
            throw WalletError.invalidMnemonicError
        }
        
        database = Database.loadFromFile()
        database.mnemonic = mnemonic
        database.seed = String(bytes: newMnemonic.seed)
        try await updateMints()
        database.proofs = []
        database.saveToFile() //overrides existing
        
        for mint in database.mints {
            for keyset in mint.allKeysets {
                let (proofs, _, lastMatchCounter) = await restoreProofs(mint: mint, keysetID: keyset.id, seed: self.database.seed!)
                print("last match counter: \(lastMatchCounter)")
                keyset.derivationCounter = lastMatchCounter
                // - "Very graceful /s"
                // - "no. but very efficient."
                if keyset.id == mint.activeKeyset.id {
                    mint.activeKeyset.derivationCounter = lastMatchCounter
                }
                let (spendable, _) = try await check(mint: mint, proofs: proofs) // ignores pending but should not
                guard spendable.count == proofs.count else {
                    throw WalletError.restoreError(detail: "could not filter: proofs, spendable need matching count")
                }
                var spendableProofs = [Proof]()
                for i in 0..<spendable.count {
                    if spendable[i] { spendableProofs.append(proofs[i]) }
                }
                self.database.proofs.append(contentsOf: spendableProofs)
                self.database.saveToFile()
            }
        }
    }
    
    private func restoreProofs(mint:Mint, keysetID:String, seed:String, batchSize:Int = 25) async -> (proofs:[Proof], totalRestored:Int, lastMatchCounter:Int) {
        
        guard let mintPubkeys = mint.allKeysets.first(where: {$0.id == keysetID})?.keys else {
            print("ERROR: could not find public keys for keyset: \(keysetID)")
            return ([], 0, 0) //FIXME: should be error handling instead
        }
        var proofs = [Proof]()
        var emtpyResponses = 0
        var currentCounter = 0
        var batchLastMatchIndex = 0
        let emptyRuns = 2
        while emtpyResponses < emptyRuns {
            print(keysetID)
            let (outputs, blindingFactors, secrets) = generateDeterministicOutputs(counter: currentCounter,
                                                                                   seed: self.database.seed!,
                                                                                   amounts: Array(repeating: 1, count: batchSize),
                                                                                   keysetID: keysetID)
            
            guard let restoreRespone = try? await Network.restoreRequest(mintURL: mint.url, outputs: outputs) else {
                print("unable to decode restoreResponse from Mint")
                return ([], 0, 0)
            }
            print(restoreRespone)
            currentCounter += batchSize
            batchLastMatchIndex = outputs.lastIndex(where: { oldOutput in
                restoreRespone.outputs.contains(where: {newOut in oldOutput.B_ == newOut.B_})
            }) ?? 0
            
            if restoreRespone.promises.isEmpty {
                emtpyResponses += 1
                continue
            } else {
                //reset counter to ensure they are CONSECUTIVE empty responses
                emtpyResponses = 0
            }
            var rs = [String]()
            var xs = [String]()
            for i in 0..<outputs.count {
                if restoreRespone.outputs.contains(where: {$0.B_ == outputs[i].B_}) {
                    rs.append(blindingFactors[i])
                    xs.append(secrets[i])
                }
            }
            
            let batchProofs = unblindPromises(promises: restoreRespone.promises, blindingFactors: rs, secrets: xs, mintPublicKeys: mintPubkeys)
            proofs.append(contentsOf: batchProofs)
            print("current counter: \(currentCounter), emptyruns: \(emptyRuns), batchlastmatch:\(batchLastMatchIndex)")
        }
        currentCounter -= emptyRuns * batchSize
        currentCounter += batchLastMatchIndex
        
        return (proofs, currentCounter, proofs.count)
    }
    
    //MARK: DRAIN
    ///Fetches all proofs for all known mints and returns them either one token per mint or as one big multi-mint token
    func drainWallet(multiMint:Bool) throws -> [(token:String, mintID:String, sum:Int)] {
        if multiMint {
            var parts = [Token_JSON]()
            var sum = 0
            for mint in database.mints {
                let proofs = try database.retrieveProofs(from: mint, amount: nil)
                parts.append(Token_JSON(mint: mint.url.absoluteString, proofs: proofs.proofs))
                sum += proofs.sum
            }
            let multiToken = try serializeToken(parts: parts, memo: "Wallet Drain")
            database.proofs = []
            database.saveToFile()
            return [(multiToken, "Multi Mint", sum)]
        } else {
            var tokens = [(String, String, Int)]()
            for mint in database.mints {
                let proofs = try database.retrieveProofs(from: mint, amount: nil)
                let token = try serializeProofs(proofs: proofs.proofs)
                tokens.append((token, mint.url.absoluteString, proofs.sum))
            }
            database.proofs = []
            database.saveToFile()
            return tokens
        }
    }
    
    //MARK: - HELPERS
    private func split(mint:Mint, totalProofs:[Proof], at amount:Int) async throws -> (new:[Proof], change:[Proof]) {
        let sum = totalProofs.reduce(0) { $0 + $1.amount }
        guard sum >= amount else {
            throw WalletError.invalidSplitAmounts
        }
        let toSend = splitIntoBase2Numbers(n: amount)
        let rest = splitIntoBase2Numbers(n: sum-amount)
        let combined = (toSend+rest).sorted()
        let keys = mint.activeKeyset.keys
        let (outputs, bfs, secrets) = generateDeterministicOutputs(counter: mint.activeKeyset.derivationCounter,
                                                                   seed: database.seed!,
                                                                   amounts: combined,
                                                                   keysetID: mint.activeKeyset.id)
        mint.activeKeyset.derivationCounter += outputs.count
        database.saveToFile()
        let newPromises = try await Network.split(for: mint, proofs: totalProofs, outputs: outputs)
        var newProofs = unblindPromises(promises: newPromises, blindingFactors: bfs, secrets: secrets, mintPublicKeys: keys)
        var sendProofs = [Proof]()
        for n in toSend {
            if let index = newProofs.firstIndex(where: {$0.amount == n}) {
                sendProofs.append(newProofs[index])
                newProofs.remove(at: index)
            }
        }
        return (sendProofs, newProofs)
    }
    
    //TODO: needs support for multi mint token creation
    private func serializeProofs(proofs: [Proof], memo:String? = nil) throws -> String {
        guard !proofs.isEmpty else { throw WalletError.tokenSerializationError(detail: "proofs cannot be empty")}
        guard let mint = database.mintForKeysetID(id: proofs[0].id) else {
            throw WalletError.tokenSerializationError(detail: "no mint found for keyset id: \(proofs[0].id)")
        }
        let token = Token_JSON(mint: mint.url.absoluteString, proofs: proofs)
        let tokenContainer = Token_Container(token: [token], memo: memo)
        let jsonData = try JSONEncoder().encode(tokenContainer)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        let safeString = try jsonString.encodeBase64UrlSafe()
        return "cashuA" + safeString
    }
    
    func serializeToken(parts:[Token_JSON], memo:String? = nil) throws -> String {
        let tokenContainer = Token_Container(token: parts, memo: memo)
        let jsonData = try JSONEncoder().encode(tokenContainer)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        let safeString = try jsonString.encodeBase64UrlSafe()
        return "cashuA" + safeString
    }
    
    func deserializeToken(token: String) throws -> Token_Container {
        // TODO: check prefix is cashuA
        var noPrefix = token
        guard token.contains("cashuA") else {
            throw WalletError.tokenDeserializationError("Token does not contain V3 prefix \"cashuA\"")
        }
        // needs to be in the right order to avoid only stripping cashu: and leaving //
        if token.hasPrefix("cashu://") {
            noPrefix = String(token.dropFirst("cashu://".count))
        }
        if token.hasPrefix("cashu:") {
            noPrefix = String(token.dropFirst("cashu:".count))
        }
        noPrefix = String(token.dropFirst(6))
        print(noPrefix)
        guard let jsonString = noPrefix.decodeBase64UrlSafe() else {
            throw WalletError.tokenDeserializationError("token could not be decoded from Base64")
        }
        print(jsonString)
        let jsonData = jsonString.data(using: .utf8)!
        guard let tokenContainer:Token_Container = try? JSONDecoder().decode(Token_Container.self,
                                                                             from: jsonData) else {
            throw WalletError.tokenDeserializationError("")
        }
        return tokenContainer
    }
    
    //FIXME: ONLY WORKS FOR SINGLE MINT TOKENS
    func checkTokenStatePending(token:String) async throws -> Bool {
        guard let deserializedToken = try deserializeToken(token: token).token.first else {
            throw WalletError.tokenDeserializationError("Token container does not contain a token.")
        }
        let proofs = deserializedToken.proofs
        guard let mintURL = URL(string: deserializedToken.mint) else {
            throw WalletError.tokenDeserializationError("could not decode mint URL from Token")
        }
        let result = try await Network.check(mintURL: mintURL, proofs: proofs)
        if result.spendable.contains(true) {
            return true
        } else {
            return false
        }
    }
    
    //Only legacy API way to check
    func checkTokenStateSpendable(for token:Token_JSON) async throws -> Bool {
        guard !token.proofs.isEmpty else {
            throw WalletError.tokenStateCheckError("token is empty")
        }
        guard let mintURL = URL(string: token.mint) else {
            throw WalletError.tokenDeserializationError("could not decode mint URL from Token")
        }
        let result = try await Network.check(mintURL: mintURL, proofs: token.proofs)
        if result.spendable.contains(true) {
            return true
        } else {
            return false
        }
    }

    private func splitIntoBase2Numbers(n: Int) -> [Int] {
        var remaining = n
        var result: [Int] = []
        while remaining > 0 {
            var powerOfTwo = 1
            while (powerOfTwo * 2) <= remaining {
                powerOfTwo *= 2
            }
            remaining -= powerOfTwo
            result.append(powerOfTwo)
        }
        return result
    }
}


