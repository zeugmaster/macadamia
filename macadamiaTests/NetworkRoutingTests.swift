import XCTest
import Network
@testable import macadamia

@MainActor
final class NetworkRoutingTests: XCTestCase {
    private let publicURL = URL(string: "https://mint.example/v1/info")!
    private let onionURL = URL(string: "http://" + String(repeating: "a", count: 56) + ".onion/v1/info")!

    private func controller(torOnly: Bool = false, extensionProcess: Bool = false) -> NetworkController {
        let name = "NetworkRoutingTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defaults.set(torOnly, forKey: NetworkController.preferenceKey)
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return NetworkController(defaults: defaults, isExtension: extensionProcess)
    }

    func testAutomaticAllowsBothRoutesAndTorOnlyConstrainsPublicTraffic() throws {
        XCTAssertEqual(try NetworkController.route(for: publicURL, torOnly: false), .direct)
        XCTAssertEqual(try NetworkController.route(for: onionURL, torOnly: false), .tor)
        XCTAssertEqual(try NetworkController.route(for: publicURL, torOnly: true), .tor)
        XCTAssertEqual(try NetworkController.route(for: onionURL, torOnly: true), .tor)
        for address in ["http://mint.example", "ws://relay.example", "https://user:password@mint.example", "file:///tmp/token", "https://old.onion"] {
            XCTAssertThrowsError(try NetworkController.route(for: URL(string: address)!, torOnly: false))
        }
    }

    func testTorOnlyRejectsLocalAddressesWithoutConstrainingAutomaticMode() throws {
        for host in ["localhost", "localhost.", "mint.localhost", "mint.local", "mint.home.arpa", "mint",
                     "127.0.0.1", "127.1", "2130706433", "0177.0.0.1", "0x7f000001", "10.1.2.3", "172.16.0.1", "192.168.1.2", "169.254.1.1", "100.64.0.1",
                     "[::1]", "[::]", "[fc00::1]", "[fe80::1]", "[::ffff:127.0.0.1]"] {
            let url = URL(string: "https://" + host)!
            XCTAssertThrowsError(try NetworkController.route(for: url, torOnly: true), host)
            XCTAssertEqual(try NetworkController.route(for: url, torOnly: false), .direct)
        }
        XCTAssertEqual(try NetworkController.route(for: URL(string: "https://1.1.1.1")!, torOnly: true), .tor)
    }

    func testBareOnionInputUsesTorWithoutChangingExplicitMintIdentity() throws {
        let host = onionURL.host!
        XCTAssertEqual(URL.fromUserInput(host)?.scheme, "http")
        XCTAssertEqual(URL.fromUserInput("https://" + host)?.scheme, "https")
        XCTAssertEqual(URL.fromUserInput("mint.example")?.scheme, "https")
    }

    func testUnavailableTorDoesNotFallBackOrBlockAutomaticPublicConnections() async throws {
        let network = controller()
        var starts = 0
        network.torEndpoint = { starts += 1; throw NetworkController.Error.unavailable }
        let direct = try await network.session(for: publicURL)
        XCTAssertEqual(starts, 0)
        XCTAssertTrue(direct.configuration.proxyConfigurations.isEmpty)
        do { _ = try await network.session(for: onionURL); XCTFail("Tor failure must propagate") } catch { }
        let second = try await network.session(for: publicURL)
        XCTAssertTrue(second === direct)
        network.setTorOnly(true)
        do { _ = try await network.session(for: publicURL); XCTFail("Tor only must fail closed") } catch { }
        XCTAssertEqual(starts, 2)
        network.invalidateSessions()
    }

    func testModeChangeDuringBootstrapCannotReturnOldSession() async throws {
        let network = controller()
        network.torEndpoint = {
            network.setTorOnly(true)
            return .hostPort(host: "127.0.0.1", port: 9050)
        }
        do { _ = try await network.session(for: onionURL); XCTFail("Mode change must invalidate waiting requests") }
        catch { XCTAssertTrue(error is NetworkController.Error) }
    }

    func testRedirectsKeepRequestsOnTheirOriginalOrigin() async throws {
        let network = controller()
        let session = try await network.session(for: publicURL)
        defer { network.invalidateSessions() }
        let delegate = try XCTUnwrap(session.delegate as? URLSessionTaskDelegate)
        let task = session.dataTask(with: publicURL)
        defer { task.cancel() }
        let response = HTTPURLResponse(url: publicURL, statusCode: 307, httpVersion: nil, headerFields: nil)!
        for (address, allowed) in [("https://mint.example:443/next", true),
                                   ("https://other.example/next", false),
                                   ("http://mint.example/next", false),
                                   ("https://mint.example:444/next", false),
                                   ("https://user@mint.example/next", false)] {
            let request = URLRequest(url: URL(string: address)!)
            let redirected = await withCheckedContinuation { continuation in
                delegate.urlSession?(session, task: task, willPerformHTTPRedirection: response,
                                     newRequest: request) { continuation.resume(returning: $0) }
            }
            XCTAssertEqual(redirected != nil, allowed, address)
        }
    }

    func testProxyDisallowsFallbackAndExtensionRequiresMainAppOnlyForTor() async throws {
        let network = controller(torOnly: true)
        network.torEndpoint = { .hostPort(host: "127.0.0.1", port: 9050) }
        let session = try await network.session(for: publicURL)
        XCTAssertEqual(session.configuration.proxyConfigurations.count, 1)
        XCTAssertFalse(session.configuration.proxyConfigurations[0].allowFailover)
        network.invalidateSessions()

        let extensionNetwork = controller(extensionProcess: true)
        _ = try await extensionNetwork.session(for: publicURL)
        do { _ = try await extensionNetwork.session(for: onionURL); XCTFail() }
        catch { XCTAssertEqual(error.localizedDescription, NetworkController.Error.openMainApp.localizedDescription) }
        extensionNetwork.setTorOnly(true)
        do { _ = try await extensionNetwork.session(for: publicURL); XCTFail() }
        catch { XCTAssertEqual(error.localizedDescription, NetworkController.Error.openMainApp.localizedDescription) }
        extensionNetwork.invalidateSessions()
    }
}
