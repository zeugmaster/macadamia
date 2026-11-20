import XCTest
@testable import macadamia

/// Opt in with MACADAMIA_TOR_SMOKE=1 in the test runner's environment.
/// Contacts only Tor Project services; never a mint or relay.
@MainActor
final class TorSmokeTests: XCTestCase {
    func testEmbeddedTorHTTPSOnionAndForegroundRecovery() async throws {
        guard ProcessInfo.processInfo.environment["MACADAMIA_TOR_SMOKE"] == "1" else {
            throw XCTSkip("Requires a live Tor network connection")
        }
        let runtime = TorRuntime.shared
        let network = NetworkController.shared
        let originalMode = network.torOnly
        runtime.install()
        network.setTorOnly(true)
        defer { runtime.suspend(); network.setTorOnly(originalMode) }
        runtime.resume()
        do {
            let (data, response) = try await network.data(from: URL(string: "https://check.torproject.org/api/ip")!)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            let result = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(result["IsTor"] as? Bool, true)
        } catch { XCTFail("Tor HTTPS request failed: \(error)") }
        // Official address: https://onion.torproject.org/
        let onion = URL(string: "http://2gzyxa5ihm7nsggfxnu52rck2vv4rvmdlkiu3zzui5du4xyclen53wid.onion/")!
        do {
            let (_, onionResponse) = try await network.data(from: onion)
            XCTAssertTrue((200..<400).contains((onionResponse as? HTTPURLResponse)?.statusCode ?? 0))
        } catch { XCTFail("Onion request failed: \(error)") }
        runtime.suspend()
        runtime.resume()
        let (_, resumedResponse) = try await network.data(from: onion)
        XCTAssertTrue((200..<400).contains((resumedResponse as? HTTPURLResponse)?.statusCode ?? 0))
        XCTAssertEqual(network.torState, .connected)
    }
}
