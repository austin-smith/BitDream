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
        let route: String
        let accountID: String?
        let generation: UInt64
    }

    private let transport: TransmissionTransport
    private let tailscale: EmbeddedTailscaleService
    private let credentialResolver: TransmissionCredentialResolver
    private var connections: [Key: TransmissionConnection] = [:]

    init(
        transport: TransmissionTransport = TransmissionTransport(),
        credentialResolver: TransmissionCredentialResolver = .live,
        tailscale: EmbeddedTailscaleService = .shared
    ) {
        self.transport = transport
        self.tailscale = tailscale
        self.credentialResolver = credentialResolver
    }

    func connection(for descriptor: TransmissionConnectionDescriptor) async throws -> TransmissionConnection {
        let endpoint = try TransmissionEndpoint(
            scheme: descriptor.scheme,
            host: descriptor.host,
            port: descriptor.port
        )
        let auth = TransmissionAuth(
            username: descriptor.username,
            password: credentialResolver.password(for: descriptor.credentialSource)
        )
        guard let route = ServerConnectionRoute(rawValue: descriptor.connectionRoute) else {
            throw TailscaleError.invalidRoute
        }
        var selectedTransport = transport
        var generation: UInt64 = 0
        if route == .tailscale {
            guard let accountID = descriptor.tailscaleAccountID else { throw TailscaleError.accountMismatch }
            let sender = try await tailscale.sender(accountID: accountID, endpoint: endpoint)
            selectedTransport = TransmissionTransport(sender: sender)
            generation = sender.generation
            connections = connections.filter { $0.key.route != "tailscale" || $0.key.generation == generation }
        }
        let key = Key(endpoint: endpoint, auth: auth, route: route.rawValue,
                      accountID: descriptor.tailscaleAccountID, generation: generation)

        if let existing = connections[key] {
            return existing
        }

        let connection = TransmissionConnection(endpoint: endpoint, auth: auth, transport: selectedTransport)
        connections[key] = connection
        return connection
    }
}
