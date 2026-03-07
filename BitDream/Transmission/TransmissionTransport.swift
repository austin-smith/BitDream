import Foundation

internal let transmissionSessionTokenHeader = "X-Transmission-Session-Id"

private struct TransmissionRPCEnvelopeHeader: Decodable, Sendable {
    let result: String
    let tag: Int?
}

private struct TransmissionTransportRequestContext: Sendable {
    let endpoint: TransmissionEndpoint
    let auth: TransmissionAuth
    let requestData: Data
    let initialToken: String?
    let requestToken: String?

    func retrying(with requestToken: String) -> Self {
        Self(
            endpoint: endpoint,
            auth: auth,
            requestData: requestData,
            initialToken: initialToken,
            requestToken: requestToken
        )
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

internal struct TransmissionTransportEnvelopeResult<ResponseArgs: Codable & Sendable>: Sendable {
    let envelope: TransmissionRPCEnvelope<ResponseArgs>
    let tokenMutation: TransmissionTransportTokenMutation
}

internal enum TransmissionTransportTokenMutation: Sendable {
    case none
    case set(matching: [String?], token: String)
    case clear(matching: [String?])
}

internal struct TransmissionTransportFailure: Error, Sendable {
    let transmissionError: TransmissionError
    let tokenMutation: TransmissionTransportTokenMutation
}

internal struct TransmissionTransport: Sendable {
    private let sender: any TransmissionRPCRequestSending

    init(sender: any TransmissionRPCRequestSending = URLSessionTransmissionRPCRequestSender()) {
        self.sender = sender
    }

    func sendEnvelope<Args: Codable & Sendable, ResponseArgs: Codable & Sendable>(
        method: String,
        arguments: Args,
        endpoint: TransmissionEndpoint,
        auth: TransmissionAuth,
        sessionToken: String? = nil,
        responseType: ResponseArgs.Type = ResponseArgs.self
    ) async throws -> TransmissionTransportEnvelopeResult<ResponseArgs> {
        let requestBody = TransmissionGenericRequest(method: method, arguments: arguments)
        let requestData = try JSONEncoder().encode(requestBody)
        let context = TransmissionTransportRequestContext(
            endpoint: endpoint,
            auth: auth,
            requestData: requestData,
            initialToken: sessionToken,
            requestToken: sessionToken
        )

        return try await sendEnvelope(context: context, responseType: responseType, retrying: false)
    }

    func sendRequiredArguments<Args: Codable & Sendable, ResponseArgs: Codable & Sendable>(
        method: String,
        arguments: Args,
        endpoint: TransmissionEndpoint,
        auth: TransmissionAuth,
        sessionToken: String? = nil,
        responseType: ResponseArgs.Type = ResponseArgs.self
    ) async throws -> TransmissionTransportEnvelopeResult<ResponseArgs> {
        let result = try await sendEnvelope(
            method: method,
            arguments: arguments,
            endpoint: endpoint,
            auth: auth,
            sessionToken: sessionToken,
            responseType: responseType
        )

        _ = try result.envelope.requireArguments()
        return result
    }
}

private extension TransmissionTransport {
    func sendEnvelope<ResponseArgs: Codable & Sendable>(
        context: TransmissionTransportRequestContext,
        responseType: ResponseArgs.Type,
        retrying: Bool
    ) async throws -> TransmissionTransportEnvelopeResult<ResponseArgs> {
        let request = buildRequest(for: context)
        let payload = try await performRequest(request)

        switch payload.response.statusCode {
        case 200:
            return try successfulResult(for: payload, context: context, responseType: responseType)
        case 401:
            throw failure(
                .unauthorized,
                mutation: .clear(matching: tokenCandidates(initialToken: context.initialToken, requestToken: context.requestToken))
            )
        case 409:
            return try await handleConflict(
                payload: payload,
                context: context,
                responseType: responseType,
                retrying: retrying
            )
        default:
            throw failure(.httpStatus(code: payload.response.statusCode, body: bodyString(from: payload.data)))
        }
    }

    func performRequest(_ request: URLRequest) async throws -> (data: Data, response: HTTPURLResponse) {
        do {
            let (data, response) = try await sender.send(request)
            return (data, response)
        } catch {
            throw failure(classifyTransportError(error))
        }
    }

    func successfulResult<ResponseArgs: Codable & Sendable>(
        for payload: (data: Data, response: HTTPURLResponse),
        context: TransmissionTransportRequestContext,
        responseType: ResponseArgs.Type
    ) throws -> TransmissionTransportEnvelopeResult<ResponseArgs> {
        let envelopeHeader = try decodeEnvelopeHeader(payload.data)
        guard envelopeHeader.result == "success" else {
            throw failure(.rpcFailure(result: envelopeHeader.result))
        }

        let envelope = try decodeEnvelope(payload.data, as: responseType)
        let tokenMutation = successTokenMutation(
            initialToken: context.initialToken,
            requestToken: context.requestToken,
            refreshedToken: extractSessionToken(from: payload.response)
        )

        return TransmissionTransportEnvelopeResult(envelope: envelope, tokenMutation: tokenMutation)
    }

    func handleConflict<ResponseArgs: Codable & Sendable>(
        payload: (data: Data, response: HTTPURLResponse),
        context: TransmissionTransportRequestContext,
        responseType: ResponseArgs.Type,
        retrying: Bool
    ) async throws -> TransmissionTransportEnvelopeResult<ResponseArgs> {
        if retrying {
            throw repeatedConflictFailure(payload: payload, context: context)
        }

        guard let nextToken = extractSessionToken(from: payload.response), !nextToken.isEmpty else {
            throw failure(.invalidResponse)
        }

        return try await sendEnvelope(
            context: context.retrying(with: nextToken),
            responseType: responseType,
            retrying: true
        )
    }

    func repeatedConflictFailure(
        payload: (data: Data, response: HTTPURLResponse),
        context: TransmissionTransportRequestContext
    ) -> TransmissionTransportFailure {
        let fallbackToken = extractSessionToken(from: payload.response) ?? context.requestToken
        let mutation: TransmissionTransportTokenMutation

        if let fallbackToken, !fallbackToken.isEmpty {
            mutation = .set(
                matching: setCandidates(
                    initialToken: context.initialToken,
                    requestToken: context.requestToken,
                    newToken: fallbackToken
                ),
                token: fallbackToken
            )
        } else {
            mutation = .none
        }

        return failure(
            .httpStatus(code: 409, body: bodyString(from: payload.data)),
            mutation: mutation
        )
    }

    func failure(
        _ error: TransmissionError,
        mutation: TransmissionTransportTokenMutation = .none
    ) -> TransmissionTransportFailure {
        TransmissionTransportFailure(transmissionError: error, tokenMutation: mutation)
    }

    func successTokenMutation(
        initialToken: String?,
        requestToken: String?,
        refreshedToken: String?
    ) -> TransmissionTransportTokenMutation {
        let effectiveToken = refreshedToken ?? requestToken

        guard let effectiveToken, !effectiveToken.isEmpty else {
            return .none
        }

        let candidates = setCandidates(
            initialToken: initialToken,
            requestToken: requestToken,
            newToken: effectiveToken
        )

        if refreshedToken != nil || effectiveToken != initialToken {
            return .set(matching: candidates, token: effectiveToken)
        }

        return .none
    }

    func tokenCandidates(initialToken: String?, requestToken: String?) -> [String?] {
        var candidates = [initialToken]
        if !candidates.contains(where: { $0 == requestToken }) {
            candidates.append(requestToken)
        }
        return candidates
    }

    func setCandidates(
        initialToken: String?,
        requestToken: String?,
        newToken: String
    ) -> [String?] {
        var candidates = tokenCandidates(initialToken: initialToken, requestToken: requestToken)

        if newToken != initialToken && !candidates.contains(where: { $0 == nil }) {
            candidates.append(nil)
        }

        return candidates
    }

    func extractSessionToken(from response: HTTPURLResponse) -> String? {
        for (key, value) in response.allHeaderFields {
            let header = String(describing: key)
            if header.compare(transmissionSessionTokenHeader, options: .caseInsensitive) == .orderedSame {
                return value as? String
            }
        }

        return nil
    }

    func buildRequest(for context: TransmissionTransportRequestContext) -> URLRequest {
        var request = URLRequest(url: context.endpoint.rpcURL)
        request.httpMethod = "POST"
        request.httpBody = context.requestData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let sessionToken = context.requestToken {
            request.setValue(sessionToken, forHTTPHeaderField: transmissionSessionTokenHeader)
        }

        let loginString = "\(context.auth.username):\(context.auth.password)"
        let loginData = loginString.data(using: .utf8) ?? Data()
        request.setValue("Basic \(loginData.base64EncodedString())", forHTTPHeaderField: "Authorization")

        return request
    }

    func decodeEnvelope<ResponseArgs: Codable & Sendable>(
        _ data: Data,
        as responseType: ResponseArgs.Type
    ) throws -> TransmissionRPCEnvelope<ResponseArgs> {
        do {
            return try JSONDecoder().decode(TransmissionRPCEnvelope<ResponseArgs>.self, from: data)
        } catch let error as DecodingError {
            if case .keyNotFound(let key, _) = error, key.stringValue == "result" {
                throw failure(.invalidResponse)
            }

            throw failure(.decoding(underlyingDescription: String(describing: error)))
        } catch {
            throw failure(.decoding(underlyingDescription: error.localizedDescription))
        }
    }

    func decodeEnvelopeHeader(_ data: Data) throws -> TransmissionRPCEnvelopeHeader {
        do {
            return try JSONDecoder().decode(TransmissionRPCEnvelopeHeader.self, from: data)
        } catch let error as DecodingError {
            if case .keyNotFound(let key, _) = error, key.stringValue == "result" {
                throw failure(.invalidResponse)
            }

            throw failure(.decoding(underlyingDescription: String(describing: error)))
        } catch {
            throw failure(.decoding(underlyingDescription: error.localizedDescription))
        }
    }

    func classifyTransportError(_ error: Error) -> TransmissionError {
        if let transportFailure = error as? TransmissionTransportFailure {
            return transportFailure.transmissionError
        }

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

    func bodyString(from data: Data) -> String? {
        guard !data.isEmpty else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }
}
