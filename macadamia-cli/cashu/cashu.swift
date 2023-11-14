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
struct Output {
    let amount: Int
    let secret: String
}
struct BlindedOutput {
    let amount: Int
    let blindedOutput: secp256k1.Signing.PublicKey
    let secret: String
    let blindingFactor: secp256k1.Signing.PrivateKey
}
struct Promise {
    let amount: Int
    let promise: secp256k1.Signing.PublicKey
    let id: String
    let blindingFactor:secp256k1.Signing.PrivateKey
}
struct Token {
    let amount: Int
    let token: secp256k1.Signing.PublicKey
    let id: String
}

class Wallet {
    var knownMints = [Mint]()
    var blindedOutputs = [BlindedOutput]()
    
    init() {
        
    }
    
    func updateMints(completion: @escaping ([Mint]) -> Void) {
        //load from database
        
        // TODO: replace hardcoded static mints
        let mintURLs = [URL(string: "https://63ff34c9b6.d.voltageapp.io/cashu/api/v1/aCPSKZ993aY9Z8ECK6uqe7")!,
                        URL(string: "https://8333.space:3338")!]
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
                    print("Error fetching data: \(error)")
                }
            }
            completion(knownMints)
        }
        Task {
            await fetchAllData()
        }
    }
    //FIXME: this is propably unnecessary complexity using two completion handlers
    func mint(amount:Int,
              prCompletion: @escaping (Result<PaymentRequest,Error>) -> Void,
              mintCompletion: @escaping (Result<String,Error>) -> Void) {
        //1. make GET req to the mint to receive lightning invoice
        // TODO: change to async await
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
                        mintCompletion(.success("yay"))
                        
                        //TODO: save tokens to disk
                        
                    } else {
                        print("empty promises")
                    }
                }
            } else {
                //needs much more robust error handling
                prCompletion(.failure(error!))
            }
        }
        task.resume()
        
        
    }

    func sendTokens(amount:Int, completion: @escaping (Result<String,Error>) -> Void) {
        
    }

    func receiveTokens(tokenString:String, completion: @escaping (Result<Void,Error>) -> Void) {
        
    }

    func melt(amount:Int, completion: @escaping (Result<Void,Error>) -> Void) {
        
    }

    fileprivate func split() {
        
    }

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
        var outputs:[Output] = []
        for m in splitIntoBase2Numbers(n: amount) {
            let key = SymmetricKey(size: .bits128)
            let keyData = key.withUnsafeBytes {Data($0)}
            let secretString = Base64FS.encodeString(str: keyData.base64EncodedString())
            let output = Output(amount: m, secret:secretString)
            outputs.append(output)
        }
        
        blindedOutputs = generateBlindedOutputs(outputs: outputs)
        
        var outputArray: [[String: Any]] = []
        for o in blindedOutputs {
            var dict: [String: Any] = [:]
            dict["amount"] = o.amount
            // Ensure this is the correct string representation
            dict["B_"] = String(bytes: o.blindedOutput.dataRepresentation)
            outputArray.append(dict)
        }
        let containerDict = ["outputs": outputArray]

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: containerDict, options: [])
            if let url = URL(string: knownMints[0].url.absoluteString + "/mint?hash=" + payReq.hash) {
                print(url)
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
                        completion(self.transformPromises(promises: jsonObject.promises))
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
    func transformPromises(promises:[Promise_JSON]) -> [Promise] {
        var transformed = [Promise]()
        print(promises)
        for promise in promises {
            let pK = try! secp256k1.Signing.PublicKey(dataRepresentation: promise.C_.bytes, format: .compressed)
            let blindingFactor = blindedOutputs.first(where: { $0.amount == promise.amount})!.blindingFactor
            let p = Promise(amount: promise.amount, promise:pK , id: promise.id, blindingFactor: blindingFactor)
            transformed.append(p)
        }
        return transformed
    }

    // 5. UNBLIND PROMISES
    // -> done in b_dhk.swift
    
    // 6. serialize tokens
    struct Token_Container: Codable {
        let token: [Token_JSON]
        let memo: String
    }
    struct Token_JSON: Codable {
        let mint: String
        let proofs: [Proofs_JSON]
    }
    struct Proofs_JSON: Codable {
        let id: String
        let amount: Int
        let secret: String
        let C: String
    }

    func serializeTokens(tokens: [Token]) -> String {
        var proofs = [Proofs_JSON]()
        for token in tokens {
            let secret = blindedOutputs.first(where: { $0.amount == token.amount})!.secret
            proofs.append(Proofs_JSON(id: token.id, amount: token.amount, secret: secret, C: String(bytes: token.token.dataRepresentation)))
        }
        let token = Token_JSON(mint: knownMints[0].url.absoluteString, proofs: proofs)
        let tokenContainer = Token_Container(token: [token], memo: "jeeez")
        
        let jsonData = try! JSONEncoder().encode(tokenContainer)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        print(jsonString)
        
        let safeString = Base64FS.encodeString(str: jsonString)
        
        return "cashuA" + safeString
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


