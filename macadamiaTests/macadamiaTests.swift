import BIP39
@testable import macadamia
import XCTest

final class macadamiaTests: XCTestCase {
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testSecureHashToCurve() throws {
        // case 000...000
        do {
            let messageData = try Data("0000000000000000000000000000000000000000000000000000000000000000".bytes)
            let result = try secureHashToCurve(message: messageData)
            XCTAssertEqual(String(bytes: result.dataRepresentation),
                           "024cce997d3b518f739663b757deaec95bcd9473c30a14ac2fd04023a739d1a725")
        }
        // case 000...001
        do {
            let messageData = try Data("0000000000000000000000000000000000000000000000000000000000000001".bytes)
            let result = try secureHashToCurve(message: messageData)
            XCTAssertEqual(String(bytes: result.dataRepresentation),
                           "022e7158e11c9506f1aa4248bf531298daa7febd6194f003edcd9b93ade6253acf")
        }
    }

    func testSecretGeneration() throws {
        let phrase = "half depart obvious quality work element tank gorilla view sugar picture humble"
        let mnemonic = try BIP39.Mnemonic(phrase: phrase.components(separatedBy: " "))
        let seed = mnemonic.seed

        let keysetID = "009a1f293253e41e"
        let secrets = [
            "485875df74771877439ac06339e284c3acfcd9be7abf3bc20b516faeadfe77ae",
            "8f2b39e8e594a4056eb1e6dbb4b0c38ef13b1b2c751f64f810ec04ee35b77270",
            "bc628c79accd2364fd31511216a0fab62afd4a18ff77a20deded7b858c9860c8",
            "59284fd1650ea9fa17db2b3acf59ecd0f2d52ec3261dd4152785813ff27a33bf",
            "576c23393a8b31cc8da6688d9c9a96394ec74b40fdaf1f693a6bb84284334ea0",
        ]

        let outputs = generateDeterministicOutputs(counter: 0,
                                                   seed: String(bytes: seed),
                                                   amounts: [1, 1, 1, 1, 1],
                                                   keysetID: keysetID)

        for i in 0 ..< outputs.secrets.count {
            XCTAssertEqual(secrets[i], outputs.secrets[i])
        }
    }
}
