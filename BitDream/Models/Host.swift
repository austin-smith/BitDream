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
}
