import Foundation
import CryptoKit

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
// 4e store list of blinded outputs for later unblinding

func requestBlindedOutputs(amount:Int, payReq:PaymentRequest, completion: @escaping ([BlindedOutput]) -> Void) {
    var outputs:[Output] = []
    for m in splitIntoBase2Numbers(n: amount) {
        let output = Output(amount: m, secret: "test_\(m)")
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
        print(jsonString ?? "Invalid JSON String")

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
                print(String(data: data!, encoding: .utf8) ?? "no data")
                completion([])
            }
            task.resume()
        } else {
            print("URL for blinded output req invalid")
        }
    } catch {
        print("Error serializing JSON: \(error)")
    }
}

// 5. UNBLIND SIGNATURES

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
