import XCTest
@testable import BitDream

final class TransmissionConnectionFactoryTests: XCTestCase {
    func testFactoryRejectsInvalidEndpointDescriptor() async {
        let factory = TransmissionConnectionFactory(
            transport: TransmissionTransport(sender: QueueSender(steps: [])),
            credentialResolver: TransmissionCredentialResolver(resolvePassword: { _ in "" })
        )
        let descriptor = TransmissionConnectionDescriptor(
            scheme: "http",
            host: "bad host",
            port: 9091,
            username: "demo",
            credentialSource: .resolvedPassword("secret")
        )

        await assertThrowsTransmissionError(.invalidEndpointConfiguration) {
            _ = try await factory.connection(for: descriptor)
        }
    }

    func testFactoryResolvesKeychainCredentialSourceBeforeConstructingConnection() async throws {
        let sender = QueueSender(steps: [
            .http(statusCode: 200, body: successStatsBody)
        ])
        let factory = TransmissionConnectionFactory(
            transport: TransmissionTransport(sender: sender),
            credentialResolver: TransmissionCredentialResolver(resolvePassword: { source in
                switch source {
                case .resolvedPassword(let password):
                    return password
                case .keychainCredential(let key):
                    return key == "widget-key" ? "resolved-secret" : ""
                }
            })
        )
        let descriptor = TransmissionConnectionDescriptor(
            scheme: "https",
            host: "example.com",
            port: 9091,
            username: "demo",
            credentialSource: .keychainCredential("widget-key")
        )

        let connection = try await factory.connection(for: descriptor)
        _ = try await connection.fetchSessionStats()

        let requests = await sender.capturedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(
            requests[0].authorizationHeader,
            "Basic \(Data("demo:resolved-secret".utf8).base64EncodedString())"
        )
    }

    func testFactoryReusesConnectionForEquivalentResolvedDescriptor() async throws {
        let factory = TransmissionConnectionFactory(
            transport: TransmissionTransport(sender: QueueSender(steps: [])),
            credentialResolver: TransmissionCredentialResolver(resolvePassword: { _ in "secret" })
        )
        let descriptor = TransmissionConnectionDescriptor(
            scheme: "http",
            host: "example.com",
            port: 9091,
            username: "demo",
            credentialSource: .keychainCredential("credential-key")
        )

        let first = try await factory.connection(for: descriptor)
        let second = try await factory.connection(for: descriptor)

        XCTAssertEqual(ObjectIdentifier(first), ObjectIdentifier(second))
    }

    func testHostAndHostRefreshRecordProduceEquivalentDescriptors() {
        let host = Host(
            serverID: "server-1",
            isDefault: false,
            isSSL: true,
            credentialKey: "credential-key",
            name: "Server",
            port: 9091,
            server: "example.com",
            username: "demo",
            version: nil
        )
        let record = HostRefreshRecord(
            serverID: "server-1",
            name: "Server",
            server: "example.com",
            port: 9091,
            username: "demo",
            isSSL: true,
            credentialKey: "credential-key",
            isDefault: false,
            version: nil
        )

        XCTAssertEqual(
            TransmissionConnectionDescriptor(host: host),
            TransmissionConnectionDescriptor(record: record)
        )
    }

    func testLegacyTupleDescriptorBridgeUsesResolvedPasswordSource() {
        let descriptor = TransmissionConnectionDescriptor(config: makeConfig(), auth: makeAuth())

        XCTAssertEqual(descriptor.scheme, "http")
        XCTAssertEqual(descriptor.host, "example.com")
        XCTAssertEqual(descriptor.port, 9091)
        XCTAssertEqual(descriptor.username, "demo")
        XCTAssertEqual(descriptor.credentialSource, .resolvedPassword("secret"))
    }
}
