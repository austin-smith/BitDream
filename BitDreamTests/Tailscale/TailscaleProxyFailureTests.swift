import Network
import XCTest
@testable import BitDream

final class TailscaleProxyFailureTests: XCTestCase {
    func testSOCKSConnectionFailureForValidURLRemainsRetryable() async throws {
        let proxy = try RejectingSOCKSProxy()
        let port = try await proxy.start()
        defer { proxy.stop() }
        let service = EmbeddedTailscaleService(
            driver: ProxySnapshotDriver(port: port), directory: { URL(filePath: "/unused") }
        )
        let endpoint = try TransmissionEndpoint(scheme: "http", host: "fixture.tail.ts.net", port: 9091)
        let sender = try await service.sender(accountID: "fixture", endpoint: endpoint)
        let transport = TransmissionTransport(sender: sender)
        do {
            _ = try await transport.sendEnvelope(
                method: "session-stats", arguments: EmptyArguments(), endpoint: endpoint,
                auth: makeAuth(), responseType: SessionStats.self
            )
            XCTFail("SOCKS rejection must fail the request")
        } catch {
            let failure = TransmissionErrorResolver.transmissionError(from: error)
            guard case .tailscale(.connectionFailed) = failure else {
                return XCTFail("Expected a Tailscale connection failure, got \(failure.diagnosticCode)")
            }
            XCTAssertTrue(failure.permitsAutomaticRetry)
            XCTAssertEqual(TransmissionErrorPresenter.presentation(for: failure).message,
                           "Could not connect to the server through Tailscale.")
        }
    }
}

private struct ProxySnapshotDriver: TailscaleDriving {
    let port: UInt16

    func perform(_ request: TailscaleNativeRequest) async throws -> TailscaleSnapshot {
        TailscaleSnapshot(
            generation: 1, state: "Running", authURL: nil, accountID: "fixture", accountName: "Fixture",
            peers: [TailscalePeer(id: "fixture", name: "Fixture", address: "fixture.tail.ts.net", online: true)],
            proxyPort: port, proxyPassword: "fixture", error: nil
        )
    }
}

/// A real loopback SOCKS5 handshake, followed by the same general-failure reply
/// used by the embedded proxy when its upstream dial fails. No external traffic.
private final class RejectingSOCKSProxy: Sendable {
    private let listener: NWListener

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    func start() async throws -> UInt16 {
        listener.newConnectionHandler = { connection in
            connection.start(queue: .global())
            Task {
                defer { connection.cancel() }
                try await Self.reject(connection)
            }
        }
        return try await withCheckedThrowingContinuation { continuation in
            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    if let port = listener.port { continuation.resume(returning: port.rawValue) } else { continuation.resume(throwing: TestError.unexpectedRequest) }
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: .global())
        }
    }

    func stop() { listener.cancel() }

    private static func reject(_ connection: NWConnection) async throws {
        let greeting = try await read(2, from: connection)
        _ = try await read(Int(greeting[1]), from: connection)
        try await send([5, 2], to: connection)
        let auth = try await read(2, from: connection)
        _ = try await read(Int(auth[1]), from: connection)
        let length = try await read(1, from: connection)
        _ = try await read(Int(length[0]), from: connection)
        try await send([1, 0], to: connection)
        let connect = try await read(4, from: connection)
        let addressLength: Int
        switch connect[3] {
        case 1: addressLength = 4
        case 4: addressLength = 16
        case 3: addressLength = Int(try await read(1, from: connection)[0])
        default: throw TestError.unexpectedRequest
        }
        _ = try await read(addressLength + 2, from: connection)
        try await send([5, 1, 0, 1, 0, 0, 0, 0, 0, 0], to: connection)
    }

    private static func read(_ count: Int, from connection: NWConnection) async throws -> [UInt8] {
        guard count > 0 else { return [] }
        return try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
                if let error { continuation.resume(throwing: error) } else if let data, data.count == count { continuation.resume(returning: Array(data)) } else { continuation.resume(throwing: TestError.unexpectedRequest) }
            }
        }
    }

    private static func send(_ bytes: [UInt8], to connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connection.send(content: Data(bytes), completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }
}
