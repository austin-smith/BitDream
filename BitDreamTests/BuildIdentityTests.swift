import Foundation
import Security
import SwiftData
import XCTest
@testable import BitDream

@MainActor
final class BuildIdentityTests: XCTestCase {
    func testAppAndEmbeddedWidgetHaveMatchingIdentity() throws {
        let pluginsURL = try XCTUnwrap(Bundle.main.builtInPlugInsURL)
        let widget = try XCTUnwrap(Bundle(url: pluginsURL.appendingPathComponent("BitDreamWidgetsExtension.appex")))

        for key in ["BitDreamVariant", "BitDreamAppName", "BitDreamAppGroup", "BitDreamURLScheme"] {
            let appValue = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: key) as? String)
            XCTAssertFalse(appValue.isEmpty)
            XCTAssertFalse(appValue.contains("$("))
            XCTAssertEqual(widget.object(forInfoDictionaryKey: key) as? String, appValue, key)
        }
        XCTAssertEqual(widget.bundleIdentifier, "\(AppIdentity.bundleIdentifier).BitDreamWidgets")
        XCTAssertEqual(AppGroup.identifier, "group.\(AppIdentity.bundleIdentifier)")
    }

    func testExplicitStoreLocationPreservesAutomaticGroupLocation() throws {
        // The production store used automatic group selection before variant isolation.
        // Both configurations must resolve the same URL within this app's group.
        let automatic = ModelConfiguration(
            "bitdream.persistence.hosts", schema: Schema([Host.self]), cloudKitDatabase: .none
        )
        try XCTSkipUnless(automatic.groupAppContainerIdentifier != nil, "App Group discovery requires a signed test host.")
        let explicit = ModelConfiguration(
            "bitdream.persistence.hosts", schema: Schema([Host.self]),
            groupContainer: .identifier(AppGroup.identifier), cloudKitDatabase: .none
        )
        XCTAssertEqual(explicit.url, automatic.url)
    }

    func testTestHostUsesEphemeralStore() {
        XCTAssertTrue(PersistenceController.shared.container.configurations.allSatisfy(\.isStoredInMemoryOnly))
    }

    func testSignedDevelopmentCredentialsAreSeparateFromProduction() throws {
        try XCTSkipUnless(AppIdentity.isDevelopment)
        let configuration = ModelConfiguration(cloudKitDatabase: .none)
        try XCTSkipUnless(configuration.groupAppContainerIdentifier != nil, "Keychain access requires a signed test host.")
        let key = "build-identity-test-\(UUID().uuidString)"
        XCTAssertTrue(KeychainService.savePassword("test-only-password", credentialKey: key))
        defer { XCTAssertTrue(KeychainService.deletePassword(credentialKey: key)) }
        XCTAssertEqual(KeychainService.readPassword(credentialKey: key), "test-only-password")

        let productionQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "com.crapshack.BitDream",
            kSecAttrAccount: "host:\(key)",
            kSecUseDataProtectionKeychain: true
        ]
        XCTAssertEqual(SecItemCopyMatching(productionQuery as CFDictionary, nil), errSecItemNotFound)
    }

    func testWidgetLinksRoundTripAndRejectOtherAppVariant() throws {
        let serverID = "server with spaces & symbols"
        let url = try XCTUnwrap(DeepLinkBuilder.serverURL(serverId: serverID))
        XCTAssertEqual(DeepLinkBuilder.serverID(from: url), serverID)

        var components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        components.scheme = AppIdentity.isDevelopment ? "bitdream" : "bitdream-dev"
        XCTAssertNil(DeepLinkBuilder.serverID(from: try XCTUnwrap(components.url)))
        XCTAssertNil(DeepLinkBuilder.serverID(from: try XCTUnwrap(URL(string: "\(DeepLinkConfig.scheme)://server?id="))))
    }

    #if canImport(Sparkle)
    func testDevelopmentCannotStartUpdaterEvenWhenExplicitlyEnabled() throws {
        try XCTSkipUnless(AppIdentity.isDevelopment, "This invariant applies to Debug and optimized DevRelease.")
        let updater = AppUpdater(updatesEnabled: true)
        updater.start()
        updater.checkForUpdates()
        XCTAssertFalse(updater.canCheckForUpdates)
        XCTAssertNil(updater.lastUpdateCheckDate)
    }
    #endif
}
