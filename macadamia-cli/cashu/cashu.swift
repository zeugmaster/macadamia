import Foundation
import CryptoKit
import secp256k1
import BIP39

class Wallet {
    
    enum WalletError: Error {
        case invalidMnemonicError
    }
    
    var database = Database.loadFromFile() //TODO: set to private
    
    init(database: Database = Database.loadFromFile()) {
        self.database = database
        
        if self.database.mnemonic == nil {
            let randomMnemonic = Mnemonic()
            self.database.mnemonic = randomMnemonic.phrase.joined(separator: " ")
            self.database.seed = String(bytes: randomMnemonic.seed)
            self.database.saveToFile()
        }
    }
    
    func updateMints() async throws {
        
        //add default mint
        if self.database.mints.isEmpty {
            let url = URL(string: "https://mint.zeugmaster.com:3338")!
            let m = Mint(url: url, activeKeyset: nil, allKeysets: nil)
            self.database.mints.append(m)
            
        }
                
        for mint in self.database.mints {
            guard let allKeysetIDs = try? await Network.loadAllKeysetIDs(mintURL: mint.url) else {
                print("could not get all keyset IDs")
                continue
            }
            guard let activeKeysetDict = try? await Network.loadKeyset(mintURL: mint.url, keysetID: nil) else {
                print("could not load current keyset of mint \(mint.url)")
                continue
            }
            print(allKeysetIDs)
            mint.allKeysets = []
            for id in allKeysetIDs.keysets {
                guard let keysetDict = try? await Network.loadKeyset(mintURL: mint.url, keysetID: id) else {
                    print("could not get keyset with \(id) of mint \(mint.url)")
                    continue
                }
                let keyset = Keyset(id: id, keys: keysetDict)
                mint.allKeysets!.append(keyset)
                if keysetDict == activeKeysetDict {
                    mint.activeKeyset = keyset
                }
            }
        }
        self.database.saveToFile()
        
    }
    
    //MARK: - Mint
    //FIXME: this is propably unnecessary complexity using two completion handlers
    func mint(amount:Int,
              mint:Mint,
              prCompletion: @escaping (Result<QuoteRequestResponse,Error>) -> Void,
              mintCompletion: @escaping (Result<String,Error>) -> Void) {
        //1. make GET req to the mint to receive lightning invoice
        // TODO: change to async await
        //TODO: remove hardcoded mint selection
        let urlString = mint.url.absoluteString + "/mint?amount=\(String(amount))"
        let url = URL(string: urlString)!
        print(url)
        let task = URLSession.shared.dataTask(with: url) {payload, response, error in
            if error == nil {
                let paymentRequest = try! JSONDecoder().decode(QuoteRequestResponse.self, from: payload!)
                // TODO: needs to handle case where JSON could not be decoded
                prCompletion(.success(paymentRequest))
                
                //WAIT FOR INVOICE PAYED
                //2. after invoice is paid, send blinded outputs for signing and subsequent unblinding
                self.requestBlindedPromises(mint: mint, amount: amount, payReq: paymentRequest) { (promises, bfs, secrets) in
                    if promises.isEmpty == false {
                        //TODO: remove hardcoded mint selection
                        
                        let proofs = unblindPromises(promises: promises, blindingFactors: bfs, secrets: secrets, mintPublicKeys: mint.activeKeyset!.keys!)
                        self.database.proofs.append(contentsOf: proofs)
                        self.database.secretDerivationCounter += promises.count //sloppy, should count outputs
                        self.database.saveToFile()
                        mintCompletion(.success("yay"))
                    } else {
                        print("empty promises lol")
                    }
                }
            } else {
                //needs much more robust error handling
                prCompletion(.failure(error!))
            }
        }
        task.resume()
    }
    
    func getQuote(from mint:Mint,for amount:Int) async throws -> QuoteRequestResponse {
        let quote = try await Network.requestQuote(for: amount, from: mint)
        return quote
    }
    
    func requestMint(from mint:Mint, for quote:QuoteRequestResponse, with amount:Int) async throws {
        let (outputs, bfs, secrets) = generateDeterministicOutputs(counter: self.database.secretDerivationCounter, seed: self.database.seed!, amounts: splitIntoBase2Numbers(n: amount), keysetID: mint.activeKeyset!.id)
        let promises = try await Network.requestSignature(mint: mint, outputs: outputs, amount: amount, invoiceHash: quote.hash)
        let proofs = unblindPromises(promises: promises, blindingFactors: bfs, secrets: secrets, mintPublicKeys: mint.activeKeyset!.keys!)
        database.proofs.append(contentsOf: proofs)
        database.secretDerivationCounter += proofs.count
        database.saveToFile()
    }
    
    //func getQuote(amount:Int, mint:Mint) async throws -> PostMintRequest
    
    //MARK: - Send
    func sendTokens(mint:Mint, amount:Int, completion: @escaping (Result<String,Error>) -> Void) {
        // 1. retrieve tokens from database. if amounts match, serialize right away
        // if amounts dont match: split, serialize token for sending, add the rest back to db
        if let proofs = self.database.retrieveProofs(from: mint, amount: amount) {
            print("total proofs collected: \(proofs)")
            var totalInProofs = 0
            for proof in proofs {
                totalInProofs += proof.amount
            }
            if totalInProofs == amount {
                let tokenstring = serializeProofs(proofs: proofs)
                self.database.removeProofsFromValid(proofsToRemove: proofs)
                self.database.saveToFile()
                completion(.success(tokenstring))
            } else if totalInProofs > amount {
                print("need to split for send ...")
                //determine split amounts
                let toSend = splitIntoBase2Numbers(n: amount)
                let rest = splitIntoBase2Numbers(n: totalInProofs-amount)
                //request split
                //TODO: sort array of amounts in ascending order to prevent privacy leak
                let combined = toSend + rest
                let (outputs, blindingfactors, secrets) = generateDeterministicOutputs(counter: self.database.secretDerivationCounter, seed: self.database.seed!, amounts: combined, keysetID: mint.activeKeyset!.id)
                requestSplit(mint: mint, forProofs: proofs, withOutputs: outputs,blindingFactors: blindingfactors, secrets: secrets) { result in
                    switch result {
                    case .success(var combinedProofs):
                        print("total returned after split: \(combinedProofs)")
                        //assign correctly to toSend and rest
                        var sendProofs = [Proof]()
                        for n in toSend {
                            if let index = combinedProofs.firstIndex(where: {$0.amount == n}) {
                                sendProofs.append(combinedProofs[index])
                                combinedProofs.remove(at: index)
                            }
                        }
                        self.database.removeProofsFromValid(proofsToRemove: proofs)
                        //serialize toSend and save rest
                        let token = self.serializeProofs(proofs: sendProofs)
                        print("change proofs, written to db: \(combinedProofs)")
                        print("sent proofs: \(sendProofs)")
                        self.database.proofs.append(contentsOf: combinedProofs)
                        self.database.secretDerivationCounter += outputs.count
                        self.database.saveToFile()
                                                
                        completion(.success(token))
                    case .failure(let splitError):
                        completion(.failure(splitError))
                    }
                }
            } //no need to check for too few proofs, function can only return enough or none at all
        } else {
            print("did not retrieve any proofs")
        }
    }
    
    //MARK: - Receive
    func receiveTokens(tokenString:String, completion: @escaping (Result<Void,Error>) -> Void) {
        //deserialise token
        if let tokenlist = self.deserializeToken(token:tokenString) {
            var amounts = [Int]()
            for p in tokenlist[0].proofs {
                amounts.append(p.amount)
            }
            
            let mint = self.database.mintForKeysetID(id: tokenlist[0].proofs[0].id)
            let keyset = mint!.activeKeyset!
            let (newOutputs, bfs, secrets) = generateDeterministicOutputs(counter: self.database.secretDerivationCounter,
                                                          seed: database.seed!,
                                                          amounts: amounts,
                                                          keysetID: keyset.id)
            //TODO: just taking the first proof.id breaks multimint token logic, needs fixing
            
            //same problem as above
            requestSplit(mint: mint!, forProofs: tokenlist[0].proofs, withOutputs: newOutputs, blindingFactors: bfs, secrets: secrets) { result in
                switch result {
                case .success(let newProofs):
                    //TODO: remove hardcoded mint selection
                    self.database.proofs.append(contentsOf: newProofs)
                    self.database.secretDerivationCounter += newProofs.count
                    self.database.saveToFile()
                    completion(.success(()))
                    print("saved new proofs to db")
                case .failure(let error):
                    completion(.failure(error))
                    print("split request for receive was unsuccessful error: \(error)")
                }
            }
        } else {
            print("could not deserialise token")
            //completion(.failure())
        }
    }
    
    //MARK: - Melt
    func melt(mint:Mint, invoice:String, completion: @escaping (Result<Void,Error>) -> Void) {
        // 1. check fee (maybe again)
        // 2. determine invoice amnt
        // 3. retrieve proofs from db for amount + fee
        // 4. TODO: implement change proofs for melting, FIX HORRIBLE NESTING
        
        Network.checkFee(mint: mint, invoice: invoice) { checkFeeResult in
            switch checkFeeResult {
            case .success(let fee):
                if let invoiceAmount = QuoteRequestResponse.satAmountFromInvoice(pr: invoice) {
                    let total = invoiceAmount + fee
                    if let proofs = self.database.retrieveProofs(from: mint, amount: total) {
                        Network.meltRequest(mint: mint, meltRequest: MeltRequest(proofs: proofs, pr: invoice)) { meltRequestResult in
                            switch meltRequestResult {
                            case .success():
                                self.database.removeProofsFromValid(proofsToRemove: proofs)
                                self.database.saveToFile()
                                completion(.success(()))
                            case .failure(let meltError):
                                completion(.failure(meltError))
                            }
                        }
                    } else {
                        print("did not receive (enough) proofs for melting tokens")
                    }
                } else {
                    //FIXME: needs correct error type
                    completion(.failure(NetworkError.decodingError))
                }
            case .failure(let error):
                print(error)
            }
        }
    }
    
    // valid mnemo for testing = mango quality holiday shuffle cereal moment hood lonely render woman come limit
    
    //MARK: - Restore
    func restoreWithMnemonic(mnemonic:String) async throws {
        
        // reset database
        guard let newMnemonic = try? BIP39.Mnemonic(phrase: mnemonic.components(separatedBy: .whitespacesAndNewlines)) else {
            throw WalletError.invalidMnemonicError
        }
        
        self.database = Database(mnemonic: mnemonic, secretDerivationCounter: 0)
        self.database.seed = String(bytes: newMnemonic.seed)
        self.database.mints.append(Mint(url: URL(string: "https://mint.zeugmaster.com:3338")!, activeKeyset: nil, allKeysets: nil))
        try await updateMints()
        self.database.saveToFile() //overrides existing
        for mint in database.mints {
            for keyset in mint.allKeysets! {
                let responsetuple = await restoreProofs(mint: mint, keysetID: keyset.id, seed: self.database.seed!)
                self.database.proofs.append(contentsOf: responsetuple.proofs)
                self.database.secretDerivationCounter = responsetuple.lastMatchCounter
                self.database.saveToFile()
                print(responsetuple)
            }
        }
    }
    
    private func restoreProofs(mint:Mint, keysetID:String, seed:String, batchSize:Int = 10) async -> (proofs:[Proof], totalRestored:Int, lastMatchCounter:Int) {
        
        guard let mintPubkeys = mint.allKeysets?.first(where: {$0.id == keysetID})?.keys else {
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
        
    private func requestSplit(mint:Mint,
                              forProofs:[Proof],
                              withOutputs:[Output],
                              blindingFactors:[String],
                              secrets:[String],
                              completion: @escaping (Result<[Proof], Error>) -> Void) {
        
        let splitReq = SplitRequest_JSON(proofs: forProofs, outputs: withOutputs)
        let payload = try! JSONEncoder().encode(splitReq)
        
        let prettyEncoder = JSONEncoder()
        prettyEncoder.outputFormatting = .prettyPrinted

        let pretty = try! prettyEncoder.encode(splitReq)
        print(String(data: pretty, encoding: .utf8)!)
        //TODO: remove hardcoded mint selection
        let url = URL(string: mint.url.absoluteString + "/split")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload

        let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
            if let error = error {
                print("Error: \(error)")
                return
            }
            if let promisesJSON = try? JSONDecoder().decode(SignatureRequestResponse.self, from: data!) {
                print(promisesJSON)
                //TODO: remove hardcoded mint selection
                let proofs = unblindPromises(promises: promisesJSON.promises, blindingFactors: blindingFactors, secrets: secrets, mintPublicKeys: mint.activeKeyset!.keys!)
                completion(.success(proofs))
            } else {
                print("could not decode promises from JSON: \(String(data: data!, encoding: .utf8) ?? "no data")")
            }
        }
        task.resume()
    }
    
    //TODO: to use or not to use
    func requestMint(amount:Int, completion: @escaping (QuoteRequestResponse?) -> Void) {
        
    }
    
    func requestBlindedPromises(mint:Mint, amount:Int, payReq:QuoteRequestResponse, completion: @escaping (([Promise], blindingFactors:[String], secrets:[String])) -> Void) {

        let (outputArray, bfs, secrets)  = generateDeterministicOutputs(counter: self.database.secretDerivationCounter, seed: self.database.seed!, amounts: splitIntoBase2Numbers(n: amount), keysetID: mint.activeKeyset!.id)
        let mintrequest = PostMintRequest(outputs: outputArray)
        guard let payload = try? JSONEncoder().encode(mintrequest) else {
            print("could not construct payload")
            return
        }
        guard let url = URL(string: mint.url.absoluteString + "/mint?hash=" + payReq.hash) else {
            print("could not construct URL for PostMintRequest")
            return
        }
        var httpReq = URLRequest(url: url)
        httpReq.httpMethod = "POST"
        httpReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        httpReq.httpBody = payload
        
        let task = URLSession.shared.dataTask(with: httpReq) { data, response, error in
            if error != nil {
                print(error!)
            }
            if let decoded = try? JSONDecoder().decode(SignatureRequestResponse.self, from: data!) {
            completion((decoded.promises, bfs, secrets))
            }
            
        }
        task.resume()
    }

    //MARK: - HELPERS
    func serializeProofs(proofs: [Proof]) -> String {
        //TODO: remove hardcoded mint selection
        let mint = database.mintForKeysetID(id: proofs[0].id)!
        let token = Token_JSON(mint: mint.url.absoluteString, proofs: proofs)
        let tokenContainer = Token_Container(token: [token], memo: "...fiat esse delendam.")
        let jsonData = try! JSONEncoder().encode(tokenContainer)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        let safeString = Base64FS.encodeString(str: jsonString)
        return "cashuA" + safeString
    }
    func deserializeToken(token: String) -> [Token_JSON]? {
        let noPrefix = token.dropFirst(6)
        let jsonString = Base64FS.decodeString(str: String(noPrefix))
        print(jsonString)
        let jsonData = jsonString.data(using: .utf8)!
        if let tokenContainer:Token_Container = try? JSONDecoder().decode(Token_Container.self, from: jsonData) {
            return tokenContainer.token
        } else {
            print("could not deserialise token")
            return nil
        }
    }

    // HELPER FUNCTIONS:

    func splitIntoBase2Numbers(n: Int) -> [Int] {
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


