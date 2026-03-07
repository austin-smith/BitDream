import Foundation

internal struct TransmissionSessionFieldQuerySpec: Sendable {
    let fields: [String]

    var arguments: StringListArguments {
        ["fields": fields]
    }
}

internal enum TransmissionSessionQuerySpec {
    static let sessionSettings = TransmissionSessionFieldQuerySpec(fields: [
        "download-dir",
        "version",
        "speed-limit-down",
        "speed-limit-down-enabled",
        "speed-limit-up",
        "speed-limit-up-enabled",
        "alt-speed-down",
        "alt-speed-up",
        "alt-speed-enabled",
        "alt-speed-time-begin",
        "alt-speed-time-end",
        "alt-speed-time-enabled",
        "alt-speed-time-day",
        "incomplete-dir",
        "incomplete-dir-enabled",
        "start-added-torrents",
        "trash-original-torrent-files",
        "rename-partial-files",
        "download-queue-enabled",
        "download-queue-size",
        "seed-queue-enabled",
        "seed-queue-size",
        "seedRatioLimited",
        "seedRatioLimit",
        "idle-seeding-limit",
        "idle-seeding-limit-enabled",
        "queue-stalled-enabled",
        "queue-stalled-minutes",
        "peer-port",
        "peer-port-random-on-start",
        "port-forwarding-enabled",
        "dht-enabled",
        "pex-enabled",
        "lpd-enabled",
        "encryption",
        "utp-enabled",
        "peer-limit-global",
        "peer-limit-per-torrent",
        "blocklist-enabled",
        "blocklist-size",
        "blocklist-url",
        "default-trackers"
    ])
}

internal extension TransmissionConnection {
    func fetchSessionStats() async throws -> SessionStats {
        try await sendRequiredArguments(
            method: "session-stats",
            arguments: EmptyArguments(),
            responseType: SessionStats.self
        )
    }

    func fetchSessionSettings() async throws -> TransmissionSessionResponseArguments {
        try await sendRequiredArguments(
            method: "session-get",
            arguments: TransmissionSessionQuerySpec.sessionSettings.arguments,
            responseType: TransmissionSessionResponseArguments.self
        )
    }
}
