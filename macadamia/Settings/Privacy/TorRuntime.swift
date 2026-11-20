import CTor
import TorCore
import Foundation
import Network

/// One embedded Tor process per app, kept warm while foregrounded.
@MainActor
final class TorRuntime {
    static let shared = TorRuntime()
    private var configuration: TorConfiguration?
    private var thread: TorThread?
    private var controller: TorController?
    private var circuitObserver: Any?
    private var established = false
    private var authenticated = false
    private var authenticationFailed = false
    private var socksEndpoint: NWEndpoint?
    private var connectionTask: Task<NWEndpoint, Swift.Error>?
    private var attempt = UUID()
    private var completedAttempt: UUID?
    private var foreground = true
    private let network = NetworkController.shared

    func install() {
        network.torEndpoint = { try await self.endpoint() }
    }

    func endpoint() async throws -> NWEndpoint {
        guard foreground else { throw NetworkController.Error.unavailable }
        if established, thread?.isFinished == false, let socksEndpoint { return socksEndpoint }
        let task: Task<NWEndpoint, Swift.Error>
        let id: UUID
        if let connectionTask {
            task = connectionTask
            id = attempt
        } else {
            id = UUID()
            attempt = id
            task = Task {
                defer {
                    if attempt == id {
                        completedAttempt = id
                        connectionTask = nil
                    }
                }
                return try await connect()
            }
            connectionTask = task
        }
        // Cancel a waiting request promptly without cancelling other requests' bootstrap.
        while completedAttempt != id {
            try Task.checkCancellation()
            guard attempt == id else { throw CancellationError() }
            try await Task.sleep(for: .milliseconds(100))
        }
        try Task.checkCancellation()
        return try await task.value
    }

    func suspend() {
        foreground = false
        attempt = UUID()
        connectionTask?.cancel()
        connectionTask = nil
        controller?.setConfForKey("DisableNetwork", withValue: "1", completion: nil)
        closeControlConnection()
        socksEndpoint = nil
        established = false
        network.invalidateSessions()
        network.torState = thread == nil ? .stopped : .reconnecting
    }

    func resume() {
        foreground = true
        network.refreshPreference()
        if network.torOnly || thread != nil {
            Task { _ = try? await endpoint() }
        }
    }

    private func connect() async throws -> NWEndpoint {
        let attemptID = attempt
        network.torState = thread == nil ? .connecting : .reconnecting
        do {
            try startThreadIfNeeded()
            let deadline = Date().addingTimeInterval(120)
            if !authenticated {
                closeControlConnection()
                authenticationFailed = false
                // Tor writes its control address and authentication cookie asynchronously.
                while controller == nil {
                    try checkDeadline(deadline)
                    if let file = configuration?.controlPortFile,
                       let content = try? String(contentsOf: file, encoding: .utf8),
                       content.hasPrefix("PORT=127.0.0.1:"),
                       let portText = content.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":").last,
                       let port = UInt16(portText), port > 0,
                       let cookie = configuration?.cookie, cookie.count == 32 {
                        let candidate = TorController(socketHost: "127.0.0.1", port: port)
                        if candidate.isConnected {
                            controller = candidate
                            candidate.authenticate(with: cookie) { [weak self, weak candidate] success, _ in
                                Task { @MainActor in
                                    guard let self, let candidate, self.controller === candidate else { return }
                                    self.authenticated = success
                                    self.authenticationFailed = !success
                                }
                            }
                        }
                    }
                    if controller == nil { try await Task.sleep(for: .milliseconds(100)) }
                }
                while !authenticated {
                    try checkDeadline(deadline)
                    guard !authenticationFailed else { throw NetworkController.Error.unavailable }
                    try await Task.sleep(for: .milliseconds(100))
                }
            }
            guard let activeController = controller else { throw NetworkController.Error.unavailable }
            // TorController matches command replies through observers; do not pipeline commands.
            var enabled: Bool?
            activeController.setConfForKey("DisableNetwork", withValue: "0") { success, _ in
                Task { @MainActor in enabled = success }
            }
            while enabled == nil {
                try checkDeadline(deadline)
                try await Task.sleep(for: .milliseconds(100))
            }
            guard enabled == true else { throw NetworkController.Error.unavailable }
            activeController.getSocks5Address { [weak self, weak activeController] host, port, _ in
                Task { @MainActor in
                    guard let self, let activeController, self.controller === activeController,
                          host == "127.0.0.1" || host == "localhost", let raw = port?.uint16Value,
                          let port = NWEndpoint.Port(rawValue: raw) else { return }
                    self.socksEndpoint = .hostPort(host: "127.0.0.1", port: port)
                }
            }
            while socksEndpoint == nil {
                try checkDeadline(deadline)
                try await Task.sleep(for: .milliseconds(100))
            }
            if circuitObserver == nil {
                circuitObserver = activeController.addObserver(forCircuitEstablished: { [weak self, weak activeController] ready in
                    Task { @MainActor in
                        guard let self, let activeController, self.controller === activeController, self.foreground else { return }
                        self.established = ready
                        if ready { self.network.torState = .connected }
                        else if self.network.torState == .connected { self.network.torState = .reconnecting }
                    }
                })
            }
            while !established {
                try checkDeadline(deadline)
                try await Task.sleep(for: .milliseconds(100))
            }
            network.torState = .connected
            return socksEndpoint!
        } catch {
            guard attempt == attemptID else { throw CancellationError() }
            controller?.setConfForKey("DisableNetwork", withValue: "1", completion: nil)
            closeControlConnection()
            established = false
            socksEndpoint = nil
            if foreground { network.torState = .unavailable }
            if error is CancellationError { throw error }
            throw NetworkController.Error.unavailable
        }
    }

    private func closeControlConnection() {
        controller?.removeObserver(circuitObserver)
        circuitObserver = nil
        // TorController.disconnect() sends SHUTDOWN; QUIT closes only the control connection.
        controller?.sendCommand("QUIT", arguments: nil, data: nil) { _, _, stop in
            stop.pointee = true
            return true
        }
        controller = nil
        authenticated = false
    }

    private func checkDeadline(_ deadline: Date) throws {
        try Task.checkCancellation()
        guard foreground, Date() < deadline, thread?.isFinished != true else {
            throw NetworkController.Error.unavailable
        }
    }

    private func startThreadIfNeeded() throws {
        guard thread == nil else { return }
        let manager = FileManager.default
        var directory = try manager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                        appropriateFor: nil, create: true).appending(path: "Tor", directoryHint: .isDirectory)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700, .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var resources = URLResourceValues()
        resources.isExcludedFromBackup = true
        try directory.setResourceValues(resources)
        let config = TorConfiguration()
        config.dataDirectory = directory
        config.ignoreMissingTorrc = true
        config.cookieAuthentication = true
        config.autoControlPort = true
        config.clientOnly = true
        config.avoidDiskWrites = true
        config.options = ["SocksPort": "127.0.0.1:auto", "SafeSocks": "1", "DisableNetwork": "1"]
        // Do not consume a previous process's stale control address or cookie.
        for name in ["controlport", "control_auth_cookie"] {
            let file = directory.appending(path: name)
            if manager.fileExists(atPath: file.path) { try manager.removeItem(at: file) }
        }
        configuration = config
        let thread = TorThread(configuration: config)
        self.thread = thread
        thread.start()
    }
}
