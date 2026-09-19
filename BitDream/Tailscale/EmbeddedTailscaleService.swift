import Foundation
import Network

actor EmbeddedTailscaleService {
    static let shared = EmbeddedTailscaleService()

    private let driver: any TailscaleDriving
    private let directory: @Sendable () throws -> URL
    private var generation: UInt64 = 0
    private var operationEpoch: UInt64 = 0
    private var isSigningOut = false
    private var session: URLSession?

    init(
        driver: any TailscaleDriving = TailscaleNativeDriver(),
        directory: @escaping @Sendable () throws -> URL = { try TailscaleStateDirectory().url }
    ) {
        self.driver = driver
        self.directory = directory
    }

    func status(startIfNeeded: Bool = false) async throws -> TailscaleSnapshot {
        guard !isSigningOut else { throw TailscaleError.connectionChanged }
        let epoch = operationEpoch
        let request = try TailscaleNativeRequest(
            action: startIfNeeded ? "start" : "status",
            directory: startIfNeeded ? directory().path : nil,
            hostname: startIfNeeded ? "bitdream" : nil
        )
        let snapshot = try await driver.perform(request)
        guard epoch == operationEpoch, !isSigningOut, snapshot.generation >= generation else {
            throw TailscaleError.connectionChanged
        }
        if generation != snapshot.generation || !snapshot.isReady {
            invalidateSession()
            generation = snapshot.generation
        }
        try Task.checkCancellation()
        return snapshot
    }

    func beginLogin() async throws -> TailscaleSnapshot {
        _ = try await status(startIfNeeded: true)
        let epoch = operationEpoch
        _ = try await driver.perform(TailscaleNativeRequest(action: "login"))
        guard epoch == operationEpoch else { throw TailscaleError.connectionChanged }
        return try await status()
    }

    /// An explicit account transition invalidates sessions before contacting Go.
    /// Failure keeps the identity on disk and lets the user retry logout.
    func signOut() async throws {
        _ = try await status(startIfNeeded: true)
        guard !isSigningOut else { throw TailscaleError.connectionChanged }
        isSigningOut = true
        operationEpoch &+= 1
        invalidateSession()
        defer { isSigningOut = false }
        let result = try await driver.perform(TailscaleNativeRequest(action: "logout"))
        generation = result.generation
    }

    func disconnect() async throws {
        guard !isSigningOut else { throw TailscaleError.connectionChanged }
        isSigningOut = true
        operationEpoch &+= 1
        invalidateSession()
        defer { isSigningOut = false }
        let result = try await driver.perform(TailscaleNativeRequest(action: "stop"))
        generation = result.generation
    }

    func sender(accountID: String, endpoint: TransmissionEndpoint) async throws -> TailscaleRequestSender {
        let snapshot = try await readySnapshot(accountID: accountID)
        try Self.validatePeer(endpoint, snapshot: snapshot)
        return TailscaleRequestSender(
            service: self, accountID: accountID, generation: snapshot.generation, endpoint: endpoint
        )
    }

    func send(
        _ request: URLRequest, accountID: String,
        endpoint: TransmissionEndpoint
    ) async throws -> (Data, HTTPURLResponse) {
        guard request.url == endpoint.rpcURL else { throw TailscaleError.untrustedRedirect }
        let snapshot = try await readySnapshot(accountID: accountID)
        try Self.validatePeer(endpoint, snapshot: snapshot)
        if session == nil { session = try Self.makeSession(snapshot: snapshot) }
        guard let session else { throw TailscaleError.unavailable }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw TransmissionError.invalidResponse }
        if (300..<400).contains(response.statusCode) { throw TailscaleError.untrustedRedirect }
        return (data, response)
    }

    private func readySnapshot(accountID: String) async throws -> TailscaleSnapshot {
        guard !accountID.isEmpty else { throw TailscaleError.accountMismatch }
        let deadline = ContinuousClock.now.advanced(by: .seconds(20))
        while true {
            let snapshot = try await status(startIfNeeded: true)
            if let current = snapshot.accountID, current != accountID { throw TailscaleError.accountMismatch }
            if snapshot.isReady { return snapshot }
            if snapshot.state == "NeedsLogin" { throw TailscaleError.signInRequired }
            if snapshot.state == "NeedsMachineAuth" { throw TailscaleError.approvalRequired }
            guard ContinuousClock.now < deadline else { throw TailscaleError.unavailable }
            try await Task.sleep(for: .milliseconds(500))
        }
    }

    private static func validatePeer(_ endpoint: TransmissionEndpoint, snapshot: TailscaleSnapshot) throws {
        guard snapshot.peers.filter({ $0.matches(host: endpoint.host) }).count == 1 else {
            throw TailscaleError.peerUnavailable
        }
    }

    private func invalidateSession() {
        session?.invalidateAndCancel()
        session = nil
    }

    private static func makeSession(snapshot: TailscaleSnapshot) throws -> URLSession {
        guard let port = snapshot.proxyPort, let nwPort = NWEndpoint.Port(rawValue: port),
              let password = snapshot.proxyPassword, !password.isEmpty else { throw TailscaleError.unavailable }
        var proxy = ProxyConfiguration(socksv5Proxy: .hostPort(host: "127.0.0.1", port: nwPort))
        proxy.applyCredential(username: "bitdream", password: password)
        proxy.allowFailover = false
        let configuration = URLSessionConfiguration.ephemeral
        configuration.proxyConfigurations = [proxy]
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration, delegate: RPCSessionDelegate(), delegateQueue: nil)
    }
}

struct TailscaleRequestSender: TransmissionRPCRequestSending {
    let service: EmbeddedTailscaleService
    let accountID: String
    let generation: UInt64
    let endpoint: TransmissionEndpoint

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await service.send(request, accountID: accountID, endpoint: endpoint)
    }
}

private final class RPCSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
