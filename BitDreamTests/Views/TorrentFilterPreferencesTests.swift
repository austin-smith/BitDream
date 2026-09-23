import XCTest
@testable import BitDream

@MainActor
final class TorrentFilterPreferencesTests: XCTestCase {
    func testRestoresStatusAndLabelRulesFromSavedPreferences() throws {
        try withDefaults { defaults, suiteName in
            let filters = TorrentFilterPreferences(userDefaults: defaults, serverID: "server-a")
            XCTAssertEqual(filters.sidebarSelection, .allDreams)
            XCTAssertFalse(filters.labelFilter.isActive)

            filters.sidebarSelection = .downloading
            filters.labelFilter.setRule(.include, for: "Movies")
            filters.labelFilter.setRule(.exclude, for: "Private")

            let reopened = TorrentFilterPreferences(
                userDefaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)),
                serverID: "server-a"
            )
            XCTAssertEqual(reopened.sidebarSelection, .downloading)
            XCTAssertEqual(reopened.sidebarSelection.filter, [.downloading])
            XCTAssertEqual(reopened.labelFilter.includedLabels, ["Movies"])
            XCTAssertEqual(reopened.labelFilter.excludedLabels, ["Private"])
        }
    }

    func testServerSwitchingAndDisconnectKeepSeparateLabelFilters() throws {
        try withDefaults { defaults, _ in
            let filters = TorrentFilterPreferences(userDefaults: defaults, serverID: "server-a")
            filters.sidebarSelection = .paused
            filters.labelFilter.setRule(.include, for: "Movies")

            filters.selectServer("server-b")
            XCTAssertFalse(filters.labelFilter.isActive)
            XCTAssertEqual(filters.sidebarSelection, .paused)
            filters.labelFilter.setShowsUnlabeledOnly(true)

            filters.selectServer(nil)
            XCTAssertFalse(filters.labelFilter.isActive)
            filters.selectServer("server-a")
            XCTAssertEqual(filters.labelFilter.includedLabels, ["Movies"])
            XCTAssertFalse(filters.labelFilter.showsUnlabeledOnly)

            filters.selectServer("server-b")
            XCTAssertTrue(filters.labelFilter.showsUnlabeledOnly)
            XCTAssertTrue(filters.labelFilter.includedLabels.isEmpty)
            let reopened = TorrentFilterPreferences(userDefaults: defaults, serverID: "server-b")
            XCTAssertTrue(reopened.labelFilter.showsUnlabeledOnly)
        }
    }

    func testClearingFiltersPersistsWithoutChangingAnotherServer() throws {
        try withDefaults { defaults, _ in
            let filters = TorrentFilterPreferences(userDefaults: defaults, serverID: "server-a")
            filters.labelFilter.setRule(.exclude, for: "Private")
            filters.selectServer("server-b")
            filters.labelFilter.setShowsUnlabeledOnly(true)
            filters.selectServer("server-a")
            filters.labelFilter.clear()
            filters.sidebarSelection = .allDreams

            let reopened = TorrentFilterPreferences(userDefaults: defaults, serverID: "server-a")
            XCTAssertFalse(reopened.labelFilter.isActive)
            XCTAssertEqual(reopened.sidebarSelection, .allDreams)
            reopened.selectServer("server-b")
            XCTAssertTrue(reopened.labelFilter.showsUnlabeledOnly)
        }
    }

    func testRestoredLabelsSurviveConnectionSetupUntilSnapshotLoads() throws {
        try withDefaults { defaults, _ in
            let filters = TorrentFilterPreferences(userDefaults: defaults, serverID: "server-a")
            filters.labelFilter.setRule(.include, for: "Movies")
            filters.labelFilter.setRule(.exclude, for: "Private")

            let reopened = TorrentFilterPreferences(userDefaults: defaults, serverID: nil)
            reopened.selectServer("server-a")
            reopened.reconcileLabels(with: [], hasLoadedSnapshot: false)
            XCTAssertEqual(reopened.labelFilter, filters.labelFilter)

            reopened.reconcileLabels(with: ["MOVIES"], hasLoadedSnapshot: true)
            XCTAssertEqual(reopened.labelFilter.includedLabels, ["MOVIES"])
            XCTAssertTrue(reopened.labelFilter.excludedLabels.isEmpty)
            XCTAssertEqual(
                TorrentFilterPreferences(userDefaults: defaults, serverID: "server-a").labelFilter,
                reopened.labelFilter
            )

            reopened.reconcileLabels(with: [], hasLoadedSnapshot: true)
            XCTAssertFalse(reopened.labelFilter.isActive)
        }
    }

    func testLabelRemovedWhileAppIsClosedIsClearedAfterLoadingAndStaysCleared() throws {
        for rule in [TorrentLabelRule.include, .exclude] {
            try withDefaults { defaults, _ in
                let filters = TorrentFilterPreferences(userDefaults: defaults, serverID: "server-a")
                filters.sidebarSelection = .downloading
                filters.labelFilter.setRule(rule, for: "Movies")

                let reopened = TorrentFilterPreferences(userDefaults: defaults, serverID: nil)
                reopened.synchronize(serverID: "server-a", availableLabels: [], hasLoadedSnapshot: false)
                XCTAssertEqual(reopened.labelFilter.rule(for: "Movies"), rule)

                // A successful empty snapshot means the label really is gone.
                reopened.synchronize(serverID: "server-a", availableLabels: [], hasLoadedSnapshot: true)
                XCTAssertFalse(reopened.labelFilter.isActive)
                XCTAssertEqual(reopened.sidebarSelection, .downloading)

                let reopenedAgain = TorrentFilterPreferences(userDefaults: defaults, serverID: "server-a")
                XCTAssertFalse(reopenedAgain.labelFilter.isActive)
                XCTAssertEqual(reopenedAgain.sidebarSelection, .downloading)
            }
        }
    }

    func testSynchronizationRemovesOnlyMissingLabelsForTheCurrentServer() throws {
        try withDefaults { defaults, _ in
            let filters = TorrentFilterPreferences(userDefaults: defaults, serverID: "server-a")
            filters.labelFilter.setRule(.include, for: "Movies")
            filters.selectServer("server-b")
            filters.labelFilter.setRule(.include, for: "Movies")
            filters.labelFilter.setRule(.include, for: "TV")
            filters.labelFilter.setRule(.exclude, for: "Private")
            filters.labelFilter.setRule(.exclude, for: "Old")

            let reopened = TorrentFilterPreferences(userDefaults: defaults, serverID: "server-a")
            reopened.synchronize(
                serverID: "server-b", availableLabels: ["tv", "Private"], hasLoadedSnapshot: true
            )
            XCTAssertEqual(reopened.labelFilter.includedLabels, ["tv"])
            XCTAssertEqual(reopened.labelFilter.excludedLabels, ["Private"])
            XCTAssertEqual(
                TorrentFilterPreferences(userDefaults: defaults, serverID: "server-b").labelFilter,
                reopened.labelFilter
            )
            XCTAssertEqual(
                TorrentFilterPreferences(userDefaults: defaults, serverID: "server-a").labelFilter.includedLabels,
                ["Movies"]
            )
        }
    }

    func testSynchronizationPreservesUnlabeledOnlyWhenServerHasNoLabels() throws {
        try withDefaults { defaults, _ in
            let filters = TorrentFilterPreferences(userDefaults: defaults, serverID: "server-a")
            filters.labelFilter.setShowsUnlabeledOnly(true)

            let reopened = TorrentFilterPreferences(userDefaults: defaults, serverID: nil)
            reopened.synchronize(serverID: "server-a", availableLabels: [], hasLoadedSnapshot: true)
            XCTAssertTrue(reopened.labelFilter.showsUnlabeledOnly)
        }
    }

    func testInvalidPreferencesFallBackToUnfilteredView() throws {
        try withDefaults { defaults, _ in
            defaults.set("unknown", forKey: "torrentStatusFilter")
            defaults.set([
                "includedLabels": 123,
                "excludedLabels": "invalid",
                "showsUnlabeledOnly": "invalid"
            ], forKey: "torrentLabelFilter.server-a")

            let filters = TorrentFilterPreferences(userDefaults: defaults, serverID: "server-a")
            XCTAssertEqual(filters.sidebarSelection, .allDreams)
            XCTAssertFalse(filters.labelFilter.isActive)
        }
    }

    private func withDefaults(_ body: (UserDefaults, String) throws -> Void) throws {
        let suiteName = "TorrentFilterPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults, suiteName)
    }
}
