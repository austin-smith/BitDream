import XCTest
@testable import BitDream

@MainActor
final class TorrentBulkLabelEditTests: XCTestCase {
    func testSharedLabelsReturnsIntersectionAcrossSelection() {
        let torrents = Set([
            makeTorrent(id: 1, labels: ["movie", "4k"]),
            makeTorrent(id: 2, labels: ["movie"]),
            makeTorrent(id: 3, labels: ["movie", "tv"])
        ])

        XCTAssertEqual(sharedLabels(for: torrents), ["movie"])
    }

    func testBulkLabelUpdatesRemovingSharedLabelRemovesItFromEverySelectedTorrent() {
        let torrents = Set([
            makeTorrent(id: 1, labels: ["movie", "4k"]),
            makeTorrent(id: 2, labels: ["movie"]),
            makeTorrent(id: 3, labels: ["movie", "tv"])
        ])

        let updates = bulkLabelUpdates(
            for: torrents,
            existingLabels: ["movie"],
            workingLabels: []
        )

        assertUpdates(
            updates,
            equal: [
                ([1], ["4k"]),
                ([2], []),
                ([3], ["tv"])
            ]
        )
    }

    func testBulkLabelUpdatesAddingLabelAddsItToEverySelectedTorrent() {
        let torrents = Set([
            makeTorrent(id: 1, labels: ["movie", "4k"]),
            makeTorrent(id: 2, labels: ["movie"]),
            makeTorrent(id: 3, labels: ["movie", "tv"])
        ])

        let updates = bulkLabelUpdates(
            for: torrents,
            existingLabels: ["movie"],
            workingLabels: ["movie", "favorite"]
        )

        assertUpdates(
            updates,
            equal: [
                ([1], ["4k", "favorite", "movie"]),
                ([2], ["favorite", "movie"]),
                ([3], ["favorite", "movie", "tv"])
            ]
        )
    }

    func testBulkLabelUpdatesPreservePartialLabelsWhenUnchanged() {
        let torrents = Set([
            makeTorrent(id: 1, labels: ["movie", "4k"]),
            makeTorrent(id: 2, labels: ["movie"]),
            makeTorrent(id: 3, labels: ["movie", "tv"])
        ])

        let updates = bulkLabelUpdates(
            for: torrents,
            existingLabels: ["movie"],
            workingLabels: ["movie"]
        )

        XCTAssertTrue(updates.isEmpty)
    }

    func testBulkLabelUpdatesAreNoLongerAddOnlyForSharedLabels() {
        let torrents = Set([
            makeTorrent(id: 1, labels: ["movie", "4k"]),
            makeTorrent(id: 2, labels: ["movie"])
        ])

        let updates = bulkLabelUpdates(
            for: torrents,
            existingLabels: ["movie"],
            workingLabels: []
        )

        assertUpdates(
            updates,
            equal: [
                ([1], ["4k"]),
                ([2], [])
            ]
        )
    }
}

private extension TorrentBulkLabelEditTests {
    func assertUpdates(
        _ updates: [TransmissionTorrentLabelsUpdate],
        equal expected: [([Int], [String])],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(updates.count, expected.count, file: file, line: line)

        for (update, expectedUpdate) in zip(updates, expected) {
            XCTAssertEqual(update.ids, expectedUpdate.0, file: file, line: line)
            XCTAssertEqual(update.labels, expectedUpdate.1, file: file, line: line)
        }
    }

    func makeTorrent(id: Int, labels: [String]) -> Torrent {
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
            labels: labels,
            leftUntilDone: 0,
            magnetLink: "",
            metadataPercentComplete: 1,
            name: "Torrent \(id)",
            peersConnected: 0,
            peersGettingFromUs: 0,
            peersSendingToUs: 0,
            percentDone: 1,
            primaryMimeType: nil,
            downloadDir: "/downloads",
            queuePosition: 0,
            rateDownload: 0,
            rateUpload: 0,
            sizeWhenDone: 0,
            status: TorrentStatus.stopped.rawValue,
            totalSize: 0,
            uploadRatio: 0,
            uploadedEver: 0,
            downloadedEver: 0
        )
    }
}
