import Foundation

public typealias TransmissionConfig = URLComponents

internal struct TransmissionEndpoint: Hashable, Sendable {
    let scheme: String
    let host: String
    let port: Int
    let rpcURL: URL
    let endpointKey: String

    init(scheme: String, host: String, port: Int) throws {
        let normalizedScheme = scheme.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedScheme.isEmpty, !normalizedHost.isEmpty else {
            throw TransmissionError.invalidEndpointConfiguration
        }

        guard normalizedScheme == "http" || normalizedScheme == "https" else {
            throw TransmissionError.invalidEndpointConfiguration
        }

        guard normalizedHost.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            throw TransmissionError.invalidEndpointConfiguration
        }

        guard (1...65_535).contains(port) else {
            throw TransmissionError.invalidEndpointConfiguration
        }

        var components = URLComponents()
        components.scheme = normalizedScheme
        components.host = normalizedHost
        components.port = port
        components.path = "/transmission/rpc"

        guard let rpcURL = components.url else {
            throw TransmissionError.invalidEndpointConfiguration
        }

        self.scheme = normalizedScheme
        self.host = normalizedHost
        self.port = port
        self.rpcURL = rpcURL
        self.endpointKey = rpcURL.absoluteString
    }

    init(config: TransmissionConfig) throws {
        try self.init(
            scheme: config.scheme ?? "",
            host: config.host ?? "",
            port: config.port ?? 0
        )
    }
}

public struct TransmissionAuth: Hashable, Sendable {
    let username: String
    let password: String
}

internal struct TransmissionRPCEnvelope<Arguments: Codable & Sendable>: Codable, Sendable {
    let result: String
    let arguments: Arguments?
    let tag: Int?

    func requireArguments() throws -> Arguments {
        guard let arguments else {
            throw TransmissionError.invalidResponse
        }

        return arguments
    }
}

internal enum TransmissionError: Error, Sendable {
    case invalidEndpointConfiguration
    case unauthorized
    case transport(underlyingDescription: String)
    case timeout
    case cancelled
    case httpStatus(code: Int, body: String?)
    case rpcFailure(result: String)
    case invalidResponse
    case decoding(underlyingDescription: String)
}

internal enum TransmissionTorrentAddOutcome: Sendable {
    case added(TorrentAddResponseArgs)
    case duplicate(TorrentAddResponseArgs)

    init(arguments: [String: TorrentAddResponseArgs]?) throws {
        guard let arguments else {
            throw TransmissionError.invalidResponse
        }

        if let added = arguments["torrent-added"] {
            self = .added(added)
            return
        }

        if let duplicate = arguments["torrent-duplicate"] {
            self = .duplicate(duplicate)
            return
        }

        throw TransmissionError.invalidResponse
    }
}
