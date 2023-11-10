import Foundation
import CryptoKit

let mintURL = "https://8333.space:3338"

var mintKeyset:Dictionary<String, String> = [:]

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
            print("Starting download")
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
    var secrets:Array<String> = [""]
    for _ in splitIntoBase2Numbers(n: amount) {
        let key = SymmetricKey.init(size: .bits128)
        let keyString:String = key.withUnsafeBytes { body in
            Data(Array(body)).base64EncodedString()
        }
        secrets.append(keyString)
    }
    print("Created the following secrets: \(secrets)")
    
    
    let urlString = mintURL + "/mint?amount=" + String(amount)
    if let url = URL(string: urlString) {
        let task = URLSession.shared.dataTask(with: url) {payload, response, error in
            if error == nil {
                let paymentRequest = try? JSONDecoder().decode(PaymentRequest.self, from: payload!)
                completion(paymentRequest)
            } else {
                //needs much more robust error handling 🤷‍♂️
                completion(nil)
            }
        }
        task.resume()
    } else {
        print("invalid URL")
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
