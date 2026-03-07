import XCTest
@testable import BitDream

final class TransportConcurrencyTests: XCTestCase {
    func testConcurrentRequestsRetryWithSharedRefreshedToken() async throws {
        let sender = ConcurrentRefreshSender()
        let transport = TransmissionRPCTransport(sender: sender, tokenStore: TransmissionSessionTokenStore())

        async let first: TransmissionRPCEnvelope<SessionStats> = transport.sendEnvelope(
            method: "session-stats",
            arguments: EmptyArguments(),
            config: makeConfig(),
            auth: makeAuth(),
            responseType: SessionStats.self
        )
        async let second: TransmissionRPCEnvelope<SessionStats> = transport.sendEnvelope(
            method: "session-stats",
            arguments: EmptyArguments(),
            config: makeConfig(),
            auth: makeAuth(),
            responseType: SessionStats.self
        )

        _ = try await (first, second)

        let requests = await sender.capturedRequests()
        XCTAssertEqual(requests.count, 4)
        XCTAssertEqual(requests.filter { $0.sessionToken == nil }.count, 2)
        XCTAssertEqual(requests.filter { $0.sessionToken == "shared-token" }.count, 2)
    }

    func testConcurrentUnauthorizedDoesNotLeaveStaleTokenBehind() async throws {
        let tokenStore = TransmissionSessionTokenStore()
        await tokenStore.setToken("stale-token", for: "http://example.com:9091/transmission/rpc")

        let sender = ConcurrentUnauthorizedRefreshSender()
        let transport = TransmissionRPCTransport(sender: sender, tokenStore: tokenStore)

        async let unauthorizedAttempt = requestOutcome(transport: transport)
        async let refreshedAttempt = requestOutcome(transport: transport)

        let outcomes = await [unauthorizedAttempt, refreshedAttempt]
        XCTAssertEqual(outcomes.filter { $0 == .success }.count, 1)
        XCTAssertEqual(outcomes.filter { $0 == .unauthorized }.count, 1)

        _ = try await transport.sendEnvelope(
            method: "session-stats",
            arguments: EmptyArguments(),
            config: makeConfig(),
            auth: makeAuth(),
            responseType: SessionStats.self
        )

        let requests = await sender.capturedRequests()
        XCTAssertEqual(requests.filter { $0.sessionToken == "stale-token" }.count, 2)
        XCTAssertEqual(requests.filter { $0.sessionToken == "new-token" }.count, 2)
    }
}
