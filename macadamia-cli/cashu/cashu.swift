import Foundation
import CryptoKit
import secp256k1

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

struct Promise_JSON: Codable {
    let id: String
    let amount: Int
    let C_: String
}
struct Promise_JSON_List: Codable {
    let promises: [Promise_JSON]
}

//let mintURL = "https://8333.space:3338"
let mintURL = "https://63ff34c9b6.d.voltageapp.io/cashu/api/v1/aCPSKZ993aY9Z8ECK6uqe7"

var mintKeyset:Dictionary<String, String> = [:]

var blindedOutputs:Array<BlindedOutput> = []

// 1. retrieve keyset from mint

func getMintKeyset(completion: @escaping (Dictionary<String,String>) -> Void) {
    if let url = URL(string: mintURL + "/keys") {
        let task = URLSession.shared.dataTask(with: url) { (data, response, error) in
            if let error = error {
                print("Network error: \(error)")
                return
            }
            guard let data = data else {
                print("No data received")
                return
            }
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: String] {
                    print("Successfully parsed JSON")
                    completion(json)
                } else {
                    print("Unable to cast JSON to [Int: String]")
                }
            } catch {
                print("JSON Serialization error: \(error)")
            }
        }
        print("Starting mint keyset download")
        task.resume()
    } else {
        print("Invalid URL")
    }
}

// 2. get invoice from mint for token minting

struct PaymentRequest: Codable {
    let pr: String
    let hash: String
}

func requestMint(amount:Int, completion: @escaping (PaymentRequest?) -> Void) {
    // make GET req and save payment req and hash
    let urlString = mintURL + "/mint?amount=" + String(amount)
    if let url = URL(string: urlString) {
        let task = URLSession.shared.dataTask(with: url) {payload, response, error in
            if error == nil {
                let paymentRequest = try? JSONDecoder().decode(PaymentRequest.self, from: payload!)
                completion(paymentRequest)
            } else {
                //needs much more robust error handling
                completion(nil)
            }
        }
        task.resume()
    } else {
        print("invalid URL")
    }
}

// 3. pay invoice

// ...

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
    //print("outputs: \(outputs)")
    
    blindedOutputs = generateBlindedOutputs(outputs: outputs)
    //print("blindedOutputs: \(blindedOutputs)")
    
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
        let jsonString = String(data: jsonData, encoding: .utf8)
        //print(jsonString ?? "Invalid JSON String")

        if let url = URL(string: mintURL + "/mint?hash=" + payReq.hash) {
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
                    completion(transformPromises(promises: jsonObject.promises))
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
    let token = Token_JSON(mint: mintURL, proofs: proofs)
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
