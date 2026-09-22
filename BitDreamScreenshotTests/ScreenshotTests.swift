import XCTest

/// The capture script exports these attachments to PNG. Each appearance starts
/// a fresh sample session and exercises the same navigation as a person.
@MainActor
final class ScreenshotTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testLibraryLight() throws { try captureLibrary(appearance: "light") }
    func testLibraryDark() throws { try captureLibrary(appearance: "dark") }

    private func captureLibrary(appearance: String) throws {
        let app = XCUIApplication()
        app.launchEnvironment["BITDREAM_DEMO"] = "1"
        app.launchEnvironment["BITDREAM_SCREENSHOT"] = "1"
        app.launchEnvironment["BITDREAM_SCREENSHOT_APPEARANCE"] = appearance
        app.launchEnvironment["TZ"] = "UTC"
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        #if os(iOS)
        XCUIDevice.shared.orientation = .portrait
        #endif
        app.launch()
        addTeardownBlock { @MainActor in app.terminate() }
        #if os(macOS)
        prepareWindow(app)
        #endif
        let bunny = app.staticTexts["Big Buck Bunny"].firstMatch
        XCTAssertTrue(bunny.waitForExistence(timeout: 20), "The sample library did not load.")
        attach(app, name: "library-\(appearance)")
        #if os(macOS)
        bunny.click()
        app.typeKey("i", modifierFlags: [.option, .command])
        #else
        bunny.tap()
        #endif
        let files = app.buttons["torrent-detail-files"].firstMatch
        XCTAssertTrue(files.waitForExistence(timeout: 10), "Torrent details did not open.")
        let loaded = expectation(for: NSPredicate(format: "value == %@", "3 files"), evaluatedWith: files)
        wait(for: [loaded], timeout: 10)
        attach(app, name: "detail-\(appearance)")
        #if os(macOS)
        files.click()
        #else
        files.tap()
        #endif
        XCTAssertTrue(app.staticTexts["Big Buck Bunny.mp4"].firstMatch.waitForExistence(timeout: 10), "Files did not load.")
        #if os(macOS)
        app.staticTexts["Big Buck Bunny.mp4"].firstMatch.click()
        #endif
        attach(app, name: "files-\(appearance)")
        #if os(macOS)
        app.buttons["Done"].firstMatch.click()
        app.buttons["torrent-detail-peers"].firstMatch.click()
        #else
        app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", "BackButton", "Back")).firstMatch.tap()
        app.buttons["torrent-detail-peers"].firstMatch.tap()
        #endif
        XCTAssertTrue(app.staticTexts["peer-address-203.0.113.10"].firstMatch.waitForExistence(timeout: 10), "Peers did not load.")
        attach(app, name: "peers-\(appearance)")
    }

    #if os(macOS)
    private func prepareWindow(_ app: XCUIApplication) {
        if !app.windows.firstMatch.waitForExistence(timeout: 3) {
            app.menuBars.menuBarItems["Window"].click()
            app.menuBars.menuBarItems["Window"].menus.menuItems["BitDream (Dev)"].click()
        }
        app.menuBars.menuBarItems["Window"].click()
        app.menuBars.menuBarItems["Window"].menus.menuItems["Center"].click()
        let window = app.windows.firstMatch
        let divider = window.splitters.firstMatch
        divider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click(
            forDuration: 0.1,
            thenDragTo: window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 220, dy: 400))
        )
        XCTAssertEqual(divider.frame.minX - window.frame.minX, 220, accuracy: 2)
    }
    #endif

    private func attach(_ app: XCUIApplication, name: String) {
        #if os(macOS)
        app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: -20, dy: 0)).hover()
        let screenshot = app.windows.firstMatch.screenshot()
        #else
        let screenshot = XCUIScreen.main.screenshot()
        #endif
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
