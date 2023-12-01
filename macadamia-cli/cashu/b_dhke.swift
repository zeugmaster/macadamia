//
//  b_dhke.swift
//  macadamia-cli
//
//

import Foundation
import CryptoKit
import secp256k1

// Step 1 (Alice)
func generateOutputs(amounts:[Int]) -> [Output] {
    var outputs = [Output]()
    
    for n in amounts {
        let key = SymmetricKey(size: .bits128)
        let keyData = key.withUnsafeBytes {Data($0)}
        let secretString = Base64FS.encodeString(str: keyData.base64EncodedString())
        let Y = hashToCurve(message: secretString)
        let blindingFactor = try! secp256k1.Signing.PrivateKey()
        let output = try! Y.combine([blindingFactor.publicKey])
        outputs.append(Output(amount: n,
                              output: String(bytes: output.dataRepresentation),
                              secret: secretString,
                              blindingFactor: String(bytes: blindingFactor.dataRepresentation)))
    }
    return outputs
}

// Step 3 (Alice)
func unblindPromises(promises:[Promise],
                     mintPublicKeys:Dictionary<String,String>) -> [Proof] {
    var proofs = [Proof]()
    for promise in promises {
        let pubBytes = try! mintPublicKeys[String(promise.amount)]!.bytes
        let mintPubKey = try! secp256k1.Signing.PublicKey(dataRepresentation: pubBytes, format: .compressed)
        let product = try! mintPubKey.multiply(promise.blindingFactor.dataRepresentation.bytes)
        let neg = negatePublicKey(key: product)

        // C = C_ - A.mult(r)
        let unblindedPromise = try! promise.promise.combine([neg])
        
        proofs.append(Proof(id: promise.id, amount: promise.amount, secret: promise.secret, C: String(bytes: unblindedPromise.dataRepresentation)))
    }
    
    return proofs
}

func hashToCurve(message: String) -> secp256k1.Signing.PublicKey {
    var point:secp256k1.Signing.PublicKey? = nil
    let prefix = Data([0x02])
    var messageData = message.data(using: .utf8)!
    while point == nil {
        let hash = SHA256.hash(data: messageData)
        let combined = prefix + hash
        do {
            point = try secp256k1.Signing.PublicKey(dataRepresentation: combined, format: .compressed)
        } catch {
            messageData = Data(hash)
        }
    }
    return point!
}

func negatePublicKey(key: secp256k1.Signing.PublicKey) -> secp256k1.Signing.PublicKey {
    let serialized = key.dataRepresentation
    var firstByte = serialized.first!
    let remainder = serialized.dropFirst()
    switch firstByte {
    case 0x03:
        firstByte = 0x02
    case 0x02:
        firstByte = 0x03
    default:
        break
    }
    let newKeyData = Data([firstByte]) + remainder
    let newKey = try! secp256k1.Signing.PublicKey(dataRepresentation: newKeyData, format: .compressed)
    return newKey
}

