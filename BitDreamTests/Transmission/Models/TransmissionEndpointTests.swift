import XCTest
@testable import BitDream

final class TransmissionEndpointTests: XCTestCase {
    func testEndpointBuildsCanonicalRPCURL() throws {
        let endpoint = try TransmissionEndpoint(scheme: "http", host: "example.com", port: 9091)

        XCTAssertEqual(endpoint.rpcURL.absoluteString, "http://example.com:9091/transmission/rpc")
        XCTAssertEqual(endpoint.endpointKey, "http://example.com:9091/transmission/rpc")
        XCTAssertEqual(endpoint.scheme, "http")
        XCTAssertEqual(endpoint.host, "example.com")
        XCTAssertEqual(endpoint.port, 9091)
    }

    func testEndpointTrimsHostAndScheme() throws {
        let endpoint = try TransmissionEndpoint(scheme: " HTTPS ", host: " example.com ", port: 9091)

        XCTAssertEqual(endpoint.rpcURL.absoluteString, "https://example.com:9091/transmission/rpc")
    }

    func testEndpointRejectsEmptyHost() async {
        await assertThrowsTransmissionError(.invalidEndpointConfiguration) {
            _ = try TransmissionEndpoint(scheme: "http", host: "   ", port: 9091)
        }
    }

    func testEndpointRejectsInvalidHost() async {
        await assertThrowsTransmissionError(.invalidEndpointConfiguration) {
            _ = try TransmissionEndpoint(scheme: "http", host: "bad host", port: 9091)
        }
    }

    func testEndpointRejectsMissingPortFromConfig() async {
        var config = TransmissionConfig()
        config.scheme = "http"
        config.host = "example.com"

        await assertThrowsTransmissionError(.invalidEndpointConfiguration) {
            _ = try TransmissionEndpoint(config: config)
        }
    }

    func testEndpointAlwaysUsesDefaultRPCPath() throws {
        var config = makeConfig()
        config.path = "/custom/path"

        let endpoint = try TransmissionEndpoint(config: config)

        XCTAssertEqual(endpoint.rpcURL.path, "/transmission/rpc")
    }
}
