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
        
        // bitcoin: URI with only an address is invalid (on-chain not supported) but gives a specific message
        let bitcoinOnchain = InputValidator.validate("bitcoin:1234567890", supportedTypes: [.bolt11Invoice, .token, .bolt12Offer, .creq, .publicKey])
        switch bitcoinOnchain {
        case .invalid:
            break // Expected - returns a BIP-321 specific error message
        default:
            XCTFail("Expected invalid result for bitcoin:1234567890")
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

    // MARK: - NUT-26 Codec Tests

    func testNUT26EncodeDecodeRoundtrip() throws {
        let original = CashuSwift.PaymentRequest(
            paymentId: "demo123",
            amount: 1000,
            unit: "sat",
            singleUse: true,
            mints: ["https://mint.example.com"],
            description: "Coffee payment",
            transports: nil,
            lockingCondition: nil
        )

        let encoded = try NUT26.encode(original)
        XCTAssertTrue(encoded.hasPrefix("CREQB1"), "NUT-26 output must start with CREQB1")

        let decoded = try NUT26.decode(encoded)
        XCTAssertEqual(decoded.paymentId, original.paymentId)
        XCTAssertEqual(decoded.amount, original.amount)
        XCTAssertEqual(decoded.unit, original.unit)
        XCTAssertEqual(decoded.singleUse, original.singleUse)
        XCTAssertEqual(decoded.mints, original.mints)
        XCTAssertEqual(decoded.description, original.description)
    }

    func testNUT26DecodeSpecVector() throws {
        // Example vector from the NUT-26 specification
        let specVector = "CREQB1QYQQWER9D4HNZV3NQGQQSQQQQQQQQQQRAQPSQQGQQSQQZQG9QQVXSAR5WPEN5TE0D45KUAPWV4UXZMTSD3JJUCM0D5RQQRJRDANXVET9YPCXZ7TDV4H8GXHR3TQ"
        let decoded = try NUT26.decode(specVector)
        XCTAssertEqual(decoded.paymentId, "demo123")
        XCTAssertEqual(decoded.amount, 1000)
        XCTAssertEqual(decoded.unit, "sat")
        XCTAssertEqual(decoded.singleUse, true)
        XCTAssertEqual(decoded.mints, ["https://mint.example.com"])
        XCTAssertEqual(decoded.description, "Coffee payment")
    }

    func testNUT26DecodeIsCaseInsensitive() throws {
        let upper = "CREQB1QYQQWER9D4HNZV3NQGQQSQQQQQQQQQQRAQPSQQGQQSQQZQG9QQVXSAR5WPEN5TE0D45KUAPWV4UXZMTSD3JJUCM0D5RQQRJRDANXVET9YPCXZ7TDV4H8GXHR3TQ"
        let lower = upper.lowercased()
        let fromUpper = try NUT26.decode(upper)
        let fromLower = try NUT26.decode(lower)
        XCTAssertEqual(fromUpper.paymentId, fromLower.paymentId)
        XCTAssertEqual(fromUpper.amount, fromLower.amount)
    }

    func testNUT26RoundtripAllFields() throws {
        let original = CashuSwift.PaymentRequest(
            paymentId: "test-id-42",
            amount: 21000,
            unit: "msat",
            singleUse: false,
            mints: ["https://mint.a.com", "https://mint.b.com"],
            description: "Multi-mint request",
            transports: [CashuSwift.Transport(type: "post", target: "https://callback.example.com/pay")],
            lockingCondition: nil
        )

        let encoded = try NUT26.encode(original)
        let decoded = try NUT26.decode(encoded)

        XCTAssertEqual(decoded.paymentId, original.paymentId)
        XCTAssertEqual(decoded.amount, original.amount)
        XCTAssertEqual(decoded.unit, original.unit)
        XCTAssertEqual(decoded.singleUse, original.singleUse)
        XCTAssertEqual(decoded.mints, original.mints)
        XCTAssertEqual(decoded.description, original.description)
        XCTAssertEqual(decoded.transports?.count, 1)
        XCTAssertEqual(decoded.transports?.first?.type, "post")
        XCTAssertEqual(decoded.transports?.first?.target, "https://callback.example.com/pay")
    }

    func testInputValidatorDetectsCreqb() {
        let creqbVector = "CREQB1QYQQWER9D4HNZV3NQGQQSQQQQQQQQQQRAQPSQQGQQSQQZQG9QQVXSAR5WPEN5TE0D45KUAPWV4UXZMTSD3JJUCM0D5RQQRJRDANXVET9YPCXZ7TDV4H8GXHR3TQ"
        let result = InputValidator.validate(creqbVector, supportedTypes: [.creq])
        if case .valid(let r) = result {
            XCTAssertEqual(r.type, .creq)
        } else {
            XCTFail("creqb string should be detected as .creq")
        }
    }

    func testParsePaymentRequestDispatch() throws {
        // NUT-18 format
        let nut18 = try CashuSwift.PaymentRequest(
            paymentId: "abc",
            amount: 500,
            unit: "sat",
            singleUse: nil,
            mints: nil,
            description: nil,
            transports: nil,
            lockingCondition: nil
        ).serialize()
        XCTAssertTrue(nut18.hasPrefix("creqA"))
        let fromNUT18 = try parsePaymentRequest(nut18)
        XCTAssertEqual(fromNUT18.paymentId, "abc")

        // NUT-26 format
        let nut26 = try NUT26.encode(CashuSwift.PaymentRequest(
            paymentId: "xyz",
            amount: 100,
            unit: "sat",
            singleUse: nil,
            mints: nil,
            description: nil,
            transports: nil,
            lockingCondition: nil
        ))
        XCTAssertTrue(nut26.hasPrefix("CREQB1"))
        let fromNUT26 = try parsePaymentRequest(nut26)
        XCTAssertEqual(fromNUT26.paymentId, "xyz")
    }
    
    // MARK: - BIP-321 Tests
    
    func testBIP321Detection() {
        XCTAssertTrue(BIP321.isBitcoinURI("bitcoin:175tWpb8K1S7NmH4Zx6rewF9WQrcZv245W"))
        XCTAssertTrue(BIP321.isBitcoinURI("BITCOIN:175tWpb8K1S7NmH4Zx6rewF9WQrcZv245W"))
        XCTAssertTrue(BIP321.isBitcoinURI("Bitcoin:?lightning=lnbc1234"))
        XCTAssertFalse(BIP321.isBitcoinURI("lnbc1234"))
        XCTAssertFalse(BIP321.isBitcoinURI("cashu://token"))
    }
    
    func testBIP321Parsing() {
        // Basic address only
        let basic = BIP321.parse("bitcoin:175tWpb8K1S7NmH4Zx6rewF9WQrcZv245W")
        XCTAssertNotNil(basic)
        XCTAssertEqual(basic?.address, "175tWpb8K1S7NmH4Zx6rewF9WQrcZv245W")
        XCTAssertNil(basic?.lightning)
        
        // Empty address with lightning param
        let lightningOnly = BIP321.parse("bitcoin:?lightning=lnbc420bogusinvoice")
        XCTAssertNotNil(lightningOnly)
        XCTAssertNil(lightningOnly?.address)
        XCTAssertEqual(lightningOnly?.lightning, "lnbc420bogusinvoice")
        
        // Address with lightning param
        let withLightning = BIP321.parse("bitcoin:175tWpb8K1S7NmH4Zx6rewF9WQrcZv245W?lightning=lnbc1234&amount=0.001")
        XCTAssertNotNil(withLightning)
        XCTAssertEqual(withLightning?.address, "175tWpb8K1S7NmH4Zx6rewF9WQrcZv245W")
        XCTAssertEqual(withLightning?.lightning, "lnbc1234")
        XCTAssertEqual(withLightning?.amount, "0.001")
        
        // With label and message
        let labeled = BIP321.parse("bitcoin:175tWpb8K1S7NmH4Zx6rewF9WQrcZv245W?label=Luke-Jr&message=Donation")
        XCTAssertNotNil(labeled)
        XCTAssertEqual(labeled?.label, "Luke-Jr")
        XCTAssertEqual(labeled?.message, "Donation")
        
        // With creq parameter
        let withCreq = BIP321.parse("bitcoin:?creq=creq1234567890&lightning=lnbc1234")
        XCTAssertNotNil(withCreq)
        XCTAssertEqual(withCreq?.creq, "creq1234567890")
        XCTAssertEqual(withCreq?.lightning, "lnbc1234")
        
        // Case-insensitive scheme
        let upperCase = BIP321.parse("BITCOIN:?LIGHTNING=lnbc999")
        XCTAssertNotNil(upperCase)
        XCTAssertEqual(upperCase?.lightning, "lnbc999")
        
        // With BOLT12 offer
        let withBolt12 = BIP321.parse("bitcoin:?lno=lno1someboltoffer")
        XCTAssertNotNil(withBolt12)
        XCTAssertEqual(withBolt12?.lno, "lno1someboltoffer")
        
        // Invalid - not a bitcoin URI
        XCTAssertNil(BIP321.parse("lnbc1234"))
    }
    
    func testBIP321Resolution() {
        let allTypes: [InputView.InputType] = [.bolt11Invoice, .creq]
        
        // Lightning-only URI resolves to bolt11Invoice
        let lightningResult = BIP321.resolve("bitcoin:?lightning=lnbc420bogusinvoice", supportedTypes: allTypes)
        switch lightningResult {
        case .valid(let result):
            XCTAssertEqual(result.type, .bolt11Invoice)
            XCTAssertEqual(result.payload, "lnbc420bogusinvoice")
        case .invalid(let msg):
            XCTFail("Expected valid result, got: \(msg)")
        }
        
        // Creq takes priority over lightning
        let creqPriority = BIP321.resolve("bitcoin:?creq=creq1234567890&lightning=lnbc420bogusinvoice", supportedTypes: allTypes)
        switch creqPriority {
        case .valid(let result):
            XCTAssertEqual(result.type, .creq)
            XCTAssertEqual(result.payload, "creq1234567890")
        case .invalid(let msg):
            XCTFail("Expected valid creq result, got: \(msg)")
        }
        
        // On-chain only gives error
        let onchainOnly = BIP321.resolve("bitcoin:175tWpb8K1S7NmH4Zx6rewF9WQrcZv245W", supportedTypes: allTypes)
        switch onchainOnly {
        case .valid:
            XCTFail("Expected invalid result for on-chain only")
        case .invalid:
            break // Expected
        }
        
        // BOLT12-only gives error
        let bolt12Only = BIP321.resolve("bitcoin:?lno=lno1someboltoffer", supportedTypes: allTypes)
        switch bolt12Only {
        case .valid:
            XCTFail("Expected invalid result for BOLT12-only")
        case .invalid:
            break // Expected
        }
        
        // Lightning with on-chain fallback resolves to lightning
        let withFallback = BIP321.resolve("bitcoin:175tWpb8K1S7NmH4Zx6rewF9WQrcZv245W?lightning=lnbc420bogusinvoice", supportedTypes: allTypes)
        switch withFallback {
        case .valid(let result):
            XCTAssertEqual(result.type, .bolt11Invoice)
            XCTAssertEqual(result.payload, "lnbc420bogusinvoice")
        case .invalid(let msg):
            XCTFail("Expected valid result, got: \(msg)")
        }
    }
    
    func testBIP321ThroughInputValidator() {
        let supportedTypes: [InputView.InputType] = [.bolt11Invoice, .token, .creq, .lightningAddress, .lnurlPay, .merchantCode]
        
        // bitcoin: URI with lightning param should resolve
        let result = InputValidator.validate("bitcoin:?lightning=lnbc420bogusinvoice", supportedTypes: supportedTypes)
        switch result {
        case .valid(let res):
            XCTAssertEqual(res.type, .bolt11Invoice)
            XCTAssertEqual(res.payload, "lnbc420bogusinvoice")
        case .invalid(let msg):
            XCTFail("Expected valid result, got: \(msg)")
        }
        
        // bitcoin: URI with creq should resolve to creq (priority)
        let creqResult = InputValidator.validate("bitcoin:?creq=creq1234567890&lightning=lnbc1234", supportedTypes: supportedTypes)
        switch creqResult {
        case .valid(let res):
            XCTAssertEqual(res.type, .creq)
            XCTAssertEqual(res.payload, "creq1234567890")
        case .invalid(let msg):
            XCTFail("Expected valid result, got: \(msg)")
        }
        
        // bitcoin: URI should no longer be considered "Unsupported Input"
        let onchainResult = InputValidator.validate("bitcoin:175tWpb8K1S7NmH4Zx6rewF9WQrcZv245W", supportedTypes: supportedTypes)
        switch onchainResult {
        case .valid:
            XCTFail("On-chain only should be invalid for this wallet")
        case .invalid:
            break // Expected - but now it gives a specific message rather than "Unsupported Input"
        }
    }
}
