//  Snapshot models shared by app and widget.

import Foundation

public struct SessionOverviewSnapshot: Codable, Equatable {
    public let serverId: String
    public let serverName: String
    public let active: Int
    public let paused: Int
    public let total: Int
    public let totalCount: Int
    public let downloadingCount: Int
    public let completedCount: Int
    public let downloadSpeed: Int64
    public let uploadSpeed: Int64
    public let ratio: Double
    public let timestamp: Date

    public init(serverId: String, serverName: String, active: Int, paused: Int, total: Int, totalCount: Int, downloadingCount: Int, completedCount: Int, downloadSpeed: Int64, uploadSpeed: Int64, ratio: Double, timestamp: Date) {
        self.serverId = serverId
        self.serverName = serverName
        self.active = active
        self.paused = paused
        self.total = total
        self.totalCount = totalCount
        self.downloadingCount = downloadingCount
        self.completedCount = completedCount
        self.downloadSpeed = downloadSpeed
        self.uploadSpeed = uploadSpeed
        self.ratio = ratio
        self.timestamp = timestamp
    }
}

public struct ServerSummary: Codable, Equatable, Identifiable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct ServerIndex: Codable, Equatable {
    public let servers: [ServerSummary]

    public init(servers: [ServerSummary]) {
        self.servers = servers
    }
}


