//
//  b_dhke.swift
//  macadamia-cli
//
//

import Foundation
import CryptoKit
import secp256k1
import BIP32
import BIP39

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
        let pK = try! secp256k1.Signing.PublicKey(dataRepresentation: promise.promise.bytes, format: .compressed)
        let product = try! mintPubKey.multiply(pK.dataRepresentation.bytes)
        let neg = negatePublicKey(key: product)

        // C = C_ - A.mult(r)
        let p = try! secp256k1.Signing.PublicKey(dataRepresentation: promise.promise.bytes, format: .compressed)
        let unblindedPromise = try! p.combine([neg])
        
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

func childPrivateKeyForDerivationPath(seed:String, derivationPath:String) -> String? {
    var parts = derivationPath.split(separator: "/")
    
    if parts.count > 7 || parts.count < 1 {
        return nil
    }
    
    if parts.first!.contains("m") {
        parts.removeFirst()
    }
    
    let privateMasterKeyDerivator: PrivateMasterKeyDerivating = PrivateMasterKeyDerivator()
    var current = try! privateMasterKeyDerivator.privateKey(seed: Data(seed.bytes))

    for var part in parts {
        var index:Int = 0
        if part.contains("'") {
            part.replace("'", with: "")
            index = 2147483648
        }
        if let i = Int(part) {
             index += i
        } else {
            print("could not read index from string")
            return nil
        }
        //derive child for current key and set current = new
        let new = try! PrivateChildKeyDerivator().privateKey(privateParentKey: current, index: UInt32(index))
        current = new
    }

    return String(bytes: current.key)
}
