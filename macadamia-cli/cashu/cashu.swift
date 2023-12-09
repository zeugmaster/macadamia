import Foundation
import CryptoKit
import secp256k1
import BIP39

class Wallet {
    
    enum WalletError: Error {
        case invalidMnemonicError
    }
    
    var database = Database.loadFromFile()
    
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
            let url = URL(string: "https://8333.space:3338")!
            let m = Mint(url: url, activeKeyset: nil, allKeysets: nil)
            self.database.mints.append(m)
            
            let url2 = URL(string: "https://testnut.cashu.space")!
            let m2 = Mint(url: url2, activeKeyset: nil, allKeysets: nil)
            self.database.mints.append(m2)
        }
        
        //1. get current keyset and compute legace ID
        
        for mint in self.database.mints {
            let activeKeyset = try await Network.loadKeyset(mintURL: mint.url, keysetID: nil)
            mint.activeKeyset = Keyset(legacyID: Mint.calculateKeysetID(keyset: activeKeyset),
                                       hexKeysetID: Mint.calculateHexKeysetID(keyset: activeKeyset),
                                       keys: activeKeyset)
            print("downloaded keyset from \(mint.url): \(mint.activeKeyset!.hexKeysetID)")
            
            guard let allKeysetIDs = try? await Network.loadAllKeysetIDs(mintURL: mint.url) else {
                print("could not get all keyset IDs")
                break
            }
            mint.allKeysets = []
            for id in allKeysetIDs.keysets {
                guard let keyset = try? await Network.loadKeyset(mintURL: mint.url, keysetID: id) else {
                    print("could not get keyset with \(id) of mint \(mint.url)")
                    break
                }
                let old = Mint.calculateKeysetID(keyset: keyset)
                let hex = Mint.calculateHexKeysetID(keyset: keyset)
                mint.allKeysets!.append(Keyset(legacyID: old,
                                               hexKeysetID: hex,
                                               keys: keyset))
                print("downloaded keyset with id \(id), calculated: \(hex), \(old)")
            }
            print("done!")
            print(mint.allKeysets?.last?.keys)
            self.database.saveToFile()
        }
        
        //2. load all keyset IDS
        
        
    }
    
    //MARK: - Mint
    //FIXME: this is propably unnecessary complexity using two completion handlers
    func mint(amount:Int,
              mint:Mint,
              prCompletion: @escaping (Result<PaymentRequest,Error>) -> Void,
              mintCompletion: @escaping (Result<String,Error>) -> Void) {
        //1. make GET req to the mint to receive lightning invoice
        // TODO: change to async await
        //TODO: remove hardcoded mint selection
        let urlString = mint.url.absoluteString + "/mint?amount=\(String(amount))"
        let url = URL(string: urlString)!
        print(url)
        let task = URLSession.shared.dataTask(with: url) {payload, response, error in
            if error == nil {
                let paymentRequest = try! JSONDecoder().decode(PaymentRequest.self, from: payload!)
                // TODO: needs to handle case where JSON could not be decoded
                prCompletion(.success(paymentRequest))
                
                //WAIT FOR INVOICE PAYED
                //2. after invoice is paid, send blinded outputs for signing and subsequent unblinding
                self.requestBlindedPromises(mint: mint, amount: amount, payReq: paymentRequest) { promises in
                    if promises.isEmpty == false {
                        //TODO: remove hardcoded mint selection
                        let proofs = unblindPromises(promises: promises, mintPublicKeys: mint.activeKeyset!.keys!)
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
    
    //MARK: - Send
    func sendTokens(mint:Mint, amount:Int, completion: @escaping (Result<String,Error>) -> Void) {
        // 1. retrieve tokens from database. if amounts match, serialize right away
        // if amounts dont match: split, serialize token for sending, add the rest back to db
        if let proofs = self.database.retrieveProofs(mint: mint, amount: amount) {
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
                let outputs = generateDeterministicOutputs(startIndex:self.database.secretDerivationCounter,
                                                           seed: self.database.seed!,
                                                           amounts: combined,
                                                           keyset: mint.activeKeyset!)
                
                requestSplit(mint: mint, forProofs: proofs, withOutputs: outputs) { result in
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
            let newOutputs = generateDeterministicOutputs(startIndex:self.database.secretDerivationCounter,
                                                          seed: self.database.seed!,
                                                          amounts: amounts,
                                                          keyset: keyset)
            
            //TODO: just taking the first proof.id breaks multimint token logic, needs fixing
            
            //same problem as above
            requestSplit(mint: mint!, forProofs: tokenlist[0].proofs, withOutputs: newOutputs) { result in
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
                if let invoiceAmount = PaymentRequest.satAmountFromInvoice(pr: invoice) {
                    let total = invoiceAmount + fee
                    if let proofs = self.database.retrieveProofs(mint: mint, amount: total) {
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
        
        self.database.saveToFile()
        
        let keyset = Keyset(legacyID: "I2yN+iRYfkzT", hexKeysetID: "0f0f0f0", keys: nil)
        let currentCounter = 0
        let (outputs, blindingFactors, secrets) = generateDeterministicOutputs(counter: currentCounter,
                                                                               seed: self.database.seed!,
                                                                               amounts: Array(repeating: 1, count: 10),
                                                                               keyset: keyset)
        
        do {
            let promises = try await Network.restoreRequest(mintURL: URL(string: "https://8333.space:3338")!, outputs: outputs)
            print(promises)
        } catch {
            print("something went wrong")
        }
        
        // check match outputs with returned promises
        // if return promises < generated outputs, restore should be done (?)
        
        //use async sequence to create n outputs per keysets and .cancel when m /restore requests come back empty
        
    }
    
    private func requestSplit(mint:Mint, forProofs:[Proof], withOutputs:[Output], completion: @escaping (Result<[Proof], Error>) -> Void) {
        //construct mint request payload and make http post req
        //transform outputs to outputs_JSON
        var outputs_json = [Output_JSON]()
        for o in withOutputs {
            outputs_json.append(Output_JSON(amount: o.amount, B_: o.output))
        }
        
        let splitReq = SplitRequest_JSON(proofs: forProofs, outputs: outputs_json)
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
            if let promisesJSON = try? JSONDecoder().decode(Promise_JSON_List.self, from: data!) {
                let promises = self.transformPromises(promises: promisesJSON.promises, originalOutputs: withOutputs)!
                print(promisesJSON)
                //TODO: remove hardcoded mint selection
                let proofs = unblindPromises(promises: promises, mintPublicKeys: mint.activeKeyset!.keys!)
                completion(.success(proofs))
            } else {
                print("could not decode promises from JSON: \(String(data: data!, encoding: .utf8) ?? "no data")")
            }
        }
        task.resume()
    }
    
    //TODO: to use or not to use
    func requestMint(amount:Int, completion: @escaping (PaymentRequest?) -> Void) {
        
    }
    
    func requestBlindedPromises(mint:Mint, amount:Int, payReq:PaymentRequest, completion: @escaping ([Promise]) -> Void) {
        //generates outputs (blindedMessages) to use when requesting
        let currentMintOutputs = generateDeterministicOutputs(startIndex:self.database.secretDerivationCounter,
                                                              seed: self.database.seed!,
                                                              amounts: splitIntoBase2Numbers(n: amount),
                                                              keyset: mint.activeKeyset!)
        var outputArray: [[String: Any]] = []
        for o in currentMintOutputs {
            var dict: [String: Any] = [:]
            dict["amount"] = o.amount
            // Ensure this is the correct string representation
            dict["B_"] = o.output
            outputArray.append(dict)
        }
        let containerDict = ["outputs": outputArray]
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: containerDict, options: [])
            //TODO: remove hardcoded mint selection
            if let url = URL(string: mint.url.absoluteString + "/mint?hash=" + payReq.hash) {
                //print(url)
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = jsonData

                let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
                    if let error = error {
                        print("Error: \(error)")
                        return
                    }
                    
                    if let jsonObject = try? JSONDecoder().decode(Promise_JSON_List.self, from: data!) {
                        completion(self.transformPromises(promises: jsonObject.promises, originalOutputs: currentMintOutputs)!)
                    } else {
                        print("could not decode promises from JSON: \(String(data: data!, encoding: .utf8) ?? "no data")")
                    }
                }
                task.resume()
            } else {
                print("URL for blinded output req invalid")
            }
        } catch {
            print("Error serializing JSON: \(error)")
        }
    }

    
    // TODO: not a very elegant solution, refactor
    func transformPromises(promises:[Promise_JSON], originalOutputs:[Output]) -> [Promise]? {
        var transformed = [Promise]()
        
        if promises.count != originalOutputs.count {
            print("transformPromises: couldn't attach r, x. supplied arrays have different lengths")
            return nil
        }
        
        for index in 0..<promises.count {
            let amount = promises[index].amount
            let p = promises[index].C_
            let id = promises[index].id
            let r = originalOutputs[index].blindingFactor
            let x = originalOutputs[index].secret
            transformed.append(Promise(amount: amount, promise: p, id: id, blindingFactor: r, secret: x))
        }
        return transformed
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


