import Foundation
import XCTest
@testable import BitDream

@MainActor
final class TransmissionStorePlaybackOperationTests: XCTestCase {
    func testToggleTorrentPlaybackUsesResumeForStoppedTorrentAndSchedulesRefresh() async throws {
        let sender = MethodQueueSender(stepsByMethod: [
            "session-stats": [
                .http(statusCode: 200, body: successStatsBody),
                .http(statusCode: 200, body: successStatsBody)
            ],
            "torrent-get": [
                .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json")),
                .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json"))
            ],
            "session-get": [
                .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/initial", version: "4.0.0")),
                .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/initial", version: "4.0.0"))
            ],
            "torrent-start": [
                .http(statusCode: 200, body: successEmptyBody)
            ]
        ])
        let store = makeStore(sender: sender)

        store.setHost(host: makeHost(serverID: "server-1", server: "example.com"))
        let didConnect = await waitUntil { store.connectionStatus == .connected }
        XCTAssertTrue(didConnect)

        try await store.toggleTorrentPlayback(makeTorrent(id: 1, status: .stopped))

        let didRefresh = await waitUntil {
            let requests = await sender.capturedRequests()
            return requests.count == 7
        }
        XCTAssertTrue(didRefresh)

        let methods = try await sender.capturedRequests().map { try requestMethod(from: $0.asURLRequest()) }
        XCTAssertEqual(methods.filter { $0 == "torrent-start" }.count, 1)
        XCTAssertEqual(methods.filter { $0 == "torrent-stop" }.count, 0)
        XCTAssertEqual(methods.filter { $0 == "session-stats" }.count, 2)
        XCTAssertEqual(methods.filter { $0 == "torrent-get" }.count, 2)
        XCTAssertEqual(methods.filter { $0 == "session-get" }.count, 2)
    }

    func testToggleTorrentPlaybackUsesPauseForActiveTorrentAndSchedulesRefresh() async throws {
        let sender = MethodQueueSender(stepsByMethod: [
            "session-stats": [
                .http(statusCode: 200, body: successStatsBody),
                .http(statusCode: 200, body: successStatsBody)
            ],
            "torrent-get": [
                .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json")),
                .http(statusCode: 200, body: try loadTransmissionFixture(named: "torrent-get.response.json"))
            ],
            "session-get": [
                .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/initial", version: "4.0.0")),
                .http(statusCode: 200, body: try sessionSettingsBody(downloadDir: "/downloads/initial", version: "4.0.0"))
            ],
            "torrent-stop": [
                .http(statusCode: 200, body: successEmptyBody)
            ]
        ])
        let store = makeStore(sender: sender)

        store.setHost(host: makeHost(serverID: "server-1", server: "example.com"))
        let didConnect = await waitUntil { store.connectionStatus == .connected }
        XCTAssertTrue(didConnect)

        try await store.toggleTorrentPlayback(makeTorrent(id: 1, status: .downloading))

        let didRefresh = await waitUntil {
            let requests = await sender.capturedRequests()
            return requests.count == 7
        }
        XCTAssertTrue(didRefresh)

        let methods = try await sender.capturedRequests().map { try requestMethod(from: $0.asURLRequest()) }
        XCTAssertEqual(methods.filter { $0 == "torrent-stop" }.count, 1)
        XCTAssertEqual(methods.filter { $0 == "torrent-start" }.count, 0)
        XCTAssertEqual(methods.filter { $0 == "session-stats" }.count, 2)
        XCTAssertEqual(methods.filter { $0 == "torrent-get" }.count, 2)
        XCTAssertEqual(methods.filter { $0 == "session-get" }.count, 2)
    }
}

private extension TransmissionStorePlaybackOperationTests {
    func makeTorrent(id: Int, status: TorrentStatus) -> Torrent {
        Torrent(
            activityDate: 0,
            addedDate: 0,
            desiredAvailable: 0,
            error: 0,
            errorString: "",
            eta: 0,
            haveUnchecked: 0,
            haveValid: 0,
            id: id,
            isFinished: false,
            isStalled: false,
            labels: [],
            leftUntilDone: 0,
            magnetLink: "",
            metadataPercentComplete: 1,
            name: "Torrent \(id)",
            peersConnected: 0,
            peersGettingFromUs: 0,
            peersSendingToUs: 0,
            percentDone: status == .stopped ? 0 : 0.5,
            primaryMimeType: nil,
            downloadDir: "/downloads",
            queuePosition: 0,
            rateDownload: 0,
            rateUpload: 0,
            sizeWhenDone: 0,
            status: status.rawValue,
            totalSize: 0,
            uploadRatioRaw: 0,
            uploadedEver: 0,
            downloadedEver: 0
        )
    }

}
