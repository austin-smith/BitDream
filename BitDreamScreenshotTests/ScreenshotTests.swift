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
        let mozart = app.staticTexts["Mozart Keyboard Sheet Music - Public Domain"].firstMatch
        XCTAssertTrue(mozart.waitForExistence(timeout: 20), "The sample library did not load.")
        attach(app, name: "library-\(appearance)")
        #if os(macOS)
        mozart.click()
        app.typeKey("i", modifierFlags: [.option, .command])
        #else
        mozart.tap()
        #endif
        let files = app.buttons["torrent-detail-files"].firstMatch
        XCTAssertTrue(files.waitForExistence(timeout: 10), "Torrent details did not open.")
        let loaded = expectation(for: NSPredicate(format: "value == %@", "94 files"), evaluatedWith: files)
        wait(for: [loaded], timeout: 10)
        attach(app, name: "detail-\(appearance)")
        #if os(macOS)
        files.click()
        #else
        files.tap()
        #endif
        let firstFile = app.staticTexts["Fantasies/Fantasy in d, K 397.pdf"].firstMatch
        XCTAssertTrue(firstFile.waitForExistence(timeout: 10), "Mozart files did not load.")
        #if os(macOS)
        firstFile.click()
        #endif
        attach(app, name: "files-\(appearance)")
    }

    #if os(macOS)
    private func prepareWindow(_ app: XCUIApplication) {
        if !app.windows.firstMatch.waitForExistence(timeout: 3) {
            app.menuBars.menuBarItems["Window"].click()
            app.menuBars.menuBarItems["Window"].menus.menuItems["BitDream (Dev)"].click()
        }
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
