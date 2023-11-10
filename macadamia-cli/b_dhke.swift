//
//  b_dhke.swift
//  macadamia-cli
//
//

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
    let blindingFactor: secp256k1.Signing.PrivateKey // THIS DOESN'T ACTUALLY MAKE SENSE AND IS CHEATING because the blindingfactor can't be known by the mint
}
struct Token {
    let amount: Int
    let token: secp256k1.Signing.PublicKey
}

// Step 1 (Alice)
func generateBlindedOutputs(outputs:[Output]) -> [BlindedOutput]{
    var blindedOutputs:Array<BlindedOutput> = []
    
    for output in outputs {
        let Y = hashToCurve(message: output.secret)
        
        //let blindingFactor = try! secp256k1.Signing.PrivateKey()
        
        let blindingFactor = try! secp256k1.Signing.PrivateKey()
        
        let blindedOutput = try! Y.combine([blindingFactor.publicKey])
        blindedOutputs.append(BlindedOutput(amount: output.amount,
                                            blindedOutput: blindedOutput,
                                            secret: output.secret,
                                            blindingFactor: blindingFactor))
    }
    return blindedOutputs
}

// Step 2 (Bob)
func signBlindedOutputs(blindedOutputs:[BlindedOutput],
                        mintPrivateKey:secp256k1.Signing.PrivateKey) -> [Promise] {
    var promises:[Promise] = []
    for blindedOutput in blindedOutputs {
        let multiplication = try! blindedOutput.blindedOutput.multiply(mintPrivateKey.dataRepresentation.bytes)
        promises.append(Promise(amount: blindedOutput.amount, promise: multiplication, blindingFactor: blindedOutput.blindingFactor))
    }
    return promises
}

// Step 3 (Alice)
func unblindPromises(promises:[Promise],
                     //fix this method call to include the blinding factor in the correct way
                     mintPublicKeys:Dictionary<String,secp256k1.Signing.PublicKey>) -> [Token] {
    var tokens:[Token] = []
    
    for promise in promises {
        let mintPubkeyBytes = mintPublicKeys[String(promise.amount)]!.dataRepresentation.bytes
        let mintPubKey = try! secp256k1.Signing.PublicKey(dataRepresentation: mintPubkeyBytes, format: .compressed)
        print("mint pubkey: " + String(bytes: mintPubKey.dataRepresentation))
        let product = try! mintPubKey.multiply(promise.blindingFactor.dataRepresentation.bytes)
        
        let neg = negatePublicKey(key: product)
        print("neg from custom: " + String(bytes: neg.dataRepresentation))
        
        // C = C_ - A.mult(r)
        print("blinded promise: " + String(bytes: promise.promise.dataRepresentation))
        
        // The Combine API arguments are an array of PublicKey objects and an optional format
        
        let unblindedPromise = try! promise.promise.combine([neg]) //adding the negative should behave just like subtracting
        
        
        print("unblinded promise: " + String(bytes: unblindedPromise.dataRepresentation))
        tokens.append(Token(amount: promise.amount, token: unblindedPromise))
        
    }
    
    return tokens
}

//-------------- Verification ---------------------------------------------------------

func verify(mintPrivateKey: secp256k1.Signing.PrivateKey, token: Token, secret: String) -> Bool {
    let secretHashedToCurve = hashToCurve(message: secret)
    let product = try! secretHashedToCurve.multiply(mintPrivateKey.dataRepresentation.bytes)
    
    print("verify: token: " + String(bytes: token.token.dataRepresentation))
    print("verify: Y.mult(a): " + String(bytes: product.dataRepresentation))
    
    return token.token.dataRepresentation == product.dataRepresentation
}

func test() {
    let testOutputs = [Output(amount: 64, secret: "test")]
    let blindedOutputs = generateBlindedOutputs(outputs: testOutputs)
    
    print("B_: " + String(bytes: blindedOutputs[0].blindedOutput.dataRepresentation))
    
    let mintPrivateKey = try! secp256k1.Signing.PrivateKey.init(dataRepresentation: "C90FDAA22168C234C4C6628B80DC1CD129024E088A67CC74020BBEA63B14E5C9".bytes) // reuse for test purposes
    
    let promises = signBlindedOutputs(blindedOutputs: blindedOutputs, mintPrivateKey: mintPrivateKey)
    print("C_: " + String(bytes: promises[0].promise.dataRepresentation))
    
    // generate dummy public key dict
    let keyset = ["64":mintPrivateKey.publicKey]
    
    let tokens = unblindPromises(promises: promises, mintPublicKeys: keyset)
    print("C: " + String(bytes: tokens[0].token.dataRepresentation))
    
    for token in tokens {
        print(verify(mintPrivateKey: mintPrivateKey, token: token, secret: "test"))
    }
}

//-------------- Supporting functions ------------------------------------------------

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
    //print("value going into negate: " + bytesToHexString(bytes: key.dataRepresentation))
    
    let serialized = key.dataRepresentation

    // Assuming serialized is a Data or [UInt8] type
    var firstByte = serialized.first!
    let remainder = serialized.dropFirst()
    
    // Flip the odd/even byte
    switch firstByte {
    case 0x03:
        firstByte = 0x02
    case 0x02:
        firstByte = 0x03
    default:
        // Handle unexpected cases or throw an error
        break
    }
    
    // Create a new PublicKey with the modified data
    // Again, the specific initializer or method would depend on your library.
    let newKeyData = Data([firstByte]) + remainder
    let newKey = try! secp256k1.Signing.PublicKey(dataRepresentation: newKeyData, format: .compressed)
    //print("value coming out of negate: " + bytesToHexString(bytes: newKey.dataRepresentation))
    return newKey
}

