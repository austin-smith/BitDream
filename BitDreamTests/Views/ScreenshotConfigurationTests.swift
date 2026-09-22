#if BITDREAM_SAMPLE_SUPPORT
import SwiftUI
import XCTest
@testable import BitDream

@MainActor
final class ScreenshotConfigurationTests: XCTestCase {
    func testCaptureExplicitlyAddsPresentationToDemoWithoutChangingDemoPreferences() async throws {
        let name = "BitDreamTests.capture.demo.\(UUID().uuidString)"
        let demoDefaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { demoDefaults.removePersistentDomain(forName: name) }
        demoDefaults.set("Dark", forKey: "themeModeKey")
        demoDefaults.set(true, forKey: UserDefaultsKeys.torrentListCompactMode)
        let environment = AppEnvironment(processEnvironment: [
            "BITDREAM_DEMO": "1", "BITDREAM_SCREENSHOT": "1", "BITDREAM_SCREENSHOT_APPEARANCE": "light"
        ], demoUserDefaults: demoDefaults)
        XCTAssertNotNil(environment.demoSession)
        XCTAssertEqual(environment.themeManager.themeMode, .light)
        XCTAssertFalse(environment.userDefaults.bool(forKey: UserDefaultsKeys.torrentListCompactMode))
        XCTAssertFalse(environment.userDefaults.inspectorVisibility)
        XCTAssertEqual(environment.screenshotWindowSize, CGSize(width: 1200, height: 900))
        XCTAssertEqual(environment.screenshotDynamicTypeSize, .large)
        XCTAssertEqual(environment.presentationDate, SampleLibrary.referenceDate)
        XCTAssertEqual(environment.mainWindowID, "screenshot-main")
        await environment.start()
        defer { environment.store.clearSelectedHost() }
        for _ in 0..<200 where environment.store.torrents.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(environment.store.lastRefreshAt, SampleLibrary.referenceDate)
        let captureOrder = sortTorrents(environment.store.torrents,
                                       by: environment.userDefaults.sortProperty,
                                       order: environment.userDefaults.sortOrder)
        XCTAssertEqual(captureOrder.first?.id, 4)
        environment.store.handleConnectionError(.timeout)
        XCTAssertNil(environment.store.nextRetryAt)
        XCTAssertEqual(demoDefaults.string(forKey: "themeModeKey"), "Dark")
        XCTAssertTrue(demoDefaults.bool(forKey: UserDefaultsKeys.torrentListCompactMode))
    }

    func testCaptureResetsOnlyItsOwnPreferences() throws {
        let name = "BitDreamTests.capture.\(UUID().uuidString)"
        let configuration = ScreenshotConfiguration(appearance: .light, compact: false)
        let first = configuration.makeUserDefaults(suiteName: name)
        defer { first.removePersistentDomain(forName: name) }
        first.set("Dark", forKey: "themeModeKey")
        first.set(true, forKey: UserDefaultsKeys.torrentListCompactMode)
        first.sortProperty = .name
        first.sortOrder = .ascending
        let second = configuration.makeUserDefaults(suiteName: name)
        _ = DemoSession(userDefaults: second)
        XCTAssertEqual(second.string(forKey: "themeModeKey"), "Light")
        XCTAssertFalse(second.bool(forKey: UserDefaultsKeys.torrentListCompactMode))
        XCTAssertEqual(second.sortProperty, .dateAdded)
        XCTAssertEqual(second.sortOrder, .descending)
    }

    func testCaptureRequiresBothDemoAndAnExplicitCaptureFlag() throws {
        XCTAssertNil(try ScreenshotConfiguration.fromProcess(environment: [:]))
        XCTAssertNil(try ScreenshotConfiguration.fromProcess(environment: [
            "BITDREAM_DEMO": "1", "BITDREAM_SCREENSHOT_APPEARANCE": "dark"
        ]))
        XCTAssertThrowsError(try ScreenshotConfiguration.fromProcess(environment: ["BITDREAM_SCREENSHOT": "1"]))
        let configuration = try XCTUnwrap(ScreenshotConfiguration.fromProcess(environment: [
            "BITDREAM_DEMO": "1", "BITDREAM_SCREENSHOT": "1", "BITDREAM_SCREENSHOT_APPEARANCE": "dark"
        ]))
        XCTAssertEqual(configuration.appearance, .dark)
        XCTAssertThrowsError(try ScreenshotConfiguration.fromProcess(environment: [
            "BITDREAM_DEMO": "1", "BITDREAM_SCREENSHOT": "1", "BITDREAM_SCREENSHOT_APPEARANCE": "misspelled"
        ]))
    }
}
#endif
