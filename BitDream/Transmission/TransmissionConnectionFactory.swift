import Foundation

internal struct TransmissionCredentialResolver: Sendable {
    private let resolvePassword: @Sendable (TransmissionCredentialSource) -> String

    init(resolvePassword: @escaping @Sendable (TransmissionCredentialSource) -> String) {
        self.resolvePassword = resolvePassword
    }

    func password(for source: TransmissionCredentialSource) -> String {
        resolvePassword(source)
    }

    static let live = Self { source in
        switch source {
        case .resolvedPassword(let password):
            return password
        case .keychainCredential(let credentialKey):
            let trimmedKey = credentialKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedKey.isEmpty else {
                return ""
            }

            return KeychainService.readPassword(credentialKey: trimmedKey)
        }
    }
}

internal actor TransmissionConnectionFactory {
    private struct Key: Hashable, Sendable {
        let endpoint: TransmissionEndpoint
        let auth: TransmissionAuth
    }

    private let transport: TransmissionTransport
    private let credentialResolver: TransmissionCredentialResolver
    private var connections: [Key: TransmissionConnection] = [:]

    init(
        transport: TransmissionTransport = TransmissionTransport(),
        credentialResolver: TransmissionCredentialResolver = .live
    ) {
        self.transport = transport
        self.credentialResolver = credentialResolver
    }

    func connection(for descriptor: TransmissionConnectionDescriptor) throws -> TransmissionConnection {
        let endpoint = try TransmissionEndpoint(
            scheme: descriptor.scheme,
            host: descriptor.host,
            port: descriptor.port
        )
        let auth = TransmissionAuth(
            username: descriptor.username,
            password: credentialResolver.password(for: descriptor.credentialSource)
        )
        let key = Key(endpoint: endpoint, auth: auth)

        if let existing = connections[key] {
            return existing
        }

        let connection = TransmissionConnection(endpoint: endpoint, auth: auth, transport: transport)
        connections[key] = connection
        return connection
    }
}
