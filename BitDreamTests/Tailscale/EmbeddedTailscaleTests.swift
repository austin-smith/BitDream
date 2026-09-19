import XCTest
@testable import BitDream

final class EmbeddedTailscaleTests: XCTestCase {
    @MainActor
    func testSetupRestoresSavedLoginWithoutInteractiveSignIn() async {
        let restored = Self.snapshot(account: "saved-account", generation: 1)
        let driver = RestoringSnapshotDriver(restored: restored)
        let service = EmbeddedTailscaleService(driver: driver, directory: { URL(filePath: "/unused") })
        let model = TailscaleSetupModel(service: service)

        // A new server has no account association. Opening its Tailscale settings
        // must still start the node and discover the login persisted by the app.
        await model.refresh()

        XCTAssertTrue(model.isSignedIn)
        XCTAssertEqual(model.snapshot?.accountID, "saved-account")
        XCTAssertEqual(model.snapshot?.peers, restored.peers)
        XCTAssertNil(model.authorizationURL, "Restoring a login must not open the sign-in browser")
        XCTAssertNil(model.errorMessage)
        let actions = await driver.actions
        XCTAssertEqual(actions, ["start"], "Restoration must not request an interactive login")
    }

    @MainActor
    func testSetupDoesNotTreatPendingOrExpiredLoginAsSignedIn() async throws {
        let pending = TailscaleSnapshot(
            generation: 1, state: "NeedsLogin", authURL: "https://login.tailscale.com/a/test",
            accountID: "cached-account", accountName: "Test", peers: [],
            proxyPort: nil, proxyPassword: nil, error: nil
        )
        let driver = SnapshotDriver(snapshot: pending)
        let service = EmbeddedTailscaleService(driver: driver, directory: { URL(filePath: "/unused") })
        let model = TailscaleSetupModel(service: service)
        XCTAssertFalse(model.isSignedIn)

        await model.signIn()
        XCTAssertNotNil(model.authorizationURL)
        XCTAssertFalse(model.isSignedIn, "Opening authorization must not expose Sign Out")

        // Canceling the browser must leave sign-in available, not imply authentication.
        model.authorizationURL = nil
        await model.refresh()
        XCTAssertFalse(model.isSignedIn)

        await model.signIn()
        for state in ["NeedsMachineAuth", "Starting", "Running", "Stopped"] {
            await driver.update(TailscaleSnapshot(
                generation: 1, state: state, authURL: nil, accountID: "account",
                accountName: "Test", peers: [], proxyPort: state == "Running" ? 1234 : nil,
                proxyPassword: nil, error: nil
            ))
            await model.refresh()
            XCTAssertTrue(model.isSignedIn, "Authenticated users can sign out during \(state)")
        }
        XCTAssertNil(model.authorizationURL)

        await driver.update(pending)
        await model.refresh()
        XCTAssertFalse(model.isSignedIn, "An expired login must not use cached identity as proof")
    }

    func testLegacyCatalogDecodesToSystemNetworking() throws {
        let data = Data("""
        {"schemaVersion":1,"generatedAt":0,"records":[{"serverID":"s","name":"NAS",
        "server":"nas.local","port":9091,"username":"u","isSSL":false,
        "credentialKey":"key","isDefault":true}]}
        """.utf8)
        let catalog = try JSONDecoder().decode(HostRefreshCatalog.self, from: data)
        let descriptor = TransmissionConnectionDescriptor(record: try XCTUnwrap(catalog.records.first))
        XCTAssertEqual(descriptor.connectionRoute, "system")
        XCTAssertNil(descriptor.tailscaleAccountID)
    }

    func testEmbeddedRouteSurvivesCatalogRoundTrip() throws {
        let original = HostRefreshRecord(
            serverID: "s", name: "NAS", server: "nas.tail.ts.net", port: 65535,
            username: "u", isSSL: true, credentialKey: "key", isDefault: true,
            version: nil, connectionRoute: "tailscale", tailscaleAccountID: "account-a"
        )
        let decoded = try JSONDecoder().decode(HostRefreshRecord.self, from: JSONEncoder().encode(original))
        let descriptor = TransmissionConnectionDescriptor(record: decoded)
        XCTAssertEqual(descriptor.connectionRoute, "tailscale")
        XCTAssertEqual(descriptor.tailscaleAccountID, "account-a")
        XCTAssertEqual(descriptor.port, 65535)
    }

    func testUnknownRouteCannotFallBackToSystemSender() async throws {
        let sender = QueueSender(steps: [])
        let factory = TransmissionConnectionFactory(transport: TransmissionTransport(sender: sender))
        let descriptor = TransmissionConnectionDescriptor(
            scheme: "http", host: "nas.local", port: 9091, username: "u",
            credentialSource: .resolvedPassword("password"), connectionRoute: "unknown"
        )
        do {
            _ = try await factory.connection(for: descriptor)
            XCTFail("Unknown route was accepted")
        } catch TailscaleError.invalidRoute {
        }
        let requests = await sender.capturedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func testDifferentAccountFailsBeforeSendingCredentials() async throws {
        let driver = SnapshotDriver(snapshot: Self.snapshot(account: "account-b", generation: 1))
        let service = EmbeddedTailscaleService(driver: driver, directory: { URL(filePath: "/unused") })
        let endpoint = try TransmissionEndpoint(scheme: "http", host: "nas.tail.ts.net", port: 9091)
        do {
            _ = try await service.sender(accountID: "account-a", endpoint: endpoint)
            XCTFail("Different account was accepted")
        } catch TailscaleError.accountMismatch {
        }
    }

    func testFactoryReplacesEmbeddedConnectionAfterProxyGenerationChanges() async throws {
        let driver = SnapshotDriver(snapshot: Self.snapshot(account: "account-a", generation: 1))
        let service = EmbeddedTailscaleService(driver: driver, directory: { URL(filePath: "/unused") })
        let factory = TransmissionConnectionFactory(tailscale: service)
        let descriptor = TransmissionConnectionDescriptor(
            scheme: "http", host: "nas.tail.ts.net", port: 9091, username: "u",
            credentialSource: .resolvedPassword("password"), connectionRoute: "tailscale",
            tailscaleAccountID: "account-a"
        )
        let first = try await factory.connection(for: descriptor)
        let reused = try await factory.connection(for: descriptor)
        XCTAssertTrue(first === reused)
        await driver.update(Self.snapshot(account: "account-a", generation: 2))
        let replaced = try await factory.connection(for: descriptor)
        XCTAssertFalse(first === replaced)
    }

    func testAuthorizationRejectsUntrustedURLs() {
        for value in ["http://login.tailscale.com/a", "https://evil.example/a", "https://user@login.tailscale.com/a"] {
            let snapshot = TailscaleSnapshot(
                generation: 1, state: "NeedsLogin", authURL: value, accountID: nil,
                accountName: nil, peers: [], proxyPort: nil, proxyPassword: nil, error: nil
            )
            XCTAssertNil(snapshot.authorizationURL)
        }
    }

    private static func snapshot(account: String, generation: UInt64) -> TailscaleSnapshot {
        TailscaleSnapshot(generation: generation, state: "Running", authURL: nil,
                          accountID: account, accountName: "Test",
                          peers: [TailscalePeer(id: "nas", name: "NAS", address: "nas.tail.ts.net", online: true)],
                          proxyPort: 1234,
                          proxyPassword: "test", error: nil)
    }
}

private actor SnapshotDriver: TailscaleDriving {
    private var snapshot: TailscaleSnapshot
    init(snapshot: TailscaleSnapshot) { self.snapshot = snapshot }
    func update(_ value: TailscaleSnapshot) { snapshot = value }
    func perform(_ request: TailscaleNativeRequest) -> TailscaleSnapshot { snapshot }
}

private actor RestoringSnapshotDriver: TailscaleDriving {
    let restored: TailscaleSnapshot
    private var isStarted = false
    private(set) var actions: [String] = []

    init(restored: TailscaleSnapshot) { self.restored = restored }

    func perform(_ request: TailscaleNativeRequest) -> TailscaleSnapshot {
        actions.append(request.action)
        if request.action == "start" { isStarted = true }
        if isStarted { return restored }
        return TailscaleSnapshot(
            generation: 0, state: "Stopped", authURL: nil, accountID: nil,
            accountName: nil, peers: [], proxyPort: nil, proxyPassword: nil, error: nil
        )
    }
}
