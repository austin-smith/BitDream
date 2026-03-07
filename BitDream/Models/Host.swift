import Foundation
import SwiftData

@Model
final class Host {
    @Attribute(.unique) var serverID: String
    var isDefault: Bool
    var isSSL: Bool
    var credentialKey: String?
    var name: String?
    var port: Int16
    var server: String?
    var username: String?
    var version: String?

    init(
        serverID: String = UUID().uuidString,
        isDefault: Bool = false,
        isSSL: Bool = false,
        credentialKey: String? = nil,
        name: String? = nil,
        port: Int16 = 0,
        server: String? = nil,
        username: String? = nil,
        version: String? = nil
    ) {
        self.serverID = serverID
        self.isDefault = isDefault
        self.isSSL = isSSL
        self.credentialKey = credentialKey
        self.name = name
        self.port = port
        self.server = server
        self.username = username
        self.version = version
    }

    @discardableResult
    func ensureCredentialKey() -> String {
        if let existing = credentialKey?.trimmingCharacters(in: .whitespacesAndNewlines), !existing.isEmpty {
            if credentialKey != existing {
                credentialKey = existing
            }
            return existing
        }

        let generated = UUID().uuidString
        credentialKey = generated
        return generated
    }
}

extension TransmissionConnectionDescriptor {
    init(host: Host) {
        self.init(
            scheme: host.isSSL ? "https" : "http",
            host: host.server ?? "",
            port: Int(host.port),
            username: host.username ?? "",
            credentialSource: .keychainCredential(KeychainService.credentialKeyIfPresent(for: host) ?? "")
        )
    }
}
