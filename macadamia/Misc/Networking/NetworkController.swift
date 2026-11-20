import Combine
import Foundation
import Network

/// The wallet owns routing and session lifetime; packages receive ordinary URLSessions.
@MainActor
final class NetworkController: ObservableObject {
    static let shared = NetworkController()
    static let preferenceKey = "TorOnly"
    static let policyChanged = Notification.Name("NetworkPolicyChanged")
    static let appGroupID = "group.com.cypherbase.macadamia"

    enum Route: Equatable { case direct, tor }
    enum TorState: Equatable {
        case stopped, connecting, connected, reconnecting, unavailable
        var label: String {
            switch self {
            case .stopped: String(localized: "Tor is idle")
            case .connecting: String(localized: "Connecting to Tor…")
            case .connected: String(localized: "Connected to Tor")
            case .reconnecting: String(localized: "Reconnecting to Tor…")
            case .unavailable: String(localized: "Tor is unavailable")
            }
        }
    }
    enum Error: LocalizedError {
        case invalidURL, insecureURL, localAddress, openMainApp, unavailable, policyChanged
        var errorDescription: String? {
            switch self {
            case .invalidURL: String(localized: "This connection address is invalid.")
            case .insecureURL: String(localized: "Use HTTPS for public addresses. HTTP is supported for onion addresses through Tor.")
            case .localAddress: String(localized: "Local network addresses cannot be reached in Tor only mode.")
            case .openMainApp: String(localized: "Open macadamia to connect through Tor.")
            case .unavailable: String(localized: "Could not connect to Tor. Check your connection and try again.")
            case .policyChanged: String(localized: "The connection mode changed. Please try again.")
            }
        }
    }

    @Published private(set) var torOnly: Bool
    @Published var torState: TorState = .stopped
    private let defaults: UserDefaults
    private let isExtension: Bool
    private let configuration: URLSessionConfiguration
    private var directSession: URLSession?
    private var torSession: URLSession?
    private var generation = 0
    var torEndpoint: (() async throws -> NWEndpoint)?

    init(defaults: UserDefaults = UserDefaults(suiteName: appGroupID)!,
         isExtension: Bool = Bundle.main.bundleURL.pathExtension == "appex",
         configuration: URLSessionConfiguration = .ephemeral) {
        self.configuration = configuration
        self.defaults = defaults
        self.isExtension = isExtension
        torOnly = defaults.bool(forKey: Self.preferenceKey)
    }

    deinit {
        directSession?.invalidateAndCancel()
        torSession?.invalidateAndCancel()
    }

    nonisolated static func isOnion(_ url: URL) -> Bool {
        url.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")).hasSuffix(".onion") == true
    }

    nonisolated static func route(for url: URL, torOnly: Bool) throws -> Route {
        guard let host = url.host?.lowercased(), !host.isEmpty,
              url.user == nil, url.password == nil,
              let scheme = url.scheme?.lowercased(), ["https", "http", "wss", "ws"].contains(scheme) else {
            throw Error.invalidURL
        }
        if isOnion(url) {
            // Reject obsolete v2 addresses and malformed onion names before any DNS lookup.
            let labels = host.trimmingCharacters(in: CharacterSet(charactersIn: ".")).split(separator: ".")
            guard labels.count >= 2, let service = labels.dropLast().last, service.count == 56,
                  service.allSatisfy({ ("a"..."z").contains(String($0)) || ("2"..."7").contains(String($0)) }) else {
                throw Error.invalidURL
            }
            return .tor
        }
        guard scheme == "https" || scheme == "wss" else { throw Error.insecureURL }
        if torOnly, Self.isLocalAddress(host) { throw Error.localAddress }
        return torOnly ? .tor : .direct
    }

    // Foundation can bypass proxies for local destinations even with failover disabled.
    nonisolated private static func isLocalAddress(_ host: String) -> Bool {
        let host = host.trimmingCharacters(in: CharacterSet(charactersIn: ".[]"))
        if !host.contains("."), !host.contains(":") { return true }
        if host.hasSuffix(".localhost") || host.hasSuffix(".local") || host.hasSuffix(".home.arpa") { return true }
        if let address = IPv4Address(host) {
            let bytes = Array(address.rawValue)
            guard host == bytes.map(String.init).joined(separator: ".") else { return true }
            return address.isLoopback || address.isLinkLocal || bytes[0] == 0 || bytes[0] == 10
                || (bytes[0] == 172 && (16...31).contains(bytes[1]))
                || (bytes[0] == 192 && bytes[1] == 168) || bytes[0] >= 224
                || (bytes[0] == 100 && (64...127).contains(bytes[1]))
        }
        // Reject abbreviated or integer IPv4 forms that Foundation may interpret as local IPs.
        if host.split(separator: ".").last?.allSatisfy(\.isNumber) == true { return true }
        if let address = IPv6Address(host) {
            let bytes = Array(address.rawValue)
            if bytes.prefix(10).allSatisfy({ $0 == 0 }), bytes[10] == 255, bytes[11] == 255 {
                return isLocalAddress(bytes.suffix(4).map(String.init).joined(separator: "."))
            }
            return address.isLoopback || address.isLinkLocal || bytes[0] & 0xe0 != 0x20
        }
        return false
    }

    func setTorOnly(_ enabled: Bool) {
        guard enabled != torOnly else { return }
        defaults.set(enabled, forKey: Self.preferenceKey)
        torOnly = enabled
        invalidateSessions()
        NotificationCenter.default.post(name: Self.policyChanged, object: self)
    }

    func refreshPreference() {
        let enabled = defaults.bool(forKey: Self.preferenceKey)
        guard enabled != torOnly else { return }
        torOnly = enabled
        invalidateSessions()
        NotificationCenter.default.post(name: Self.policyChanged, object: self)
    }

    func invalidateSessions() {
        generation += 1
        directSession?.invalidateAndCancel()
        torSession?.invalidateAndCancel()
        directSession = nil
        torSession = nil
    }

    func session(for url: URL) async throws -> URLSession {
        refreshPreference()
        try Task.checkCancellation()
        let route = try Self.route(for: url, torOnly: torOnly)
        if route == .direct {
            if let directSession { return directSession }
            let session = makeSession(route: .direct)
            directSession = session
            return session
        }
        guard !isExtension else { throw Error.openMainApp }
        let currentGeneration = generation
        guard let torEndpoint else { throw Error.unavailable }
        let endpoint = try await torEndpoint()
        try Task.checkCancellation()
        guard generation == currentGeneration else { throw Error.policyChanged }
        if let torSession { return torSession }
        let session = makeSession(route: .tor, endpoint: endpoint)
        torSession = session
        return session
    }

    func data(from url: URL) async throws -> (Data, URLResponse) {
        try await session(for: url).data(from: url)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard let url = request.url else { throw Error.invalidURL }
        return try await session(for: url).data(for: request)
    }

    private func makeSession(route: Route, endpoint: NWEndpoint? = nil) -> URLSession {
        let configuration = self.configuration.copy() as! URLSessionConfiguration
        configuration.timeoutIntervalForRequest = route == .tor ? 90 : 30
        configuration.timeoutIntervalForResource = 180
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        if let endpoint {
            var proxy = ProxyConfiguration(socksv5Proxy: endpoint)
            proxy.allowFailover = false
            configuration.proxyConfigurations = [proxy]
        }
        return URLSession(configuration: configuration, delegate: RedirectPolicy(), delegateQueue: nil)
    }
}

/// Never forward proofs, credentials or a direct request to another origin on redirect.
private final class RedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard let source = response.url, let destination = request.url,
              source.scheme?.lowercased() == destination.scheme?.lowercased(),
              source.host?.lowercased() == destination.host?.lowercased(),
              (source.port ?? defaultPort(source)) == (destination.port ?? defaultPort(destination)),
              destination.user == nil, destination.password == nil else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    private func defaultPort(_ url: URL) -> Int {
        ["https", "wss"].contains(url.scheme?.lowercased() ?? "") ? 443 : 80
    }
}
