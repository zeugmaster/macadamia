import Foundation
import CryptoKit
import secp256k1

struct Mint {
    let url: URL
    let keySet: Dictionary<String,String>
}
struct PaymentRequest: Codable {
    let pr: String
    let hash: String
}

struct Output_JSON: Codable {
    let amount: Int
    let B_: String
}
struct Promise {
    let amount: Int
    let promise: String
    let id: String
    let blindingFactor:String
    let secret: String
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
    var knownMints = [Mint]()
    var tokenStore = TokenStore()
    
    init() {
        
    }

    //FIXME: not being able to decode json from one mint (e.g. because its offline) crashes program
    func updateMints(completion: @escaping ([Mint]) -> Void) {
        //load from database
        // TODO: replace hardcoded static mints
        let mintURLs = [URL(string: "https://8333.space:3338")!]
        
        knownMints = []
        @Sendable func fetchAllData() async {
            for url in mintURLs {
                do {
                    let (data, _) = try await URLSession.shared.data(from: url.appending(path: "keys"))
                    // Use the fetched data
                    let json = try JSONSerialization.jsonObject(with: data, options: []) as! [String: String]
                    knownMints.append(Mint(url: url, keySet: json))
                } catch {
                    // TODO: needs real error handling
                    print("Mint keyset download: Error fetching data: \(error)")
                }
            }
            completion(knownMints)
        }
        Task {
            await fetchAllData()
        }
    }
    //MARK: - Mint
    //FIXME: this is propably unnecessary complexity using two completion handlers
    func mint(amount:Int,
              prCompletion: @escaping (Result<PaymentRequest,Error>) -> Void,
              mintCompletion: @escaping (Result<String,Error>) -> Void) {
        //1. make GET req to the mint to receive lightning invoice
        // TODO: change to async await
        //TODO: remove hardcoded mint selection
        let urlString = knownMints[0].url.absoluteString + "/mint?amount=\(String(amount))"
        let url = URL(string: urlString)!
        print(url)
        let task = URLSession.shared.dataTask(with: url) {payload, response, error in
            if error == nil {
                let paymentRequest = try! JSONDecoder().decode(PaymentRequest.self, from: payload!)
                // TODO: needs to handle case where JSON could not be decoded
                prCompletion(.success(paymentRequest))
                
                //WAIT FOR INVOICE PAYED
                //2. after invoice is paid, send blinded outputs for signing and subsequent unblinding
                self.requestBlindedPromises(amount: amount, payReq: paymentRequest) { promises in
                    if promises.isEmpty == false {
                        //TODO: remove hardcoded mint selection
                        let proofs = unblindPromises(promises: promises, mintPublicKeys: self.knownMints[0].keySet)
                        self.tokenStore.addToken(token: Token_JSON(mint: self.knownMints[0].url.absoluteString, proofs: proofs))
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
    func sendTokens(amount:Int, completion: @escaping (Result<String,Error>) -> Void) {
        // 1. retrieve tokens from database. if amounts match, serialize right away
        // if amounts dont match: split, serialize token for sending, add the rest back to db
        if let proofs = self.tokenStore.retrieveProofsForAmount(amount: amount) {
            var totalInProofs = 0
            for proof in proofs {
                totalInProofs += proof.amount
            }
            print(proofs)
            if totalInProofs == amount {
                let tokenstring = serializeProofs(proofs: proofs)
                completion(.success(tokenstring))
            } else if totalInProofs > amount {
                print("need to split for send ...")
                //determine split amounts
                let toSend = splitIntoBase2Numbers(n: amount)
                let rest = splitIntoBase2Numbers(n: totalInProofs-amount)
                //request split
                //TODO: sort array of amounts in ascending order to prevent privacy leak
                let outputs = generateOutputs(amounts: toSend+rest)
                requestSplit(forProofs: proofs, withOutputs: outputs) { result in
                    switch result {
                    case .success(var combinedProofs):
                        //assign correctly to toSend and rest
                        var sendProofs = [Proof]()
                        for n in toSend {
                            if let index = combinedProofs.firstIndex(where: {$0.amount == n}) {
                                sendProofs.append(combinedProofs[index])
                                combinedProofs.remove(at: index)
                            }
                        }
                        //serialize toSend and save rest
                        let token = self.serializeProofs(proofs: sendProofs)
                        //FIXME: hardcoded mint must be replaced
                        self.tokenStore.addToken(token: Token_JSON(mint: "well", proofs: combinedProofs))
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
            //TODO: remove hardcoded mint selection
            requestSplit(forProofs: tokenlist[0].proofs, withOutputs: newOutputs) { result in
                switch result {
                case .success(let newProofs):
                    //TODO: remove hardcoded mint selection
                    self.tokenStore.addToken(token: Token_JSON(mint: self.knownMints[0].url.absoluteString, proofs: newProofs))
                    completion(.success(()))
                    print("saved new proofs to db")
                case .failure(let error):
                    completion(.failure(error))
                    print("split request for receive was unsuccessful error: \(error)")
                }
            }
        } else {
            
        }
    }
    
    //MARK: - Melt
    func melt(amount:Int, completion: @escaping (Result<Void,Error>) -> Void) {
        
    }
    
    struct SplitRequest_JSON: Codable {
        let proofs:[Proof]
        let outputs:[Output_JSON]
    }
    private func requestSplit(forProofs:[Proof], withOutputs:[Output], completion: @escaping (Result<[Proof], Error>) -> Void) {
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
        let url = URL(string: self.knownMints[0].url.absoluteString + "/split")!
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
                let promises = self.transformPromises(promises: promisesJSON.promises, originalOutputs: withOutputs)
                print(promisesJSON)
                //TODO: remove hardcoded mint selection
                let proofs = unblindPromises(promises: promises, mintPublicKeys: self.knownMints[0].keySet)
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

    // 3. pay invoice

    // ...
    
    //MARK: -
    // 4. MINT TOKENS aka request blinded signatures:
    // 4a generate array of outputs with amounts adding up to invoice payed ✔
    // 4b blind outputs ✔
    // 4c construct JSON with blinded outputs and amounts ✔
    // 4d make post req to mint with payment hash in url and JSON as payload ✔
    // 4e read JSON data to object and transform by changind key strings to objects, adding blindingfactors
    // 4f store list of blinded outputs for later unblinding
    
    func requestBlindedPromises(amount:Int, payReq:PaymentRequest, completion: @escaping ([Promise]) -> Void) {
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
            if let url = URL(string: knownMints[0].url.absoluteString + "/mint?hash=" + payReq.hash) {
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
                        completion(self.transformPromises(promises: jsonObject.promises, originalOutputs: currentMintOutputs))
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
    func transformPromises(promises:[Promise_JSON], originalOutputs:[Output]) -> [Promise] {
        var transformed = [Promise]()
        for promise in promises {
            let pK = try! secp256k1.Signing.PublicKey(dataRepresentation: promise.C_.bytes, format: .compressed)
            let blindingFactor = originalOutputs.first(where: { $0.amount == promise.amount})!.blindingFactor
            let bfKey = try! secp256k1.Signing.PrivateKey(dataRepresentation: blindingFactor.bytes, format: .compressed)
            let secret = originalOutputs.first(where: { $0.amount == promise.amount})!.secret
            
            let p = Promise(amount: promise.amount, promise:String(bytes: pK.dataRepresentation) , id: promise.id, blindingFactor: blindingFactor, secret: secret)
            transformed.append(p)
        }
        return transformed
    }


    func serializeProofs(proofs: [Proof]) -> String {
        //TODO: remove hardcoded mint selection
        let token = Token_JSON(mint: knownMints[0].url.absoluteString, proofs: proofs)
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


