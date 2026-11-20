import XCTest
import Network
@testable import macadamia

/// A local SOCKS server records destination names and refuses every connection.
private final class SOCKSRecorder: @unchecked Sendable {
    let listener: NWListener
    let destination: (String) -> Void
    private var connections: [NWConnection] = []
    private let queue = DispatchQueue(label: "SOCKSRoutingTests")

    init(destination: @escaping (String) -> Void) throws {
        listener = try NWListener(using: .tcp, on: .any)
        self.destination = destination
    }

    func start() async throws -> NWEndpoint {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NWEndpoint, Swift.Error>) in
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    continuation.resume(returning: .hostPort(host: "127.0.0.1", port: listener.port!))
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { return }
                connections.append(connection)
                connection.start(queue: queue)
                Task {
                    do {
                        let greeting = try await Self.read(connection, count: 2)
                        guard greeting[0] == 5 else { throw URLError(.badServerResponse) }
                        _ = try await Self.read(connection, count: Int(greeting[1]))
                        try await Self.write(connection, bytes: [5, 0])
                        let header = try await Self.read(connection, count: 4)
                        let host: String
                        switch header[3] {
                        case 3:
                            let length = try await Self.read(connection, count: 1)[0]
                            host = String(decoding: try await Self.read(connection, count: Int(length)), as: UTF8.self)
                        case 1:
                            host = try await Self.read(connection, count: 4).map(String.init).joined(separator: ".")
                        default: throw URLError(.badServerResponse)
                        }
                        _ = try await Self.read(connection, count: 2)
                        self.destination(host)
                        try await Self.write(connection, bytes: [5, 5, 0, 1, 0, 0, 0, 0, 0, 0])
                    } catch { }
                    connection.cancel()
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        queue.sync {
            listener.cancel()
            connections.forEach { $0.cancel() }
        }
    }

    private static func read(_ connection: NWConnection, count: Int) async throws -> [UInt8] {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
                if let data, data.count == count { continuation.resume(returning: Array(data)) }
                else { continuation.resume(throwing: error ?? NWError.posix(.ECONNRESET)) }
            }
        }
    }

    private static func write(_ connection: NWConnection, bytes: [UInt8]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Swift.Error>) in
            connection.send(content: Data(bytes), completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            })
        }
    }
}

@MainActor
final class SOCKSRoutingTests: XCTestCase {
    private func network(endpoint: NWEndpoint) -> NetworkController {
        let name = "SOCKSRoutingTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defaults.set(true, forKey: NetworkController.preferenceKey)
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        let network = NetworkController(defaults: defaults, isExtension: false)
        network.torEndpoint = { endpoint }
        return network
    }

    func testHTTPAndWebSocketPassDestinationNamesToSOCKS() async throws {
        let onion = String(repeating: "a", count: 56) + ".onion"
        for (scheme, host) in [("http", onion), ("https", "proxy-dns-test.invalid"),
                               ("ws", onion), ("wss", "proxy-dns-test.invalid"),
                               ("https", "203.0.113.1"), ("wss", "203.0.113.1")] {
            let received = expectation(description: "\(scheme) destination reached SOCKS")
            let proxy = try SOCKSRecorder { actual in
                XCTAssertEqual(actual, host)
                received.fulfill()
            }
            let endpoint = try await proxy.start()
            let network = network(endpoint: endpoint)
            defer { proxy.stop(); network.invalidateSessions() }
            let url = URL(string: "\(scheme)://\(host)")!
            let session = try await network.session(for: url)
            if scheme.hasPrefix("ws") {
                let socket = session.webSocketTask(with: url)
                socket.resume()
                await fulfillment(of: [received], timeout: 8)
                socket.cancel(with: .goingAway, reason: nil)
            } else {
                let request = URLRequest(url: url, timeoutInterval: 5)
                _ = try? await session.data(for: request)
                await fulfillment(of: [received], timeout: 2)
            }
        }
    }

    func testTorOnlyBlocksPlatformProxyBypassForLoopback() async throws {
        let bypass = expectation(description: "No direct connection")
        bypass.isInverted = true
        bypass.assertForOverFulfill = false
        let trap = try NWListener(using: .tcp, on: .any)
        let ready = expectation(description: "Direct listener ready")
        trap.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        trap.newConnectionHandler = { connection in bypass.fulfill(); connection.cancel() }
        trap.start(queue: .global())
        defer { trap.cancel() }
        await fulfillment(of: [ready], timeout: 3)
        let proxy = try SOCKSRecorder { _ in }
        let endpoint = try await proxy.start()
        let network = network(endpoint: endpoint)
        defer { proxy.stop(); network.invalidateSessions() }
        let url = URL(string: "https://127.0.0.1:\(try XCTUnwrap(trap.port).rawValue)")!
        do { _ = try await network.data(for: URLRequest(url: url, timeoutInterval: 3)); XCTFail() }
        catch { XCTAssertEqual(error.localizedDescription, NetworkController.Error.localAddress.localizedDescription) }
        await fulfillment(of: [bypass], timeout: 1)
    }
}
