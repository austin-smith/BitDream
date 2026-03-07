import Foundation

internal actor TransmissionConnection {
    private let endpoint: TransmissionEndpoint
    private let auth: TransmissionAuth
    private let transport: TransmissionTransport

    private var sessionToken: String?

    init(
        endpoint: TransmissionEndpoint,
        auth: TransmissionAuth,
        transport: TransmissionTransport = TransmissionTransport()
    ) {
        self.endpoint = endpoint
        self.auth = auth
        self.transport = transport
    }

    func sendEnvelope<Args: Codable & Sendable, ResponseArgs: Codable & Sendable>(
        method: String,
        arguments: Args,
        responseType: ResponseArgs.Type = ResponseArgs.self
    ) async throws -> TransmissionRPCEnvelope<ResponseArgs> {
        let tokenAtRequestStart = sessionToken

        do {
            let result = try await transport.sendEnvelope(
                method: method,
                arguments: arguments,
                endpoint: endpoint,
                auth: auth,
                sessionToken: tokenAtRequestStart,
                responseType: responseType
            )

            applyTokenMutation(result.tokenMutation)
            return result.envelope
        } catch let error as TransmissionTransportFailure {
            applyTokenMutation(error.tokenMutation)
            throw error.transmissionError
        }
    }

    func sendRequiredArguments<Args: Codable & Sendable, ResponseArgs: Codable & Sendable>(
        method: String,
        arguments: Args,
        responseType: ResponseArgs.Type = ResponseArgs.self
    ) async throws -> ResponseArgs {
        let envelope = try await sendEnvelope(
            method: method,
            arguments: arguments,
            responseType: responseType
        )

        return try envelope.requireArguments()
    }

    func sendStatusRequest<Args: Codable & Sendable>(
        method: String,
        arguments: Args
    ) async throws {
        _ = try await sendEnvelope(
            method: method,
            arguments: arguments,
            responseType: EmptyArguments.self
        )
    }

    func sendTorrentAdd(arguments: StringArguments) async throws -> TransmissionTorrentAddOutcome {
        let responseArguments = try await sendRequiredArguments(
            method: "torrent-add",
            arguments: arguments,
            responseType: [String: TorrentAddResponseArgs].self
        )

        return try TransmissionTorrentAddOutcome(arguments: responseArguments)
    }

    func currentSessionToken() -> String? {
        sessionToken
    }

    func setSessionTokenForTesting(_ token: String?) {
        sessionToken = token
    }

    private func applyTokenMutation(_ mutation: TransmissionTransportTokenMutation) {
        switch mutation {
        case .none:
            return
        case .set(let matching, let token):
            if matching.contains(where: { $0 == sessionToken }) {
                sessionToken = token
            }
        case .clear(let matching):
            if matching.contains(where: { $0 == sessionToken }) {
                sessionToken = nil
            }
        }
    }
}
