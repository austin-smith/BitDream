import Foundation

enum ServerConnectionTester {
    static func test(_ descriptor: TransmissionConnectionDescriptor) async throws -> TransmissionSessionResponseArguments {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let factory = TransmissionConnectionFactory(
            transport: TransmissionTransport(sender: URLSessionTransmissionRPCRequestSender(session: session))
        )
        return try await withThrowingTaskGroup(of: TransmissionSessionResponseArguments.self) { group in
            group.addTask {
                let connection = try await factory.connection(for: descriptor)
                return try await connection.fetchSessionSettings()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(30))
                throw TransmissionError.timeout
            }
            defer { group.cancelAll() }
            guard let response = try await group.next() else { throw CancellationError() }
            return response
        }
    }
}
