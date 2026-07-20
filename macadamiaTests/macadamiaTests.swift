import BIP39
@testable import macadamia
import XCTest
import CashuSwift
import CryptoKit
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
                let quoteRequest = CashuSwift.Bolt11.MintQuoteRequest(unit: "sat", amount: 100)
                let mintQuote = try await CashuSwift.Bolt11.requestMintQuote(quoteRequest, from: sendableMint)
                
                // Perform minting with sendable types
                let issueResult = try await CashuSwift.Bolt11.mint(quote: mintQuote, from: sendableMint, seed: seed)
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
        
        // Test NUT-XX quote offers (spec test vector: mint offer for 500 ora
        // via method "branch" with description "Cash deposit")
        let offerVector = "cquoteAp2FteBhodHRwczovL21pbnQuZXhhbXBsZS5jb21hb2RtaW50YWhmYnJhbmNoYXVjb3JhYWEZAfRhdHgkMDE5OGMwZWYtM2YxMS03MDAwLWEzZjctMmY0YjZlMmQ5YzFhYWRsQ2FzaCBkZXBvc2l0"

        switch InputValidator.validate(offerVector, supportedTypes: [.quoteOffer]) {
        case .valid(let res):
            XCTAssertEqual(res.type, .quoteOffer)
            guard let offer = try? CashuSwift.QuoteOffer(encodedOffer: res.payload) else {
                XCTFail("validated quote offer payload must decode")
                break
            }
            XCTAssertEqual(offer.mintURL, "https://mint.example.com")
            XCTAssertEqual(offer.operation, .mint)
            XCTAssertEqual(offer.method.rawValue, "branch")
            XCTAssertEqual(offer.unit, "ora")
            XCTAssertEqual(offer.amount, 500)
            XCTAssertEqual(offer.ticket, "0198c0ef-3f11-7000-a3f7-2f4b6e2d9c1a")
            XCTAssertEqual(offer.offerDescription, "Cash deposit")
        case .invalid:
            XCTFail("Expected valid result for quote offer test vector")
        }

        // A quote offer must be rejected where the caller doesn't accept offers
        switch InputValidator.validate(offerVector, supportedTypes: [.bolt11Invoice, .token]) {
        case .invalid:
            break // Expected
        default:
            XCTFail("Quote offer must be invalid when .quoteOffer is not supported")
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
    
    /// The prototype NUT-20 counter for an offer ticket is the first 4 bytes of
    /// SHA256(ticket) read as a big-endian UInt32, masked to a non-hardened
    /// BIP-32 index. Recomputed here independently with CryptoKit so the app
    /// helper can't drift without this test catching it.
    func testQuoteOfferCounterDerivation() throws {
        let ticket = "0198c0ef-3f11-7000-a3f7-2f4b6e2d9c1a"

        let digest = Data(SHA256.hash(data: Data(ticket.utf8)))
        let expected = digest.prefix(4).withUnsafeBytes {
            UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self))
        } & 0x7FFF_FFFF

        XCTAssertEqual(QuoteOfferTools.nut20Counter(forTicket: ticket), expected)

        // The counter must always be a valid non-hardened derivation index.
        XCTAssertLessThanOrEqual(QuoteOfferTools.nut20Counter(forTicket: ticket), 0x7FFF_FFFF)

        // Deterministic: same ticket, same counter (key recovery after restart
        // depends on this).
        XCTAssertEqual(QuoteOfferTools.nut20Counter(forTicket: ticket),
                       QuoteOfferTools.nut20Counter(forTicket: ticket))
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

    func testNUT26NostrTransportRoundtrip() throws {
        // Test with nostr transport (npub, no relays)
        let npubOriginal = CashuSwift.PaymentRequest(
            paymentId: "nostr-test",
            amount: 500,
            unit: "sat",
            singleUse: nil,
            mints: nil,
            description: nil,
            transports: [CashuSwift.Transport(
                type: CashuSwift.Transport.TransportType.nostr,
                target: "npub1qyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqszqgpqyqs8j9gdm"
            )],
            lockingCondition: nil
        )
        let npubEncoded = try NUT26.encode(npubOriginal)
        let npubDecoded = try NUT26.decode(npubEncoded)
        XCTAssertEqual(npubDecoded.transports?.count, 1)
        XCTAssertEqual(npubDecoded.transports?.first?.type, CashuSwift.Transport.TransportType.nostr)
        // The target should start with "npub"
        XCTAssertTrue(npubDecoded.transports?.first?.target.hasPrefix("npub") == true)
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

    // MARK: - Payment Request Mint Matching

    func testURLMatchesIgnoresTrailingSlashHostCaseAndDefaultPort() {
        let base = URL(string: "https://mint.example.com")!
        XCTAssertTrue(base.matches(URL(string: "https://mint.example.com/")!), "trailing slash should match")
        XCTAssertTrue(base.matches(URL(string: "https://MINT.EXAMPLE.COM")!), "host case should be ignored")
        XCTAssertTrue(base.matches(URL(string: "https://mint.example.com:443")!), "explicit default port should match")
        XCTAssertFalse(base.matches(URL(string: "http://mint.example.com")!), "different scheme should not match")
        XCTAssertFalse(base.matches(URL(string: "https://other.example.com")!), "different host should not match")

        let pathed = URL(string: "https://mint.example.com/cashu")!
        XCTAssertTrue(pathed.matches(URL(string: "https://mint.example.com/cashu/")!), "trailing slash on path should match")
        XCTAssertFalse(pathed.matches(URL(string: "https://mint.example.com")!), "different path should not match")
    }

    @MainActor
    func testAcceptedByPaymentRequestNormalizesMintURLs() throws {
        let context = container.mainContext

        // Local mint stored WITHOUT a trailing slash.
        let mintA = Mint(url: URL(string: "https://mint.a.example.com")!, keysets: [])
        // Local mint stored WITH a trailing slash.
        let mintB = Mint(url: URL(string: "https://mint.b.example.com/")!, keysets: [])
        context.insert(mintA)
        context.insert(mintB)
        let mints = [mintA, mintB]

        // Empty request list -> request accepts any mint.
        XCTAssertEqual(mints.acceptedByPaymentRequest(mintURLs: []).count, 2)

        // Request lists mint A WITH a trailing slash; local copy has none -> must still match.
        let matchA = mints.acceptedByPaymentRequest(mintURLs: ["https://mint.a.example.com/"])
        XCTAssertEqual(matchA.map { $0.url.absoluteString }, ["https://mint.a.example.com"])

        // Request lists mint B WITHOUT a trailing slash; local copy has one -> must still match.
        let matchB = mints.acceptedByPaymentRequest(mintURLs: ["https://mint.b.example.com"])
        XCTAssertEqual(matchB.map { $0.url.absoluteString }, ["https://mint.b.example.com/"])

        // Host case differences must not prevent a match.
        let matchCase = mints.acceptedByPaymentRequest(mintURLs: ["https://MINT.A.EXAMPLE.COM"])
        XCTAssertEqual(matchCase.count, 1)

        // A genuinely absent mint must not match.
        XCTAssertTrue(mints.acceptedByPaymentRequest(mintURLs: ["https://unknown.example.com"]).isEmpty)
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
    
    func testURLcomparison() {
        let url1 = URL(string: "https://mint.minibits.cash/bitcoin")!
        let url2 = URL(string: "https://mint.minibits.cash/Bitcoin")!
        let url3 = URL(string: "https://Mint.minibits.cash/Bitcoin")!
        let url4 = URL(string: url1.absoluteString.uppercased())!
        
        XCTAssertTrue(url2.matches(url3))
        XCTAssertFalse(url1.matches(url2))
        XCTAssertFalse(url3.matches(url4))
        
        // checking how Foundation handles url string input without scheme
        let url5 = URL(string: "macadamia.cash")!
        print(url5.absoluteString)
        print(url5.host() ?? "nil")
        print(url5.scheme ?? "nil")
        
        let url6 = URL(string: "")
        print(url6 ?? "nil")
        
        let url7 = URL(string: "https://mint.macadamia.cash")!
        let url8 = URL(string: "HTTPS://Mint.macadamia.cash:443")!
        let url9 = URL(string: "https://mint.macadamia.cash:5000")!
        let url10 = URL(string: "http://mint.macadamia.cash")!
        let url11 = URL(string: "https://mint.notmacadamia.cash")!
        XCTAssert(url7.matches(url8))
        XCTAssertFalse(url8.matches(url9))
        XCTAssertFalse(url7.matches(url10))
        XCTAssertFalse(url7.matches(url11))
    }

    func testSatAmountFormattingHasNoDecimal() {
        XCTAssertEqual(amountDisplayString(42, unit: .sat), "42 sat")
        XCTAssertEqual(amountDisplayString(0, unit: .sat), "0 sat")
        XCTAssertEqual(amountDisplayString(42, unit: .sat, negative: true), "- 42 sat")
    }

    func testAmountConcealmentRandomizesStarCount() {
        let satAmount = AmountConcealment.concealedString(for: "12345 sat")
        XCTAssertTrue(satAmount.hasSuffix(" sat"))
        let satStars = satAmount.dropLast(" sat".count)
        XCTAssertTrue((4...6).contains(satStars.count))
        XCTAssertTrue(satStars.allSatisfy { $0 == "*" })

        let negativeAmount = AmountConcealment.concealedString(for: "- 42 sat")
        XCTAssertTrue(negativeAmount.hasPrefix("- "))
        XCTAssertTrue(negativeAmount.hasSuffix(" sat"))
        let negativeStars = negativeAmount
            .dropFirst("- ".count)
            .dropLast(" sat".count)
        XCTAssertTrue((1...3).contains(negativeStars.count))
        XCTAssertTrue(negativeStars.allSatisfy { $0 == "*" })

        let fiatAmount = AmountConcealment.concealedString(for: "$1.23")
        XCTAssertTrue(fiatAmount.hasPrefix("$"))
        let fiatStars = fiatAmount.dropFirst()
        XCTAssertTrue((3...5).contains(fiatStars.count))
        XCTAssertTrue(fiatStars.allSatisfy { $0 == "*" })
    }

    func testAmountConcealmentRandomDigitFramesMatchTargetShape() {
        let frame = AmountConcealment.randomDigitString(matching: "- **** sat")
        XCTAssertTrue(frame.hasPrefix("- "))
        XCTAssertTrue(frame.hasSuffix(" sat"))
        let digits = frame.dropFirst("- ".count).dropLast(" sat".count)
        XCTAssertEqual(digits.count, 4)
        XCTAssertTrue(digits.allSatisfy { $0.isNumber })

        let fiatFrame = AmountConcealment.randomDigitString(matching: "$***")
        XCTAssertTrue(fiatFrame.hasPrefix("$"))
        XCTAssertEqual(fiatFrame.dropFirst().count, 3)
        XCTAssertTrue(fiatFrame.dropFirst().allSatisfy { $0.isNumber })
    }

    // MARK: - Legacy store migration (App Store 0.9.x -> current)

    /// Reproduces the crash scenario on disk: a v0.9.x store whose `Event.bolt11MintQuote`
    /// composite attribute predates the non-optional `unit` field, then opens it with the
    /// current (fixed) schema. Verifies the upgrade migrates cleanly (no throw), the formerly
    /// trapping property access is now safe, and the quote data is preserved with unit -> "sat".
    @MainActor
    func testMigrationFromV09PreUnitMintQuotePreservesDataWithoutCrashing() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macadamia-migration-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
            }
        }

        let quoteID = "quote-abc-123"
        let invoice = "lnbc1500n1pjqxyz0pp5testinvoicepayload"
        let expiry = 1_900_000_000

        // 1) Write a 0.9.x-shaped store: events carrying the pre-`unit` MintQuote composite.
        do {
            let legacyContainer = try ModelContainer(for: LegacyV09Schema.Event.self,
                                                     configurations: ModelConfiguration(url: storeURL))
            let context = ModelContext(legacyContainer)
            let legacyQuote = LegacyV09Schema.LegacyMintQuote(quote: quoteID,
                                                              request: invoice,
                                                              paid: nil,
                                                              state: .paid,
                                                              expiry: expiry)
            context.insert(LegacyV09Schema.Event(shortDescription: "Pending Ecash",
                                                 visible: true,
                                                 kind: .pendingMint,
                                                 bolt11MintQuote: legacyQuote,
                                                 amount: 1500))
            context.insert(LegacyV09Schema.Event(shortDescription: "Ecash created",
                                                 visible: true,
                                                 kind: .mint,
                                                 bolt11MintQuote: legacyQuote,
                                                 amount: 1500))
            try context.save()
            // legacyContainer / context go out of scope and release the store here.
        }

        // 2) Open the SAME store with the current schema. This is the upgrade migration that
        //    affected App Store (0.9.x) users perform. It must not throw (no failed migration).
        let currentContainer = try ModelContainer(for: Wallet.self, Proof.self, Mint.self, Event.self,
                                                  configurations: ModelConfiguration(url: storeURL))
        let context = ModelContext(currentContainer)

        let events = try context.fetch(FetchDescriptor<Event>())
        XCTAssertEqual(events.count, 2, "Both legacy events must survive the migration")

        for event in events {
            // 3) This is the exact access that used to trap (EXC_BREAKPOINT) at launch.
            let quote = event.mintQuote
            XCTAssertNotNil(quote, "Legacy quote data must be preserved, not dropped")
            XCTAssertEqual(quote?.quote, quoteID, "Quote ID must survive migration")
            XCTAssertEqual(quote?.request, invoice, "Invoice must survive migration")
            XCTAssertEqual(quote?.unit, "sat", "Missing legacy unit must default to sat, not crash")
            XCTAssertEqual(quote?.state, .paid, "Quote state must survive migration")
            XCTAssertEqual(quote?.expiry, expiry, "Expiry must survive migration")
        }
    }

    /// Verifies the upgrade path for current TestFlight testers on 0.10 build 1/2, whose stores
    /// already use the current quote columns. Both a row with an explicit `unit` and a row whose
    /// `unit` is NULL (migrated up from 0.9.x) must migrate cleanly and read back without crashing.
    @MainActor
    func testMigrationFrom010Build2StorePreservesUnitAndDefaultsNull() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macadamia-migration-b2-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
            }
        }

        // 1) Write a 0.10 build-2-shaped store: one unit-bearing row, one NULL-unit row.
        do {
            let container = try ModelContainer(for: Build2Schema.Event.self,
                                               configurations: ModelConfiguration(url: storeURL))
            let context = ModelContext(container)
            context.insert(Build2Schema.Event(shortDescription: "Ecash created",
                                              visible: true,
                                              kind: .mint,
                                              bolt11MintQuote: .init(quote: "with-unit",
                                                                     request: "lnbc-with-unit",
                                                                     amount: 2100,
                                                                     unit: "sat",
                                                                     state: .issued,
                                                                     expiry: 1_900_000_000),
                                              amount: 2100))
            context.insert(Build2Schema.Event(shortDescription: "Pending Ecash",
                                              visible: true,
                                              kind: .pendingMint,
                                              bolt11MintQuote: .init(quote: "null-unit",
                                                                     request: "lnbc-null-unit",
                                                                     amount: nil,
                                                                     unit: nil,
                                                                     state: .unpaid,
                                                                     expiry: nil),
                                              amount: 500))
            try context.save()
        }

        // 2) Open with the current fixed schema.
        let currentContainer = try ModelContainer(for: Wallet.self, Proof.self, Mint.self, Event.self,
                                                  configurations: ModelConfiguration(url: storeURL))
        let context = ModelContext(currentContainer)
        let events = try context.fetch(FetchDescriptor<Event>())
        XCTAssertEqual(events.count, 2, "Both build-2 events must survive the migration")

        let withUnit = try XCTUnwrap(events.first { $0.mintQuote?.quote == "with-unit" }?.mintQuote)
        XCTAssertEqual(withUnit.request, "lnbc-with-unit")
        XCTAssertEqual(withUnit.unit, "sat", "Explicit unit must be preserved verbatim")
        XCTAssertEqual(withUnit.state, .issued)

        let nullUnit = try XCTUnwrap(events.first { $0.mintQuote?.quote == "null-unit" }?.mintQuote)
        XCTAssertEqual(nullUnit.request, "lnbc-null-unit")
        XCTAssertEqual(nullUnit.unit, "sat", "NULL unit must default to sat, not crash")
        XCTAssertEqual(nullUnit.state, .unpaid)
    }

    // MARK: - Legacy melt quote migration (cashu-swift 0.3.1 shape -> current)

    /// Reproduces a pending payment created on the App Store build: its `bolt11MeltQuote` was
    /// serialized with the pre-overhaul cashu-swift 0.3.1 shape, where the invoice and unit lived
    /// inside a nested `quoteRequest` and there was no top-level `unit`. The current
    /// `CashuSwift.Bolt11.MeltQuote` makes `unit` a required top-level field, so the plain
    /// `try?` decode returns nil on these rows — which is exactly why the melt view showed a
    /// pending payment with no quote info and "Check Payment State" did nothing. Verifies the
    /// legacy fallback recovers the quote instead of dropping it.
    @MainActor
    func testLegacyMeltQuoteDecodesViaFallbackWithNestedInvoiceAndUnitDefault() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macadamia-melt-migration-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
            }
        }

        let quoteID = "melt-quote-xyz"
        let invoice = "lnbc2500n1pjqmeltinvoicepayload"
        let amount = 2500
        let feeReserve = 5
        let expiry = 1_900_000_000

        // 1) Encode an old-shape MeltQuote exactly as cashu-swift 0.3.1 would have, and store it
        //    in the same `bolt11MeltQuoteData` Data column the current model uses.
        let legacyData = try JSONEncoder().encode(
            LegacyMeltSchema.LegacyMeltQuote(quote: quoteID,
                                             amount: amount,
                                             feeReserve: feeReserve,
                                             paid: false,
                                             expiry: expiry,
                                             paymentPreimage: nil,
                                             quoteRequest: .init(unit: "sat",
                                                                 request: invoice,
                                                                 options: nil),
                                             state: .unpaid))

        do {
            let legacyContainer = try ModelContainer(for: LegacyMeltSchema.Event.self,
                                                     configurations: ModelConfiguration(url: storeURL))
            let context = ModelContext(legacyContainer)
            context.insert(LegacyMeltSchema.Event(shortDescription: "Pending Payment",
                                                  visible: true,
                                                  kind: .pendingMelt,
                                                  bolt11MeltQuoteData: legacyData,
                                                  amount: amount))
            try context.save()
        }

        // 2) Open the SAME store with the current schema and read the quote back through the
        //    real computed property (which runs the fallback).
        let currentContainer = try ModelContainer(for: Wallet.self, Proof.self, Mint.self, Event.self,
                                                  configurations: ModelConfiguration(url: storeURL))
        let context = ModelContext(currentContainer)
        let events = try context.fetch(FetchDescriptor<Event>())
        XCTAssertEqual(events.count, 1, "The legacy melt event must survive the migration")

        let quote = try XCTUnwrap(events.first?.bolt11MeltQuote,
                                  "Legacy melt quote must decode via the fallback, not return nil")
        XCTAssertEqual(quote.quote, quoteID, "Quote ID must survive")
        XCTAssertEqual(quote.request, invoice, "Invoice must be recovered from nested quoteRequest")
        XCTAssertEqual(quote.amount, amount, "Amount must survive")
        XCTAssertEqual(quote.feeReserve, feeReserve, "Fee reserve must survive")
        XCTAssertEqual(quote.unit, "sat", "Missing top-level unit must default to sat")
        XCTAssertEqual(quote.state, .unpaid, "Quote state must survive")
        XCTAssertEqual(quote.expiry, expiry, "Expiry must survive")
    }

    /// A row written by the current build (new top-level `unit`) must still decode directly,
    /// proving the fallback doesn't interfere with the happy path.
    @MainActor
    func testCurrentShapeMeltQuoteStillDecodes() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("macadamia-melt-current-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
            }
        }

        let current = CashuSwift.Bolt11.MeltQuote(quote: "current-quote",
                                                  request: "lnbc-current",
                                                  amount: 1000,
                                                  unit: "sat",
                                                  feeReserve: 2,
                                                  state: .paid,
                                                  expiry: 1_900_000_000,
                                                  paymentPreimage: "preimage123")
        let data = try JSONEncoder().encode(current)

        do {
            let legacyContainer = try ModelContainer(for: LegacyMeltSchema.Event.self,
                                                     configurations: ModelConfiguration(url: storeURL))
            let context = ModelContext(legacyContainer)
            context.insert(LegacyMeltSchema.Event(shortDescription: "Payment",
                                                  visible: true,
                                                  kind: .melt,
                                                  bolt11MeltQuoteData: data,
                                                  amount: 1000))
            try context.save()
        }

        let currentContainer = try ModelContainer(for: Wallet.self, Proof.self, Mint.self, Event.self,
                                                  configurations: ModelConfiguration(url: storeURL))
        let context = ModelContext(currentContainer)
        let quote = try XCTUnwrap(try context.fetch(FetchDescriptor<Event>()).first?.bolt11MeltQuote)
        XCTAssertEqual(quote.quote, "current-quote")
        XCTAssertEqual(quote.request, "lnbc-current")
        XCTAssertEqual(quote.unit, "sat")
        XCTAssertEqual(quote.feeReserve, 2)
        XCTAssertEqual(quote.paymentPreimage, "preimage123")
        XCTAssertEqual(quote.state, .paid)
    }

    /// Non-BOLT11 quotes are persisted through a method-tagged envelope in the same Data
    /// column BOLT11 quotes use. The envelope must round-trip to the right concrete type,
    /// must never leak through the BOLT11-typed accessors, and BOLT11 quotes written through
    /// the method-agnostic accessor must keep their legacy byte layout.
    @MainActor
    func testStoredQuoteEnvelopeRoundtrip() throws {
        let container = try ModelContainer(for: Wallet.self, Proof.self, Mint.self, Event.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let mnemonic = Mnemonic()
        let wallet = Wallet(mnemonic: mnemonic.phrase.joined(separator: " "), seed: String(bytes: mnemonic.seed))
        context.insert(wallet)

        // Generic (custom method) melt quote → envelope write.
        let meltRaw: CashuSwift.JSONObject = [
            "quote": .string("generic-melt-id"),
            "amount": .integer(42),
            "unit": .string("usd"),
            "fee_reserve": .integer(1),
            "state": .string("UNPAID"),
            "expiry": .integer(1_900_000_000),
            "method": .string("credit")
        ]
        let genericMelt = CashuSwift.Generic.MeltQuote(method: CashuSwift.PaymentMethodID(rawValue: "credit"),
                                                       quote: "generic-melt-id",
                                                       amount: 42,
                                                       unit: "usd",
                                                       feeReserve: 1,
                                                       state: .unpaid,
                                                       expiry: 1_900_000_000,
                                                       paymentPreimage: nil,
                                                       change: nil,
                                                       raw: meltRaw)
        let genericMeltEvent = Event.pendingMeltEvent(unit: Unit(code: "usd"),
                                                      shortDescription: "Pending Payment",
                                                      wallet: wallet,
                                                      quote: genericMelt,
                                                      amount: 42,
                                                      expiration: nil,
                                                      mints: [])
        context.insert(genericMeltEvent)
        try context.save()

        let restoredMelt = try XCTUnwrap(genericMeltEvent.storedMeltQuote)
        XCTAssertTrue(restoredMelt is CashuSwift.Generic.MeltQuote, "envelope must restore the concrete type")
        XCTAssertEqual(restoredMelt.quote, "generic-melt-id")
        XCTAssertEqual(restoredMelt.method.rawValue, "credit")
        XCTAssertEqual(restoredMelt.unit, "usd")
        XCTAssertEqual(restoredMelt.amount, 42)
        XCTAssertNil(genericMeltEvent.bolt11MeltQuote,
                     "an envelope row must not decode through the BOLT11-typed accessor")

        // BOLT11 melt quote through the method-agnostic accessor → legacy byte layout.
        let bolt11 = CashuSwift.Bolt11.MeltQuote(quote: "bolt11-melt-id",
                                                 request: "lnbc-envelope-test",
                                                 amount: 21,
                                                 unit: "sat",
                                                 feeReserve: 2,
                                                 state: .unpaid,
                                                 expiry: nil)
        let bolt11Event = Event.pendingMeltEvent(unit: .sat,
                                                 shortDescription: "Pending Payment",
                                                 wallet: wallet,
                                                 quote: bolt11,
                                                 amount: 21,
                                                 expiration: nil,
                                                 mints: [])
        context.insert(bolt11Event)
        try context.save()

        XCTAssertEqual(bolt11Event.bolt11MeltQuote?.quote, "bolt11-melt-id",
                       "BOLT11 quotes must remain readable through the legacy accessor")
        XCTAssertTrue(bolt11Event.storedMeltQuote is CashuSwift.Bolt11.MeltQuote)
        XCTAssertEqual(bolt11Event.storedMeltQuote?.quote, "bolt11-melt-id")

        // Generic mint quote → envelope write on the mint quote column.
        let mintRaw: CashuSwift.JSONObject = [
            "quote": .string("generic-mint-id"),
            "request": .string(""),
            "unit": .string("usd"),
            "amount": .integer(42),
            "state": .string("PAID"),
            "method": .string("credit")
        ]
        let genericMint = CashuSwift.Generic.MintQuote(method: CashuSwift.PaymentMethodID(rawValue: "credit"),
                                                       quote: "generic-mint-id",
                                                       request: "",
                                                       unit: "usd",
                                                       amount: 42,
                                                       state: .paid,
                                                       expiry: nil,
                                                       raw: mintRaw)
        let mintEvent = Event(date: Date(),
                              unit: Unit(code: "usd"),
                              shortDescription: "Pending Ecash",
                              visible: true,
                              kind: .pendingMint,
                              wallet: wallet)
        mintEvent.storedMintQuote = genericMint
        context.insert(mintEvent)
        try context.save()

        let restoredMint = try XCTUnwrap(mintEvent.storedMintQuote)
        XCTAssertTrue(restoredMint is CashuSwift.Generic.MintQuote)
        XCTAssertEqual(restoredMint.quote, "generic-mint-id")
        XCTAssertEqual(restoredMint.method.rawValue, "credit")
        XCTAssertEqual(restoredMint.unit, "usd")
        XCTAssertNil(mintEvent.mintQuote,
                     "an envelope row must not decode through the BOLT11-typed accessor")
    }
}

/// Minimal stand-in for the v0.9.x persisted schema, used only to write a pre-migration store.
///
/// The single relevant difference from the current schema is `bolt11MintQuote`: in 0.9.x it was a
/// composite attribute of a `MintQuote` whose Codable shape had no `unit`/`amount` (cashu-swift 0.3.1).
/// `Event` here deliberately uses the same entity name and the real `AppSchemaV1.Event.Kind` so the
/// current schema recognises the store as the same `Event` entity and lightweight-migrates it.
private enum LegacyV09Schema {
    /// The pre-`unit` `CashuSwift.Bolt11.MintQuote` shape, as persisted by v0.9.x.
    struct LegacyMintQuote: Codable {
        var quote: String
        var request: String
        var paid: Bool?
        var state: CashuSwift.QuoteState?
        var expiry: Int?
        // No `unit`, no `amount` — exactly the shape that traps the unpatched current build.
    }

    @Model
    final class Event {
        @Attribute(.unique) var eventID: UUID
        var date: Date
        var shortDescription: String
        var visible: Bool
        var kind: AppSchemaV1.Event.Kind
        var bolt11MintQuote: LegacyMintQuote?
        var amount: Int?

        init(eventID: UUID = UUID(),
             date: Date = Date(),
             shortDescription: String,
             visible: Bool,
             kind: AppSchemaV1.Event.Kind,
             bolt11MintQuote: LegacyMintQuote?,
             amount: Int?) {
            self.eventID = eventID
            self.date = date
            self.shortDescription = shortDescription
            self.visible = visible
            self.kind = kind
            self.bolt11MintQuote = bolt11MintQuote
            self.amount = amount
        }
    }
}

/// Stand-in for the 0.10 build 1/2 (TestFlight) persisted schema. By then `bolt11MintQuote`
/// already had the current column set {quote, request, amount, unit, state, expiry}. A real
/// build-1/2 store mixes rows whose `unit` is set (events those builds created) with rows whose
/// `unit` is NULL (events migrated up from 0.9.x). `unit` is modelled optional here so we can
/// write both kinds of row.
private enum Build2Schema {
    struct Build2MintQuote: Codable {
        var quote: String
        var request: String
        var amount: Int?
        var unit: String?
        var state: CashuSwift.QuoteState?
        var expiry: Int?
    }

    @Model
    final class Event {
        @Attribute(.unique) var eventID: UUID
        var date: Date
        var shortDescription: String
        var visible: Bool
        var kind: AppSchemaV1.Event.Kind
        var bolt11MintQuote: Build2MintQuote?
        var amount: Int?

        init(eventID: UUID = UUID(),
             date: Date = Date(),
             shortDescription: String,
             visible: Bool,
             kind: AppSchemaV1.Event.Kind,
             bolt11MintQuote: Build2MintQuote?,
             amount: Int?) {
            self.eventID = eventID
            self.date = date
            self.shortDescription = shortDescription
            self.visible = visible
            self.kind = kind
            self.bolt11MintQuote = bolt11MintQuote
            self.amount = amount
        }
    }
}

/// Stand-in for a store whose `Event.bolt11MeltQuote` JSON predates the cashu-swift
/// payment-method overhaul. Unlike the mint quote, the melt quote was always a manually
/// serialized `Data` column (`bolt11MeltQuoteData`), so this models that exact column name and
/// writes pre-overhaul bytes into it. `LegacyMeltQuote` mirrors the cashu-swift 0.3.1
/// `Bolt11.MeltQuote` Codable shape: top-level `quote`/`amount`/`fee_reserve` plus a nested
/// `quoteRequest` carrying `unit` and the invoice, and no top-level `unit`.
private enum LegacyMeltSchema {
    struct LegacyMeltQuote: Codable {
        struct Request: Codable {
            var unit: String?
            var request: String?
            var options: String?   // always nil in these tests; real shape is irrelevant here
        }
        var quote: String
        var amount: Int
        var feeReserve: Int
        var paid: Bool?
        var expiry: Int?
        var paymentPreimage: String?
        var quoteRequest: Request?
        var state: CashuSwift.QuoteState?

        enum CodingKeys: String, CodingKey {
            case quote, amount, paid, expiry, quoteRequest, state
            case feeReserve = "fee_reserve"
            case paymentPreimage = "payment_preimage"
        }
    }

    @Model
    final class Event {
        @Attribute(.unique) var eventID: UUID
        var date: Date
        var shortDescription: String
        var visible: Bool
        var kind: AppSchemaV1.Event.Kind
        var bolt11MeltQuoteData: Data?
        var amount: Int?

        init(eventID: UUID = UUID(),
             date: Date = Date(),
             shortDescription: String,
             visible: Bool,
             kind: AppSchemaV1.Event.Kind,
             bolt11MeltQuoteData: Data?,
             amount: Int?) {
            self.eventID = eventID
            self.date = date
            self.shortDescription = shortDescription
            self.visible = visible
            self.kind = kind
            self.bolt11MeltQuoteData = bolt11MeltQuoteData
            self.amount = amount
        }
    }
}
