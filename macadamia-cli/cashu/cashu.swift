import Foundation
import CryptoKit
import secp256k1
import BIP39

class Wallet {
    
    static let shared = Wallet()
    
    enum WalletError: Error {
        case invalidMnemonicError
        case tokenDeserializationError
        case tokenSerializationError(detail:String)
        case unknownMintError //TODO: should not be treated like an error
        case missingMintKeyset
        case insufficientFunds(mint:Mint)
        case invalidInvoiceError
        case invalidSplitAmounts
        case restoreError(detail:String)
    }
    
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
            let url = URL(string: "https://8333.space:3338")!
            try await addMint(with: url)
        }
                
        for mint in self.database.mints {
            try await refreshMintDetails(mint: mint)
        }
        self.database.saveToFile()
    }
    
    func addMint(with url:URL) async throws {
        guard database.mints.contains(where: {$0.url == url}) == false else {
            return
        }
        let allKeysetIDs = try await Network.loadAllKeysetIDs(mintURL: url)
        let activeKeysetDict = try await Network.loadKeyset(mintURL: url, keysetID: nil)
        let mintInfo = try await Network.mintInfo(mintURL: url)
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
        database.mints.append(Mint(url: url,
                                   activeKeyset: activeKeyset!,
                                   allKeysets: keysets,
                                   info: mintInfo))
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
    func balance(mint:Mint?) -> Int {
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
        let promises = try await Network.requestSignature(mint: mint, 
                                                          outputs: outputs,
                                                          amount: amount,
                                                          invoiceHash: quote.hash)
        let proofs = unblindPromises(promises: promises, 
                                     blindingFactors: bfs,
                                     secrets: secrets,
                                     mintPublicKeys: mint.activeKeyset.keys)
        database.proofs.append(contentsOf: proofs)
        mint.activeKeyset.derivationCounter += proofs.count
        database.saveToFile()
    }
    
    //MARK: Send
    func sendTokens(from mint:Mint, amount:Int) async throws -> String {
        let (proofs, sum) = try database.retrieveProofs(from: mint, amount: amount)
        if amount == sum {
            self.database.removeProofsFromValid(proofsToRemove: proofs)
            self.database.saveToFile()
            return try serializeProofs(proofs: proofs)
        } else if amount < sum {
            let (new, change) = try await split(mint: mint, totalProofs: proofs, at: amount)
            database.removeProofsFromValid(proofsToRemove: proofs)
            database.proofs.append(contentsOf: change)
            mint.activeKeyset.derivationCounter += (new.count + change.count)
            database.saveToFile()
            return try serializeProofs(proofs: new)
        } else {
            throw WalletError.unknownMintError
        }
    }
    
    //MARK: - Receive
    func receiveToken(tokenString:String) async throws {
        let tokenlist = try self.deserializeToken(token: tokenString)
        var amounts = [Int]()
        for p in tokenlist[0].proofs {
            amounts.append(p.amount)
        }
        guard let mint = self.database.mintForKeysetID(id: tokenlist[0].proofs[0].id) else {
            throw WalletError.unknownMintError
        }
        
        let keyset = mint.activeKeyset
        let (newOutputs, bfs, secrets) = generateDeterministicOutputs(counter: mint.activeKeyset.derivationCounter,
                                                                      seed: database.seed!,
                                                                      amounts: amounts,
                                                                      keysetID: keyset.id)
        
        let newPromises = try await Network.split(for: mint, proofs: tokenlist[0].proofs, outputs: newOutputs)
        let newProofs = unblindPromises(promises: newPromises, 
                                        blindingFactors: bfs,
                                        secrets: secrets,
                                        mintPublicKeys: keyset.keys)
        self.database.proofs.append(contentsOf: newProofs)
        mint.activeKeyset.derivationCounter += newProofs.count
        self.database.saveToFile()
    }
    
    //MARK: State check
    func check(mint:Mint, proofs:[Proof]) async throws -> (spendable:[Bool], pending:[Bool]) {
        if proofs.isEmpty {return ([], [])}
        let result = try await Network.check(mint: mint, proofs: proofs)
        return (result.spendable, result.pending)
    }
    
    //MARK: - Melt
    func melt(mint:Mint, invoice:String) async throws -> Bool {
        let invoiceAmount = try QuoteRequestResponse.satAmountFromInvoice(pr: invoice)
        let fee = try await Network.checkFee(mint: mint, invoice: invoice)
        let (proofs, _) = try database.retrieveProofs(from: mint, amount: invoiceAmount)
        let (new, change) = try await split(mint: mint, totalProofs: proofs, at: invoiceAmount+fee)
        database.removeProofsFromValid(proofsToRemove: proofs)
        let meltReqResponse = try await Network.melt(mint: mint, meltRequest: MeltRequest(proofs: new, pr: invoice))
        database.proofs.append(contentsOf: change)
        if meltReqResponse.paid {
            database.saveToFile()
            return true
        } else {
            database.proofs.append(contentsOf: new) //putting the proofs back
            database.saveToFile()
            return false
        }
    }
    
        
    //MARK: - Restore
    func restoreWithMnemonic(mnemonic:String) async throws {
        
        // reset database
        guard let newMnemonic = try? BIP39.Mnemonic(phrase: mnemonic.components(separatedBy: .whitespacesAndNewlines)) else {
            throw WalletError.invalidMnemonicError
        }
        
        self.database = Database.loadFromFile()
        database.mnemonic = mnemonic
        self.database.seed = String(bytes: newMnemonic.seed)
        try await addMint(with: URL(string: "https://8333.space:3338")!)
        try await updateMints()
        self.database.saveToFile() //overrides existing
        for mint in database.mints {
            for keyset in mint.allKeysets {
                let (proofs, totalRestored, lastMatchCounter) = await restoreProofs(mint: mint, keysetID: keyset.id, seed: self.database.seed!)
                keyset.derivationCounter = lastMatchCounter
                let (spendable, pending) = try await check(mint: mint, proofs: proofs)
                guard spendable.count == proofs.count else {
                    throw WalletError.restoreError(detail: "could not filter: proofs, spendable need matching lenght")
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
    
    private func restoreProofs(mint:Mint, keysetID:String, seed:String, batchSize:Int = 10) async -> (proofs:[Proof], totalRestored:Int, lastMatchCounter:Int) {
        
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
            //currentcounter needs to be correct
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
    
    private func serializeProofs(proofs: [Proof]) throws -> String {
        guard let mint = database.mintForKeysetID(id: proofs[0].id) else {
            throw WalletError.tokenSerializationError(detail: "no mint found for keyset id: \(proofs[0].id)")
        }
        let token = Token_JSON(mint: mint.url.absoluteString, proofs: proofs)
        let tokenContainer = Token_Container(token: [token], memo: "...fiat esse delendam.")
        let jsonData = try JSONEncoder().encode(tokenContainer)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        let safeString = Base64FS.encodeString(str: jsonString)
        return "cashuA" + safeString
    }
    
    private func deserializeToken(token: String) throws -> [Token_JSON] {
        //TODO: check for more cases where invalid
        let noPrefix = token.dropFirst(6)
        let jsonString = Base64FS.decodeString(str: String(noPrefix))
        print(jsonString)
        let jsonData = jsonString.data(using: .utf8)!
        guard let tokenContainer:Token_Container = try? JSONDecoder().decode(Token_Container.self, from: jsonData) else {
            throw WalletError.tokenDeserializationError
        }
        return tokenContainer.token
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


