import Foundation

internal let transmissionSessionTokenHeader = "X-Transmission-Session-Id"

internal actor TransmissionSessionTokenStore {
    static let shared = TransmissionSessionTokenStore()

    private var tokens: [String: String]

    init(tokens: [String: String] = [:]) {
        self.tokens = tokens
    }

    func token(for endpoint: String) -> String? {
        tokens[endpoint]
    }

    func setToken(_ token: String, for endpoint: String) {
        tokens[endpoint] = token
    }

    func clearToken(for endpoint: String) {
        tokens.removeValue(forKey: endpoint)
    }
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

internal protocol TransmissionRPCRequestSending: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

internal struct URLSessionTransmissionRPCRequestSender: TransmissionRPCRequestSending {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TransmissionError.invalidResponse
        }

        return (data, httpResponse)
    }
}

internal struct TransmissionRPCTransport: Sendable {
    private let sender: any TransmissionRPCRequestSending
    private let tokenStore: TransmissionSessionTokenStore

    init(
        sender: any TransmissionRPCRequestSending = URLSessionTransmissionRPCRequestSender(),
        tokenStore: TransmissionSessionTokenStore = .shared
    ) {
        self.sender = sender
        self.tokenStore = tokenStore
    }

    func sendEnvelope<Args: Codable, ResponseArgs: Codable & Sendable>(
        method: String,
        arguments: Args,
        config: TransmissionConfig,
        auth: TransmissionAuth,
        responseType: ResponseArgs.Type = ResponseArgs.self
    ) async throws -> TransmissionRPCEnvelope<ResponseArgs> {
        let requestBody = TransmissionGenericRequest(method: method, arguments: arguments)
        let requestData = try JSONEncoder().encode(requestBody)

        return try await sendEnvelope(
            requestData: requestData,
            config: config,
            auth: auth,
            responseType: responseType,
            retrying: false
        )
    }

    func sendRequiredArguments<Args: Codable, ResponseArgs: Codable & Sendable>(
        method: String,
        arguments: Args,
        config: TransmissionConfig,
        auth: TransmissionAuth,
        responseType: ResponseArgs.Type = ResponseArgs.self
    ) async throws -> ResponseArgs {
        let envelope = try await sendEnvelope(
            method: method,
            arguments: arguments,
            config: config,
            auth: auth,
            responseType: responseType
        )

        return try envelope.requireArguments()
    }

    private func sendEnvelope<ResponseArgs: Codable & Sendable>(
        requestData: Data,
        config: TransmissionConfig,
        auth: TransmissionAuth,
        responseType: ResponseArgs.Type,
        retrying: Bool
    ) async throws -> TransmissionRPCEnvelope<ResponseArgs> {
        guard let url = rpcURL(from: config) else {
            throw TransmissionError.invalidEndpointConfiguration
        }

        let endpoint = url.absoluteString
        let currentToken = await tokenStore.token(for: endpoint)
        let request = buildRequest(url: url, requestData: requestData, auth: auth, sessionToken: currentToken)

        let data: Data
        let response: HTTPURLResponse

        do {
            (data, response) = try await sender.send(request)
        } catch {
            throw classifyTransportError(error)
        }

        switch response.statusCode {
        case 200:
            if let refreshedToken = extractSessionToken(from: response) {
                await tokenStore.setToken(refreshedToken, for: endpoint)
            }

            let envelope = try decodeEnvelope(data, as: responseType)
            guard envelope.result == "success" else {
                throw TransmissionError.rpcFailure(result: envelope.result)
            }

            return envelope
        case 401:
            await tokenStore.clearToken(for: endpoint)
            throw TransmissionError.unauthorized
        case 409:
            guard !retrying else {
                throw TransmissionError.httpStatus(code: 409, body: bodyString(from: data))
            }

            guard let nextToken = extractSessionToken(from: response), !nextToken.isEmpty else {
                throw TransmissionError.invalidResponse
            }

            await tokenStore.setToken(nextToken, for: endpoint)

            return try await sendEnvelope(
                requestData: requestData,
                config: config,
                auth: auth,
                responseType: responseType,
                retrying: true
            )
        default:
            throw TransmissionError.httpStatus(code: response.statusCode, body: bodyString(from: data))
        }
    }

    private func rpcURL(from config: TransmissionConfig) -> URL? {
        var endpoint = config
        endpoint.path = "/transmission/rpc"
        return endpoint.url
    }

    private func extractSessionToken(from response: HTTPURLResponse) -> String? {
        for (key, value) in response.allHeaderFields {
            let header = String(describing: key)
            if header.compare(transmissionSessionTokenHeader, options: .caseInsensitive) == .orderedSame {
                return value as? String
            }
        }

        return nil
    }

    private func buildRequest(
        url: URL,
        requestData: Data,
        auth: TransmissionAuth,
        sessionToken: String?
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = requestData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let sessionToken {
            request.setValue(sessionToken, forHTTPHeaderField: transmissionSessionTokenHeader)
        }

        let loginString = "\(auth.username):\(auth.password)"
        let loginData = loginString.data(using: .utf8) ?? Data()
        request.setValue("Basic \(loginData.base64EncodedString())", forHTTPHeaderField: "Authorization")

        return request
    }

    private func decodeEnvelope<ResponseArgs: Codable & Sendable>(
        _ data: Data,
        as responseType: ResponseArgs.Type
    ) throws -> TransmissionRPCEnvelope<ResponseArgs> {
        do {
            return try JSONDecoder().decode(TransmissionRPCEnvelope<ResponseArgs>.self, from: data)
        } catch let error as DecodingError {
            if case .keyNotFound(let key, _) = error, key.stringValue == "result" {
                throw TransmissionError.invalidResponse
            }

            throw TransmissionError.decoding(underlyingDescription: String(describing: error))
        } catch {
            throw TransmissionError.decoding(underlyingDescription: error.localizedDescription)
        }
    }

    private func classifyTransportError(_ error: Error) -> TransmissionError {
        if let transmissionError = error as? TransmissionError {
            return transmissionError
        }

        if error is CancellationError {
            return .cancelled
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return .timeout
            case .cancelled:
                return .cancelled
            default:
                return .transport(underlyingDescription: urlError.localizedDescription)
            }
        }

        return .transport(underlyingDescription: error.localizedDescription)
    }

    private func bodyString(from data: Data) -> String? {
        guard !data.isEmpty else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }
}
