import BIP39
@testable import macadamia
import XCTest
import CashuSwift
import SwiftData
import secp256k1

final class macadamiaTests: XCTestCase {
    
    // Success Mint (5s delay) - Always succeeds after 5 seconds
    let successMint = "http://localhost:3338"

    // Success Mint Long (90s delay) - Always succeeds after 90 seconds with MPP support
    let successMintLong = "http://localhost:3342"

    // Long Error Mint (120s delay) - Always fails after 120 seconds
    let longErrorMint = "http://localhost:3339"

    // Short Error Mint (3s delay) - Always fails after 3 seconds
    let shortErrorMint = "http://localhost:3340"

    // Exception Mint - Immediately throws exceptions
    let exceptionMint = "http://localhost:3341"
    
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
        let mnemonic = Mnemonic()
        let wallet = Wallet(mnemonic: mnemonic.phrase.joined(separator: " "), seed: String(bytes: mnemonic.seed))
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
    
    @MainActor
    func testMintEcashDerivationCounter() {
        // Set up the test environment synchronously
        let context = container.mainContext
        let mnemonic = Mnemonic()
        let wallet = Wallet(mnemonic: mnemonic.phrase.joined(separator: " "), seed: String(bytes: mnemonic.seed))
        context.insert(wallet)
        
        // Use expectation for async operations
        let setupExpectation = XCTestExpectation(description: "Mint setup completed")
        let mintExpectation = XCTestExpectation(description: "Mint operation completed")
        
        var testMint: Mint?
        var initialDerivationCounter: Int = 0
        var testKeysetID: String = ""
        var mintedProofs: [CashuSwift.Proof]?
        
        // Create sendable types for async operations
        let mintURL = URL(string: successMint)!
        let seed = wallet.seed
        
        // Set up mint in a Task using sendable types
        Task {
            do {
                // Load mint using CashuSwift
                let sendableMint = try await CashuSwift.loadMint(url: mintURL)
                
                // Convert back to AppSchemaV1.Mint on MainActor
                await MainActor.run {
                    let mint = Mint(url: sendableMint.url, keysets: sendableMint.keysets)
                    mint.wallet = wallet
                    context.insert(mint)
                    testMint = mint
                    
                    // Store initial state
                    XCTAssertFalse(mint.keysets.isEmpty, "Mint should have keysets")
                    testKeysetID = mint.keysets.first!.keysetID
                    initialDerivationCounter = mint.keysets.first!.derivationCounter
                    
                    setupExpectation.fulfill()
                }
                
                // Now get quote and mint using sendable types
                let quoteRequest = CashuSwift.Bolt11.RequestMintQuote(unit: "sat", amount: 100)
                let quote = try await CashuSwift.getQuote(mint: sendableMint, quoteRequest: quoteRequest)
                
                guard let mintQuote = quote as? CashuSwift.Bolt11.MintQuote else {
                    XCTFail("Quote should be a MintQuote")
                    mintExpectation.fulfill()
                    return
                }
                
                // Perform minting with sendable types
                let issueResult = try await CashuSwift.issue(for: mintQuote, mint: sendableMint, seed: seed)
                mintedProofs = issueResult.proofs
                
                // Check DLEQ verification result
                switch issueResult.dleqResult {
                case .valid:
                    print("✅ DLEQ verification: Valid")
                case .fail:
                    print("❌ DLEQ verification: Failed")
                    XCTFail("DLEQ verification failed")
                case .noData:
                    print("⚠️ DLEQ verification: No DLEQ data available")
                }
                
                mintExpectation.fulfill()
                
            } catch {
                XCTFail("Operation failed with error: \(error)")
                setupExpectation.fulfill()
                mintExpectation.fulfill()
            }
        }
        
        // Wait for async operations to complete
        wait(for: [setupExpectation, mintExpectation], timeout: 15.0)
        
        // Verify results synchronously on MainActor
        guard let mint = testMint else {
            XCTFail("Mint was not initialized")
            return
        }
        
        // Verify that proofs were minted
        XCTAssertNotNil(mintedProofs, "Minted proofs should not be nil")
        XCTAssertFalse(mintedProofs?.isEmpty ?? true, "Should have minted some proofs")
        
        let proofsCount = mintedProofs?.count ?? 0
        
        // Update derivation counter in mint (simulating what would happen in the app)
        mint.increaseDerivationCounterForKeysetWithID(testKeysetID, by: proofsCount)
        
        // Get the updated derivation counter for the keyset
        let updatedKeyset = mint.keysets.first { $0.keysetID == testKeysetID }
        XCTAssertNotNil(updatedKeyset, "Keyset should still exist")
        
        let finalDerivationCounter = updatedKeyset!.derivationCounter
        
        // Verify the derivation counter was increased correctly
        XCTAssertGreaterThan(finalDerivationCounter, initialDerivationCounter, 
                           "Derivation counter should have increased")
        XCTAssertEqual(finalDerivationCounter, initialDerivationCounter + proofsCount,
                      "Derivation counter should have increased by the number of minted proofs (\(proofsCount))")
        
        print("✅ Test passed: Derivation counter increased from \(initialDerivationCounter) to \(finalDerivationCounter) (increase of \(proofsCount) proofs)")
    }
    
    func testInputValidator() {
        
        // Test BOLT11 invoices
        let bolt11Tests = [
            ("lnbc1234567890", true),
            ("lightning:lnbc1234567890", true),
            ("lightning://lnbc1234567890", true),
            ("LNBC1234567890", true), // case insensitive
            ("lntbs1234567890", true),
            ("lntb1234567890", true),
            ("lnbcrt1234567890", true),
            ("lnbc+12+34+56+78+90", true), // with + signs
            ("lnbc 12 34 56 78 90", true), // with spaces
        ]
        
        for (input, shouldBeValid) in bolt11Tests {
            let result = InputValidator.validate(input, supportedTypes: [.bolt11Invoice])
            switch result {
            case .valid(let res) where shouldBeValid:
                XCTAssertEqual(res.type, .bolt11Invoice)
                XCTAssertFalse(res.payload.contains("+"))
                XCTAssertFalse(res.payload.contains(" "))
                XCTAssertFalse(res.payload.hasPrefix("lightning:"))
            case .invalid where !shouldBeValid:
                break // Expected
            default:
                XCTFail("Unexpected result for \(input)")
            }
        }
        
        // Test Cashu tokens
        let cashuTests = [
            ("cashuAeyJ0b2tlbiI6W3sicHJvb2ZzIjpbXX1dfQ", true),
            ("cashu://cashuAeyJ0b2tlbiI6W3sicHJvb2ZzIjpbXX1dfQ", true),
            ("cashu:cashuAeyJ0b2tlbiI6W3sicHJvb2ZzIjpbXX1dfQ", true),
            ("CASHUAeyJ0b2tlbiI6W3sicHJvb2ZzIjpbXX1dfQ", true), // case insensitive
            ("cashu+A+eyJ0b2tlbiI6W3sicHJvb2ZzIjpbXX1dfQ", true), // with + signs
        ]
        
        for (input, shouldBeValid) in cashuTests {
            let result = InputValidator.validate(input, supportedTypes: [.token])
            switch result {
            case .valid(let res) where shouldBeValid:
                XCTAssertEqual(res.type, .token)
                XCTAssertFalse(res.payload.contains("+"))
                XCTAssertFalse(res.payload.hasPrefix("cashu://"))
            case .invalid where !shouldBeValid:
                break // Expected
            default:
                XCTFail("Unexpected result for \(input)")
            }
        }
        
        // Test BOLT12 offers
        let bolt12Tests = [
            ("lno1234567890", true),
            ("LNO1234567890", true), // case insensitive
        ]
        
        for (input, shouldBeValid) in bolt12Tests {
            let result = InputValidator.validate(input, supportedTypes: [.bolt12Offer])
            switch result {
            case .valid(let res) where shouldBeValid:
                XCTAssertEqual(res.type, .bolt12Offer)
            case .invalid where !shouldBeValid:
                break // Expected
            default:
                XCTFail("Unexpected result for \(input)")
            }
        }
        
        // Test CREQ
        let creqTests = [
            ("creq1234567890", true),
            ("CREQ1234567890", true), // case insensitive
        ]
        
        for (input, shouldBeValid) in creqTests {
            let result = InputValidator.validate(input, supportedTypes: [.creq])
            switch result {
            case .valid(let res) where shouldBeValid:
                XCTAssertEqual(res.type, .creq)
            case .invalid where !shouldBeValid:
                break // Expected
            default:
                XCTFail("Unexpected result for \(input)")
            }
        }
        
        // Test public keys
        // Using a valid compressed public key from Bitcoin wiki test vectors
        let validPubkey = "0279BE667EF9DCBBAC55A06295CE870B07029BFCDB2DCE28D959F2815B16F81798"
        let pubkeyTests = [
            (validPubkey, true),
            ("invalidpubkey", false),
            ("00", false), // too short
            ("not_hex_at_all!", false),
        ]
        
        for (input, shouldBeValid) in pubkeyTests {
            let result = InputValidator.validate(input, supportedTypes: [.publicKey])
            switch result {
            case .valid(let res) where shouldBeValid:
                XCTAssertEqual(res.type, .publicKey)
            case .invalid where !shouldBeValid:
                break // Expected
            default:
                XCTFail("Unexpected result for public key test: \(input)")
            }
        }
        
        // Test unsupported types
        let unsupportedTests = [
            "randomstring",
            "http://example.com",
            "bitcoin:1234567890",
            "",
        ]
        
        for input in unsupportedTests {
            let result = InputValidator.validate(input, supportedTypes: [.bolt11Invoice, .token, .bolt12Offer, .creq, .publicKey])
            switch result {
            case .invalid(let message):
                XCTAssertEqual(message, "Unsupported Input")
            default:
                XCTFail("Expected invalid result for \(input)")
            }
        }
        
        // Test supported types filtering
        let filterTests = [
            ("lnbc1234567890", [InputView.InputType.token], false), // BOLT11 but only token supported
            ("cashuAeyJ0b2tlbiI6W3sicHJvb2ZzIjpbXX1dfQ", [InputView.InputType.bolt11Invoice], false), // Token but only BOLT11 supported
            ("lnbc1234567890", [InputView.InputType.bolt11Invoice, InputView.InputType.token], true), // BOLT11 with correct support
        ]
        
        for (input, supportedTypes, shouldBeValid) in filterTests {
            let result = InputValidator.validate(input, supportedTypes: supportedTypes)
            switch result {
            case .valid where shouldBeValid:
                break // Expected
            case .invalid where !shouldBeValid:
                break // Expected
            default:
                XCTFail("Unexpected result for \(input) with supported types \(supportedTypes)")
            }
        }
    }
    
    // MARK: - Balance Calculator Tests
    
    func testBalanceCalculatorSimpleTransfer() {
        // Test case: Two accounts, one needs to send, one needs to receive
        let deltas: [String: Int] = [
            "A": -100,  // A needs to send 100
            "B": 100    // B needs to receive 100
        ]
        
        let transactions = BalanceCalculator<String>.calculateTransactions(for: deltas)
        
        XCTAssertEqual(transactions.count, 1, "Should generate exactly 1 transaction")
        XCTAssertEqual(transactions[0].from, "A")
        XCTAssertEqual(transactions[0].to, "B")
        XCTAssertEqual(transactions[0].amount, 100)
    }
    
    func testBalanceCalculatorMultipleAccounts() {
        // Test case: Multiple accounts with various deltas
        let deltas: [String: Int] = [
            "A": -300,  // A needs to send 300
            "B": -200,  // B needs to send 200
            "C": 250,   // C needs to receive 250
            "D": 250    // D needs to receive 250
        ]
        
        let transactions = BalanceCalculator<String>.calculateTransactions(for: deltas)
        
        // Verify total amount sent equals total amount received
        let totalSent = transactions.reduce(0) { $0 + $1.amount }
        XCTAssertEqual(totalSent, 500, "Total amount transferred should be 500")
        
        // Verify each account's net change matches the delta
        var netChanges: [String: Int] = ["A": 0, "B": 0, "C": 0, "D": 0]
        for tx in transactions {
            netChanges[tx.from, default: 0] -= tx.amount
            netChanges[tx.to, default: 0] += tx.amount
        }
        
        for (account, expectedDelta) in deltas {
            XCTAssertEqual(netChanges[account], expectedDelta, 
                         "Account \(account) should have net change of \(expectedDelta)")
        }
    }
    
    func testBalanceCalculatorNoTransactionsNeeded() {
        // Test case: All accounts already balanced (zero deltas)
        let deltas: [String: Int] = [
            "A": 0,
            "B": 0,
            "C": 0
        ]
        
        let transactions = BalanceCalculator<String>.calculateTransactions(for: deltas)
        
        XCTAssertEqual(transactions.count, 0, "Should generate no transactions when all deltas are zero")
    }
    
    func testBalanceCalculatorComplexRebalancing() {
        // Test case: Complex scenario with multiple sources and targets
        let deltas: [String: Int] = [
            "MintA": -500,  // Has 500 extra
            "MintB": -300,  // Has 300 extra
            "MintC": 200,   // Needs 200
            "MintD": 400,   // Needs 400
            "MintE": 200    // Needs 200
        ]
        
        let transactions = BalanceCalculator<String>.calculateTransactions(for: deltas)
        
        // Verify conservation of amount
        let totalSent = transactions.reduce(0) { $0 + $1.amount }
        XCTAssertEqual(totalSent, 800, "Total amount transferred should be 800")
        
        // Verify each mint's net change matches the delta
        var netChanges: [String: Int] = [:]
        for tx in transactions {
            netChanges[tx.from, default: 0] -= tx.amount
            netChanges[tx.to, default: 0] += tx.amount
        }
        
        for (mint, expectedDelta) in deltas {
            XCTAssertEqual(netChanges[mint], expectedDelta, 
                         "Mint \(mint) should have net change of \(expectedDelta), got \(netChanges[mint] ?? 0)")
        }
        
        // Print for debugging
        print("\nComplex Rebalancing Test:")
        for tx in transactions {
            print("  \(tx.from) → \(tx.to): \(tx.amount)")
        }
    }
    
    func testBalanceCalculatorThreeWayBalance() {
        // Test case: Three accounts forming a triangle
        let deltas: [Int: Int] = [
            1: -100,
            2: -50,
            3: 150
        ]
        
        let transactions = BalanceCalculator<Int>.calculateTransactions(for: deltas)
        
        XCTAssertEqual(transactions.reduce(0) { $0 + $1.amount }, 150, "Total should be 150")
        
        var netChanges: [Int: Int] = [1: 0, 2: 0, 3: 0]
        for tx in transactions {
            netChanges[tx.from, default: 0] -= tx.amount
            netChanges[tx.to, default: 0] += tx.amount
        }
        
        XCTAssertEqual(netChanges[1], -100)
        XCTAssertEqual(netChanges[2], -50)
        XCTAssertEqual(netChanges[3], 150)
    }
    
    func testBalanceCalculatorRealWorldScenario() {
        // Real-world scenario: User wants to distribute 1000 sats across 3 mints
        // Current: MintA=800, MintB=100, MintC=100
        // Target:  MintA=333, MintB=333, MintC=334 (33.3% each, rounded)
        let deltas: [String: Int] = [
            "MintA": 333 - 800,  // -467
            "MintB": 333 - 100,  // +233
            "MintC": 334 - 100   // +234
        ]
        
        let transactions = BalanceCalculator<String>.calculateTransactions(for: deltas)
        
        print("\nReal World Scenario - Balancing 1000 sats across 3 mints:")
        print("Initial: A=800, B=100, C=100")
        print("Target:  A=333, B=333, C=334")
        print("Deltas:  A=-467, B=+233, C=+234")
        print("Transactions:")
        for tx in transactions {
            print("  \(tx.from) → \(tx.to): \(tx.amount)")
        }
        
        // Verify correctness
        var netChanges: [String: Int] = ["MintA": 0, "MintB": 0, "MintC": 0]
        for tx in transactions {
            netChanges[tx.from, default: 0] -= tx.amount
            netChanges[tx.to, default: 0] += tx.amount
        }
        
        for (mint, expectedDelta) in deltas {
            XCTAssertEqual(netChanges[mint], expectedDelta,
                         "Mint \(mint) should have delta \(expectedDelta), got \(netChanges[mint] ?? 0)")
        }
    }
    
    func testBalanceCalculatorEmptyInput() {
        let deltas: [String: Int] = [:]
        let transactions = BalanceCalculator<String>.calculateTransactions(for: deltas)
        XCTAssertEqual(transactions.count, 0, "Empty input should produce no transactions")
    }
}
