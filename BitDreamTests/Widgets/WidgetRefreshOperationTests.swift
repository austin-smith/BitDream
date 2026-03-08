import Foundation
import XCTest
@testable import BitDream

final class WidgetRefreshOperationTests: XCTestCase {
    func testWidgetRefreshUsesDescriptorFactoryPathForHostRecords() async throws {
        let sender = MethodQueueSender(stepsByMethod: [
            "session-stats": [
                .http(statusCode: 200, body: successStatsBody)
            ],
            "torrent-get": [
                .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json"))
            ]
        ])
        let recorder = WidgetRefreshRecorder()
        let dependencies = makeDependencies(
            sender: sender,
            recorder: recorder,
            records: [
                makeHostRefreshRecord(
                    serverID: "server-1",
                    name: "Server",
                    server: "example.com",
                    isSSL: true
                )
            ],
            resolvePassword: { source in
                switch source {
                case .resolvedPassword(let password):
                    return password
                case .keychainCredential(let key):
                    return key == "widget-key" ? "resolved-secret" : ""
                }
            },
            sleep: sleepUntilCancelled
        )

        let success = await WidgetRefreshRunner.run(dependencies: dependencies)

        XCTAssertTrue(success)
        XCTAssertEqual(recorder.serverIndexCount, 1)
        XCTAssertEqual(recorder.sessionSnapshotCount, 1)
        XCTAssertEqual(recorder.reloadCount, 1)

        let requests = await sender.capturedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(
            requests[0].authorizationHeader,
            "Basic \(Data("demo:resolved-secret".utf8).base64EncodedString())"
        )
        let torrentRequest = try request(named: "torrent-get", in: requests)
        XCTAssertEqual(
            try capturedRequestFields(torrentRequest),
            TransmissionTorrentQuerySpec.widgetSummary.fields
        )
    }

    func testWidgetRefreshTimeoutSkipsSnapshotWrite() async {
        let sender = HangingSender()
        let recorder = WidgetRefreshRecorder()
        let dependencies = makeDependencies(
            sender: sender,
            recorder: recorder,
            records: [
                makeHostRefreshRecord(
                    serverID: "server-1",
                    name: "Server",
                    server: "example.com",
                    isSSL: false
                )
            ],
            resolvePassword: { _ in "" },
            sleep: { _ in }
        )

        let success = await WidgetRefreshRunner.run(dependencies: dependencies)

        XCTAssertTrue(success)
        XCTAssertEqual(recorder.sessionSnapshotCount, 0)
    }

    func testWidgetRefreshWritesOneServerIndexAndOneReloadPerBatch() async throws {
        let sender = MethodQueueSender(stepsByMethod: [
            "session-stats": [
                .http(statusCode: 200, body: successStatsBody),
                .http(statusCode: 200, body: successStatsBody)
            ],
            "torrent-get": [
                .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json")),
                .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json"))
            ]
        ])
        let recorder = WidgetRefreshRecorder()
        let dependencies = makeDependencies(
            sender: sender,
            recorder: recorder,
            records: [
                makeHostRefreshRecord(
                    serverID: "server-1",
                    name: "Server One",
                    server: "example.com",
                    isSSL: false
                ),
                makeHostRefreshRecord(
                    serverID: "server-2",
                    name: "Server Two",
                    server: "example.net",
                    isSSL: false
                )
            ],
            resolvePassword: { _ in "" },
            sleep: sleepUntilCancelled
        )

        let success = await WidgetRefreshRunner.run(dependencies: dependencies)

        XCTAssertTrue(success)
        XCTAssertEqual(recorder.serverIndexCount, 1)
        XCTAssertEqual(recorder.sessionSnapshotCount, 2)
        XCTAssertEqual(recorder.reloadCount, 1)
    }
}

private final class WidgetRefreshRecorder: @unchecked Sendable {
    struct SessionSnapshot {
        let serverID: String
        let stats: SessionStats
        let torrents: [Torrent]
        let reloadTimelines: Bool
    }

    private let lock = NSLock()
    private(set) var serverIndexes: [[ServerSummary]] = []
    private(set) var sessionSnapshots: [SessionSnapshot] = []
    private(set) var reloadCount = 0

    var writer: WidgetSnapshotWriter {
        WidgetSnapshotWriter(
            writeServerIndex: { [weak self] summaries in
                self?.recordServerIndex(summaries)
            },
            writeSessionSnapshot: { [weak self] serverID, _, stats, torrents, reloadTimelines in
                self?.recordSessionSnapshot(serverID: serverID, stats: stats, torrents: torrents, reloadTimelines: reloadTimelines)
            },
            reloadTimelines: { [weak self] in
                self?.recordReload()
            }
        )
    }

    var serverIndexCount: Int {
        lock.withLock {
            serverIndexes.count
        }
    }

    var sessionSnapshotCount: Int {
        lock.withLock {
            sessionSnapshots.count
        }
    }

    private func recordServerIndex(_ summaries: [ServerSummary]) {
        lock.withLock {
            serverIndexes.append(summaries)
        }
    }

    private func recordSessionSnapshot(
        serverID: String,
        stats: SessionStats,
        torrents: [Torrent],
        reloadTimelines: Bool
    ) {
        lock.withLock {
            sessionSnapshots.append(
                SessionSnapshot(
                    serverID: serverID,
                    stats: stats,
                    torrents: torrents,
                    reloadTimelines: reloadTimelines
                )
            )
        }
    }

    private func recordReload() {
        lock.withLock {
            reloadCount += 1
        }
    }
}

private actor HangingSender: TransmissionRPCRequestSending {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await Task.sleep(nanoseconds: .max)
        throw TransmissionError.timeout
    }
}

private func makeDependencies(
    sender: some TransmissionRPCRequestSending,
    recorder: WidgetRefreshRecorder,
    records: [HostRefreshRecord],
    resolvePassword: @escaping @Sendable (TransmissionCredentialSource) -> String,
    sleep: @escaping @Sendable (TimeInterval) async throws -> Void
) -> WidgetRefreshDependencies {
    WidgetRefreshDependencies(
        connectionFactory: TransmissionConnectionFactory(
            transport: TransmissionTransport(sender: sender),
            credentialResolver: TransmissionCredentialResolver(resolvePassword: resolvePassword)
        ),
        snapshotWriter: recorder.writer,
        loadHosts: { records },
        sleep: sleep
    )
}

private func makeHostRefreshRecord(
    serverID: String,
    name: String,
    server: String,
    isSSL: Bool
) -> HostRefreshRecord {
    HostRefreshRecord(
        serverID: serverID,
        name: name,
        server: server,
        port: 9091,
        username: "demo",
        isSSL: isSSL,
        credentialKey: "widget-key",
        isDefault: false,
        version: nil
    )
}

private func sleepUntilCancelled(_: TimeInterval) async throws {
    try await Task.sleep(nanoseconds: .max)
}

private func request(named expectedMethod: String, in requests: [CapturedRequest]) throws -> CapturedRequest {
    for request in requests where try capturedRequestMethod(request) == expectedMethod {
        return request
    }

    XCTFail("Missing request for method \(expectedMethod)")
    throw TestError.unexpectedRequest
}

private func capturedRequestMethod(_ request: CapturedRequest) throws -> String {
    let body = try XCTUnwrap(request.body)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
    return try XCTUnwrap(object["method"] as? String)
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
