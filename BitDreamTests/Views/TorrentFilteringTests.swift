import XCTest
@testable import BitDream

@MainActor
final class TorrentFilteringTests: XCTestCase {
    func testEmptyLabelSelectionDoesNotRestrictResults() {
        let torrents = [
            makeTorrent(id: 1, name: "One", labels: ["movie"]),
            makeTorrent(id: 2, name: "Two", labels: [])
        ]

        XCTAssertEqual(
            torrents.filtered(by: TorrentLabelFilter()).map(\.id),
            [1, 2]
        )
    }

    func testLabelFilteringMatchesAnySelectedLabelCaseInsensitively() {
        let torrents = [
            makeTorrent(id: 1, name: "Movie", labels: ["Movie"]),
            makeTorrent(id: 2, name: "Series", labels: ["TV"]),
            makeTorrent(id: 3, name: "Album", labels: ["music"])
        ]

        let filtered = torrents.filtered(
            by: TorrentLabelFilter(includedLabels: ["movie", "tv"])
        )

        XCTAssertEqual(filtered.map(\.id), [1, 2])
    }

    func testUnlabeledSelectionMatchesTorrentsWithoutLabels() {
        let torrents = [
            makeTorrent(id: 1, name: "Movie", labels: ["movie"]),
            makeTorrent(id: 2, name: "Unlabeled", labels: [])
        ]

        let filtered = torrents.filtered(
            by: TorrentLabelFilter(showsUnlabeledOnly: true)
        )

        XCTAssertEqual(filtered.map(\.id), [2])
    }

    func testExcludedLabelsRemoveMatchingTorrentsCaseInsensitively() {
        let torrents = [
            makeTorrent(id: 1, name: "Movie", labels: ["movie"]),
            makeTorrent(id: 2, name: "Series", labels: ["tv"]),
            makeTorrent(id: 3, name: "Unlabeled", labels: [])
        ]

        let filtered = torrents.filtered(
            by: TorrentLabelFilter(excludedLabels: ["TV"])
        )

        XCTAssertEqual(filtered.map(\.id), [1, 3])
    }

    func testIncludedAndExcludedLabelsComposeWithAndSemantics() {
        let torrents = [
            makeTorrent(id: 1, name: "Movie", labels: ["movie"]),
            makeTorrent(id: 2, name: "Movie Series", labels: ["movie", "tv"]),
            makeTorrent(id: 3, name: "Series", labels: ["tv"]),
            makeTorrent(id: 4, name: "Unlabeled", labels: [])
        ]

        let filtered = torrents.filtered(
            by: TorrentLabelFilter(
                includedLabels: ["movie"],
                excludedLabels: ["tv"]
            )
        )

        XCTAssertEqual(filtered.map(\.id), [1])
    }

    func testUnlabeledAndLabelRulesAreMutuallyExclusive() {
        var labelFilter = TorrentLabelFilter(includedLabels: ["movie"])

        labelFilter.setShowsUnlabeledOnly(true)

        XCTAssertTrue(labelFilter.includedLabels.isEmpty)
        XCTAssertTrue(labelFilter.excludedLabels.isEmpty)
        XCTAssertTrue(labelFilter.showsUnlabeledOnly)

        labelFilter.setRule(.exclude, for: "tv")

        XCTAssertFalse(labelFilter.showsUnlabeledOnly)
        XCTAssertEqual(labelFilter.excludedLabels, ["tv"])
    }

    func testAdvancingLabelRuleMatchesMacOSTriStateOrder() {
        var labelFilter = TorrentLabelFilter()

        labelFilter.advanceRule(for: "movie")
        XCTAssertEqual(labelFilter.rule(for: "movie"), .include)

        labelFilter.advanceRule(for: "movie")
        XCTAssertEqual(labelFilter.rule(for: "movie"), .exclude)

        labelFilter.advanceRule(for: "movie")
        XCTAssertEqual(labelFilter.rule(for: "movie"), .none)
    }

    func testStatusLabelAndSearchFiltersComposeWithAndSemantics() {
        let torrents = [
            makeTorrent(
                id: 1,
                name: "Ubuntu Desktop",
                labels: ["linux"],
                status: .downloading,
                percentDone: 0.4
            ),
            makeTorrent(
                id: 2,
                name: "Ubuntu Server",
                labels: ["linux"],
                status: .stopped,
                percentDone: 1
            ),
            makeTorrent(
                id: 3,
                name: "Fedora Workstation",
                labels: ["linux"],
                status: .downloading,
                percentDone: 0.4
            ),
            makeTorrent(
                id: 4,
                name: "Ubuntu Documentary",
                labels: ["movies"],
                status: .downloading,
                percentDone: 0.4
            )
        ]

        let filtered = torrents.filtered(
            by: [.downloading],
            labelFilter: TorrentLabelFilter(includedLabels: ["LINUX"]),
            searchText: "ubuntu"
        )

        XCTAssertEqual(filtered.map(\.id), [1])
    }

    func testFilterAndSortSortsOnlyMatchingTorrents() {
        let torrents = [
            makeTorrent(id: 1, name: "Zulu", labels: ["selected"]),
            makeTorrent(id: 2, name: "Alpha", labels: ["selected"]),
            makeTorrent(id: 3, name: "Bravo", labels: ["other"])
        ]

        let displayed = filterAndSortTorrents(
            torrents,
            options: TorrentDisplayOptions(
                statusFilter: TorrentStatusCalc.allCases,
                labelFilter: TorrentLabelFilter(includedLabels: ["selected"]),
                searchText: "",
                sortProperty: .name,
                sortOrder: .ascending
            )
        )

        XCTAssertEqual(displayed.map(\.id), [2, 1])
    }
}

private extension TorrentFilteringTests {
    func makeTorrent(
        id: Int,
        name: String,
        labels: [String],
        status: TorrentStatus = .downloading,
        percentDone: Double = 0.5
    ) -> Torrent {
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
            isFinished: percentDone == 1,
            isStalled: false,
            labels: labels,
            leftUntilDone: 0,
            magnetLink: "",
            metadataPercentComplete: 1,
            name: name,
            peersConnected: 0,
            peersGettingFromUs: 0,
            peersSendingToUs: 0,
            percentDone: percentDone,
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
