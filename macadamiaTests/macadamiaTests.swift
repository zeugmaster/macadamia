import BIP39
@testable import macadamia
import XCTest
import CashuSwift
import SwiftData

final class macadamiaTests: XCTestCase {
    
    var container: ModelContainer!

    override func setUp() {
        super.setUp()
        
        let schema = Schema([Proof.self, Mint.self, Wallet.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        
        do {
            container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            XCTFail("Failed to create in-memory container: \(error)")
        }
    }

    override func tearDown() {
        container = nil
        super.tearDown()
    }
    
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    @MainActor
    func testProofSelection() async throws {
        let context = container.mainContext
        
        let wallet = Wallet()
        context.insert(wallet)
        let mint = try await CashuSwift.loadMint(url: URL(string: "https://testmint.macadamia.cash")!, type: Mint.self)
        mint.wallet = wallet
        
        
        let proofs = [
            Proof(keysetID: "id1", C: "C1", secret: "secret1", unit: .sat, inputFeePPK: 100, state: .valid, amount: 1, mint: mint, wallet: wallet),
            Proof(keysetID: "id2", C: "C2", secret: "secret2", unit: .sat, inputFeePPK: 100, state: .valid, amount: 2, mint: mint, wallet: wallet),
            Proof(keysetID: "id3", C: "C3", secret: "secret3", unit: .sat, inputFeePPK: 200, state: .valid, amount: 4, mint: mint, wallet: wallet),
            Proof(keysetID: "id4", C: "C4", secret: "secret4", unit: .sat, inputFeePPK: 200, state: .valid, amount: 8, mint: mint, wallet: wallet),
            Proof(keysetID: "id5", C: "C5", secret: "secret5", unit: .sat, inputFeePPK: 100, state: .valid, amount: 16, mint: mint, wallet: wallet),
            Proof(keysetID: "id6", C: "C6", secret: "secret6", unit: .sat, inputFeePPK: 100, state: .valid, amount: 32, mint: mint, wallet: wallet),
            Proof(keysetID: "id7", C: "C7", secret: "secret7", unit: .sat, inputFeePPK: 100, state: .valid, amount: 64, mint: mint, wallet: wallet),
            Proof(keysetID: "id8", C: "C8", secret: "secret8", unit: .sat, inputFeePPK: 100, state: .valid, amount: 128, mint: mint, wallet: wallet),
            Proof(keysetID: "id9", C: "C9", secret: "secret9", unit: .sat, inputFeePPK: 100, state: .valid, amount: 256, mint: mint, wallet: wallet),
            Proof(keysetID: "id1", C: "c", secret: "secret10", unit: .sat, inputFeePPK: 200, state: .valid, amount: 512, mint: mint, wallet: wallet),
            Proof(keysetID: "id3", C: "C3", secret: "secret3", unit: .sat, inputFeePPK: 200, state: .valid, amount: 4, mint: mint, wallet: wallet),
            Proof(keysetID: "id4", C: "C4", secret: "secret4", unit: .sat, inputFeePPK: 200, state: .valid, amount: 8, mint: mint, wallet: wallet),
            Proof(keysetID: "id5", C: "C5", secret: "secret5", unit: .sat, inputFeePPK: 400, state: .valid, amount: 16, mint: mint, wallet: wallet),
            Proof(keysetID: "id6", C: "C6", secret: "secret6", unit: .sat, inputFeePPK: 400, state: .valid, amount: 32, mint: mint, wallet: wallet),
            Proof(keysetID: "id7", C: "C7", secret: "secret7", unit: .sat, inputFeePPK: 400, state: .valid, amount: 64, mint: mint, wallet: wallet),
            Proof(keysetID: "id8", C: "C8", secret: "secret8", unit: .sat, inputFeePPK: 200, state: .valid, amount: 128, mint: mint, wallet: wallet),
            Proof(keysetID: "id9", C: "C9", secret: "secret9", unit: .sat, inputFeePPK: 200, state: .valid, amount: 256, mint: mint, wallet: wallet),
            Proof(keysetID: "i0", C: "C10", secret: "ecret10", unit: .sat, inputFeePPK: 200, state: .valid, amount: 512, mint: mint, wallet: wallet)
        ]

        
        mint.proofs = proofs
        proofs.forEach({ context.insert($0) })
        context.insert(mint)
        try context.save()

        // Fetch the mint from the context to ensure we're working with the managed object
//        let fetchedMint = try context.fetch(FetchDescriptor<Mint>()).first
//        XCTAssertNotNil(fetchedMint, "Failed to fetch the mint from the context")

        // Set a target amount
        let targetAmount = 20
        
        guard let selection = mint.select(allProofs: proofs, amount: targetAmount, unit: .sat) else {
            XCTFail()
            return
        }
        
        print("proof sum: \(selection.selected.sum)")
        selection.selected.forEach({ proof in
            print(proof.amount)
        })
        print(selection.fee)
        print(proofs.sum)
    }
    
    func testAmountString() {
        print(amountDisplayString(123, unit: .sat))
        print(amountDisplayString(-123, unit: .sat, negative: true))
        print(amountDisplayString(123, unit: .usd))
        print(amountDisplayString(123, unit: .eur, negative: true))
        print(amountDisplayString(0, unit: .eur))
    }
}
