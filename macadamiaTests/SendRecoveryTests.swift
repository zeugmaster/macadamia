import XCTest
import SwiftData
import CashuSwift
@testable import macadamia

@MainActor
final class SendRecoveryTests: XCTestCase {
    private func wallet(at url: URL) throws -> (ModelContainer, Wallet, Mint, Proof) {
        let container = try ModelContainer(for: Wallet.self, Mint.self, Proof.self, Event.self, NostrKeypair.self, NostrMessage.self,
                                          configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let wallet = Wallet(mnemonic: "test", seed: String(repeating: "ab", count: 32))
        let keys = Dictionary(uniqueKeysWithValues: (0...10).map { (String(1 << $0), "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798") })
        let id = "0011223344556677"
        let data = try JSONSerialization.data(withJSONObject: ["id": id, "unit": "sat", "active": true, "keys": keys,
                                                             "input_fee_ppk": 0, "derivationCounter": 7])
        let keyset = try JSONDecoder().decode(CashuSwift.Keyset.self, from: data)
        let mint = Mint(url: url, keysets: [keyset])
        mint.wallet = wallet
        container.mainContext.insert(wallet)
        container.mainContext.insert(mint)
        let proof = try XCTUnwrap(mint.addProofs([CashuSwift.Proof(keysetID: id, amount: 8, secret: "input", C: keys["8"]!)],
            to: container.mainContext, increaseDerivationCounter: false).first)
        try container.mainContext.save()
        return (container, wallet, mint, proof)
    }

    func testAmbiguousSendKeepsReservationAndRecoversWithoutSecondSwap() async throws {
        let stub = try MintHTTPStub { request in
            if request.url?.path == "/v1/swap" { throw URLError(.timedOut) }
            XCTAssertEqual(request.url?.path, "/v1/restore")
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            let outputs = try XCTUnwrap(body["outputs"] as? [[String: Any]])
            let signatures = outputs.map { ["id": $0["id"]!, "amount": $0["amount"]!, "C_": $0["B_"]!] }
            return try JSONSerialization.data(withJSONObject: ["outputs": outputs, "signatures": signatures])
        }
        defer { stub.remove() }
        let (container, wallet, mint, proof) = try wallet(at: stub.url)
        do {
            _ = try await AppSchemaV1.createToken(mint: mint, activeWallet: wallet, amount: 3, unit: .sat,
                memo: "test", modelContext: container.mainContext, lockingKey: nil, network: await stub.network)
            XCTFail("Expected pending send")
        } catch { XCTAssertTrue(error is AppSchemaV1.SendError) }
        let event = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<Event>()).first)
        XCTAssertNotNil(event.sendContextData)
        XCTAssertNil(event.token)
        XCTAssertEqual(proof.state, .pending)
        let counter = mint.keysets[0].derivationCounter
        XCTAssertEqual(counter, 11)
        let token = try await AppSchemaV1.recoverSend(event: event, modelContext: container.mainContext, network: await stub.network)
        XCTAssertEqual(token.sum(), 3)
        XCTAssertNil(event.sendContextData)
        XCTAssertEqual(proof.state, .spent)
        XCTAssertEqual(mint.balance(for: .sat), 5)
        XCTAssertEqual(mint.keysets[0].derivationCounter, counter)
        XCTAssertEqual(stub.requests.map { $0.url!.path }, ["/v1/swap", "/v1/restore"])
    }

    func testExactTokenIsOfflineEvenWhenTorOnlyCannotConnect() async throws {
        let (container, wallet, mint, proof) = try wallet(at: URL(string: "https://offline.invalid")!)
        let network = NetworkController.shared
        let original = network.torOnly
        let endpoint = network.torEndpoint
        network.setTorOnly(true)
        network.torEndpoint = { XCTFail("Offline send must not start Tor"); throw NetworkController.Error.unavailable }
        defer { network.torEndpoint = endpoint; network.setTorOnly(original) }
        let token = try await AppSchemaV1.createToken(mint: mint, activeWallet: wallet, amount: 8, unit: .sat,
            memo: "", modelContext: container.mainContext, lockingKey: nil)
        XCTAssertEqual(token.sum(), 8)
        XCTAssertEqual(proof.state, .pending)
        XCTAssertEqual(mint.keysets[0].derivationCounter, 7)
    }
}
