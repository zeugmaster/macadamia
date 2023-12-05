import Foundation
import CryptoKit
import secp256k1

struct PaymentRequest: Codable {
    let pr: String
    let hash: String
}

struct Output_JSON: Codable {
    let amount: Int
    let B_: String
}
struct Token_Container: Codable {
    let token: [Token_JSON]
    let memo: String?
}
struct Token_JSON: Codable {
    let mint: String
    var proofs: [Proof]
}

class Wallet {
    var database = Database.loadFromFile()
    
    
    func updateMints(completion: @escaping (Result<Void,Error>) -> Void) {
        //load from database
        // TODO: replace hardcoded static mints
        if self.database.mints.isEmpty {
            let m = Mint(url: URL(string: "https://8333.space:3338")!, keySets: [])
            self.database.mints.append(m)
        }
        
        for mint in database.mints {
            Network.loadCurrentKeyset(fromMint: mint) { result in
                switch result {
                case .success(let dict):
                    let id = Mint.calculateKeysetID(keyset: dict)
                    let keyset = Keyset(keysetID: id, keys: dict)
                    mint.keySets = [keyset]
                    print("successfully downloaded keyset with ID: \(id)")
                case .failure(let error):
                    print("could not load keyset for \(mint) because of \(error)")
                }
            }
        }
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
                        let proofs = unblindPromises(promises: promises, mintPublicKeys: mint.keySets[0].keys!)
                        self.database.proofs.append(contentsOf: proofs)
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
                let outputs = generateOutputs(amounts: toSend+rest)
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
                        self.database.saveToFile()
                        completion(.success(token))
                        //run completion handler accordingly
                    case .failure(let splitError):
                        completion(.failure(splitError))
                    }
                }
            } //TODO: add guard for unlikely case of too few tokens being returned
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
            let newOutputs = generateOutputs(amounts: amounts)
            
            //TODO: just taking the first proof.id breaks multimint token logic, needs fixing
            let mint = self.database.mintForKeysetID(id: tokenlist[0].proofs[0].id)
            //same problem as above
            requestSplit(mint: mint!, forProofs: tokenlist[0].proofs, withOutputs: newOutputs) { result in
                switch result {
                case .success(let newProofs):
                    //TODO: remove hardcoded mint selection
                    self.database.proofs.append(contentsOf: newProofs)
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
    func melt(amount:Int, completion: @escaping (Result<Void,Error>) -> Void) {
        
    }
    
    struct SplitRequest_JSON: Codable {
        let proofs:[Proof]
        let outputs:[Output_JSON]
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
                let proofs = unblindPromises(promises: promises, mintPublicKeys: mint.keySets[0].keys!)
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
        let currentMintOutputs = generateOutputs(amounts: splitIntoBase2Numbers(n: amount))
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

    struct Promise_JSON: Codable {
        let id: String
        let amount: Int
        let C_: String
    }
    struct Promise_JSON_List: Codable {
        let promises: [Promise_JSON]
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


