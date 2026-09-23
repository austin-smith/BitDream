import XCTest

#if os(macOS)
@MainActor
final class KeyboardFocusTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testArrowNavigationSurvivesListModeChanges() {
        let app = launchDemo()
        // Native tab order starts in the sidebar, then Search, then the torrent list.
        app.typeKey(.tab, modifierFlags: [])
        app.typeKey(.tab, modifierFlags: [])
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(torrentRows(in: app).element(boundBy: 0).isSelected)

        app.buttons["Compact View"].firstMatch.click()
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(torrentRows(in: app).element(boundBy: 1).isSelected)

        app.buttons["Expanded View"].firstMatch.click()
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(torrentRows(in: app).element(boundBy: 2).isSelected)
    }

    func testModeChangesPreserveSearchAndSidebarFocus() {
        let app = launchDemo()
        let search = app.searchFields.firstMatch
        app.typeKey("f", modifierFlags: .command)
        app.typeText("Mozart")
        XCTAssertEqual(search.value as? String, "Mozart")

        app.buttons["Compact View"].firstMatch.click()
        app.typeText(" Keyboard")
        XCTAssertEqual(search.value as? String, "Mozart Keyboard")
        app.buttons["Expanded View"].firstMatch.click()
        app.typeText(" Sheet")
        XCTAssertEqual(search.value as? String, "Mozart Keyboard Sheet")

        app.typeKey("i", modifierFlags: [.command, .option])
        app.typeText(" Music")
        XCTAssertEqual(search.value as? String, "Mozart Keyboard Sheet Music")
        app.typeKey("a", modifierFlags: .command)
        app.typeKey(.delete, modifierFlags: [])
        torrentRows(in: app).element(boundBy: 0).click()
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(torrentRows(in: app).element(boundBy: 1).isSelected)

        app.outlines["Sidebar"].staticTexts["All Dreams"].firstMatch.click()
        app.buttons["Compact View"].firstMatch.click()
        app.typeKey(.downArrow, modifierFlags: [])
        let downloading = app.outlines["Sidebar"].children(matching: .outlineRow)
            .containing(.staticText, identifier: "Downloading").firstMatch
        XCTAssertTrue(downloading.isSelected)
    }

    private func launchDemo() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["BITDREAM_DEMO"] = "1"
        app.launchEnvironment["BITDREAM_SCREENSHOT"] = "1"
        app.launchEnvironment["BITDREAM_SCREENSHOT_APPEARANCE"] = "light"
        app.launch()
        addTeardownBlock { @MainActor in app.terminate() }
        XCTAssertTrue(app.staticTexts["Mozart Keyboard Sheet Music - Public Domain"].firstMatch
            .waitForExistence(timeout: 20))
        return app
    }

    private func torrentRows(in app: XCUIApplication) -> XCUIElementQuery {
        app.outlines.matching(NSPredicate(format: "label != %@", "Sidebar")).firstMatch
            .children(matching: .outlineRow)
    }
}
#endif
