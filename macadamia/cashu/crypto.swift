//
//  b_dhke.swift
//  macadamia-cli
//
//

/*
import Foundation
import CryptoKit
import secp256k1
import BIP32
import BIP39
import BigNumber
import OSLog

//TODO: needs to be able to throw
//TODO: should be broken up into one function for secret and one for the outputs
func generateDeterministicOutputs(counter:Int, seed:String, amounts:[Int], keysetID:String) -> (outputs: [Output], blindingFactors: [String], secrets:[String]) {
    var outputs = [Output]()
    var blindingFactors = [String]()
    var secrets = [String]()
    let keysetInt:Int
    if keysetID.count == 16 {
        keysetInt = convertHexKeysetID(keysetID: keysetID)!
    } else {
        keysetInt = convertKeysetID(keysetID: keysetID)!
    }
    for i in 0..<amounts.count {
        let index = counter + i
        
        let secretPath = "m/129372'/0'/\(keysetInt)'/\(index)'/0"
        let blindingFactorPath = "m/129372'/0'/\(keysetInt)'/\(index)'/1"
        
        // x is the secret, Y = hashToCurve(x)
        let x = childPrivateKeyForDerivationPath(seed: seed, derivationPath: secretPath)!
        let Y = try! secureHashToCurve(message: x.data(using: .utf8)!)
        
        
        // r is the blinding factor
        let r = try! secp256k1.Signing.PrivateKey(dataRepresentation: childPrivateKeyForDerivationPath(seed: seed, derivationPath: blindingFactorPath)!.bytes)
        let output = try! Y.combine([r.publicKey])
        
        let outputString = String(bytes: output.dataRepresentation)
        
        outputs.append(Output(amount: amounts[i], B_: outputString))
        
        blindingFactors.append(String(bytes: r.dataRepresentation))
        secrets.append(x)
        Logger(subsystem: "com.zeugmaster.macadamia", category: "wallet").debug(
            """
            Created secrets with derivation path \(secretPath, privacy: .public), \
            for keysetID: \(keysetID), output: ...\(outputString.suffix(10))
            """
        )
    }
    
    return (outputs, blindingFactors, secrets)
}

//TODO: DEFINITELY needs to be able to throw
func unblindPromises(promises:[Promise],
                     blindingFactors:[String],
                     secrets:[String],
                     mintPublicKeys:Dictionary<String,String>) -> [Proof] {
    var proofs = [Proof]()
    for i in 0..<promises.count {
        let pubBytes = try! mintPublicKeys[String(promises[i].amount)]!.bytes
        let mintPubKey = try! secp256k1.Signing.PublicKey(dataRepresentation: pubBytes, format: .compressed)
        let pK = try! secp256k1.Signing.PrivateKey(dataRepresentation: blindingFactors[i].bytes)
        let product = try! mintPubKey.multiply(pK.dataRepresentation.bytes)
        let neg = negatePublicKey(key: product)

        // C = C_ - A.mult(r)
        let p = try! secp256k1.Signing.PublicKey(dataRepresentation: promises[i].C_.bytes, format: .compressed)
        let unblindedPromise = try! p.combine([neg])
        
        proofs.append(Proof(id: promises[i].id, amount: promises[i].amount, secret: secrets[i], C: String(bytes: unblindedPromise.dataRepresentation)))
    }
    return proofs
}

func secureHashToCurve(message: Data) throws -> secp256k1.Signing.PublicKey {
    let domainSeparator = Data("Secp256k1_HashToCurve_Cashu_".utf8)
    
    let msgToHash = SHA256.hash(data: domainSeparator + message)
    var counter: UInt32 = 0

    while counter < UInt32(pow(2.0, 16)) {
        let counterData = Data(withUnsafeBytes(of: &counter, { Data($0) }))
        let hash = SHA256.hash(data: msgToHash + counterData)
        do {
            let prefix = Data([0x02])
            let combined = prefix + hash
            return try secp256k1.Signing.PublicKey(dataRepresentation: combined, format: .compressed)
        } catch {
            counter += 1
        }
    }
    
    // If no valid point is found, throw an error
    throw NSError(domain: "No valid point found", code: -1, userInfo: nil)
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

func convertKeysetID(keysetID: String) -> Int? {
    let data = [UInt8](Data(base64Encoded: keysetID)!)
    let big = BInt(bytes: data)
    let result = big % (Int(pow(2.0, 31.0)) - 1)
    return Int(result)
}

func convertHexKeysetID(keysetID: String) -> Int? {
    let data = try! [UInt8](Data(keysetID.bytes))
    let big = BInt(bytes: data)
    let result = big % (Int(pow(2.0, 31.0)) - 1)
    return Int(result)
}
*/
