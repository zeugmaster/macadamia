import Foundation
import CryptoKit

let mintURL = "https://8333.space:3338"

var mintKeyset:Dictionary<String, String> = [:]

// 1. retrieve keyset from mint

func getMintKeyset() {
    if let url = URL(string: mintURL + "/keys") {
        let task = URLSession.shared.dataTask(with: url) { (data, response, error) in
            if let error = error {
                print("Error: \(error)")
            } else if let data = data {
                do {
                    if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: String] {
                        mintKeyset = json
                        //print(mintKeyset)
                    }
                } catch {
                    print("JSON Serialization error: \(error)")
                }
            }
        }
        // Start the task
        task.resume()
    }
}


// ------------ MINTING
// 1. get invoice from mint for token minting

struct PaymentRequest: Codable {
    let pr: String
    let hash: String
}



func serializationTest() {
    let teststring = """
{"token":[{"mint":"https://8333.space:3338","proofs":[{"id":"DSAl9nvvyfva","amount":2,"secret":"EhpennC9qB3iFlW8FZ_pZw","C":"02c020067db727d586bc3183aecf97fcb800c3f4cc4759f69c626c9db5d8f5b5d4"},{"id":"DSAl9nvvyfva","amount":8,"secret":"TmS6Cv0YT5PU_5ATVKnukw","C":"02ac910bef28cbe5d7325415d5c263026f15f9b967a079ca9779ab6e5c2db133a7"}]}],"memo":"Thankyou."}
"""
    
    let serialized = Base64FS.encodeString(str: teststring)
    print(serialized)
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
    
    /*
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
    }*/
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
