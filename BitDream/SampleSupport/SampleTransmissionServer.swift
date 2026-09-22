#if BITDREAM_SAMPLE_SUPPORT
import Foundation

/// An in-process RPC server. Every request stays here, including arbitrary URLs
/// entered into the server editor. Actor isolation serializes concurrent RPCs.
actor SampleTransmissionServer: TransmissionRPCRequestSending {
    private var records: [[String: Any]]
    private var session: [String: Any]
    private var nextID = 8
    private let token = "bitdream-sample-session"

    init() throws {
        session = try Self.object(SampleFixtures.sessionConfiguration)
        records = try zip(SampleFixtures.torrents, SampleFixtures.details).map { torrent, detail in
            try Self.object(torrent).merging(Self.object(detail)) { _, detail in detail }
        }
    }

    nonisolated func connection(for descriptor: TransmissionConnectionDescriptor) throws -> TransmissionConnection {
        let endpoint = try TransmissionEndpoint(scheme: descriptor.scheme, host: descriptor.host, port: descriptor.port)
        return TransmissionConnection(endpoint: endpoint, auth: TransmissionAuth(username: "", password: ""),
                                      transport: TransmissionTransport(sender: self))
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        if request.url?.host?.lowercased() == SampleFixtures.remoteServerAddress { return try response(request, status: 401, body: [:]) }
        guard request.value(forHTTPHeaderField: transmissionSessionTokenHeader) == token else {
            return try response(request, status: 409, body: [:])
        }
        guard let data = request.httpBody,
              let body = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = body["method"] as? String,
              let arguments = body["arguments"] as? [String: Any] else {
            return try response(request, body: ["result": "Invalid sample RPC request"])
        }
        do {
            let result = try dispatch(method, arguments)
            return try response(request, body: ["result": "success", "arguments": result])
        } catch {
            return try response(request, body: ["result": error.localizedDescription])
        }
    }

    private func dispatch(_ method: String, _ args: [String: Any]) throws -> [String: Any] {
        switch method {
        case "session-get": return try project(session, fields: args["fields"])
        case "session-stats":
            let data = try JSONSerialization.data(withJSONObject: records)
            let torrents = try JSONDecoder().decode([Torrent].self, from: data)
            return try Self.object(SampleFixtures.statistics(for: torrents))
        case "torrent-get":
            let selected = try indices(args)
            return ["torrents": try selected.map { try project(records[$0], fields: args["fields"]) }]
        case "torrent-add": return try add(args)
        case "free-space": return ["path": args["path"] ?? SampleLibrary.downloadDirectory, "size-bytes": 512_000_000_000, "total_size": 1_000_000_000_000]
        case "port-test": return ["port-is-open": true]
        case "blocklist-update": return ["blocklist-size": session["blocklist-size"] ?? 0]
        default: return try mutate(method, args)
        }
    }

    private func mutate(_ method: String, _ args: [String: Any]) throws -> [String: Any] {
        switch method {
        case "session-set": try updateSession(args)
        case "torrent-rename-path": return try rename(args)
        case "queue-move-top", "queue-move-up", "queue-move-down", "queue-move-bottom":
            try moveQueue(method, args)
        case "torrent-remove":
            let selected = Set(try indices(args))
            records = records.enumerated().filter { !selected.contains($0.offset) }.map(\.element)
            normalizeQueue()
        case "torrent-stop", "torrent-start", "torrent-start-now", "torrent-verify", "torrent-reannounce":
            try playback(method, args)
        case "torrent-set": try update(args)
        case "torrent-set-location":
            guard let path = args["location"] as? String, !path.isEmpty else { throw Failure.invalid("location") }
            for index in try indices(args) { records[index]["downloadDir"] = path }
        default: throw Failure.unsupported(method)
        }
        return [:]
    }

    private func updateSession(_ args: [String: Any]) throws {
        for key in args.keys where session[key] == nil { throw Failure.unsupported("session field \(key)") }
        session.merge(args) { _, new in new }
    }

    private func playback(_ method: String, _ args: [String: Any]) throws {
        // Reannounce does not change torrent state.
        guard method != "torrent-reannounce" else { return }
        for index in try indices(args) {
            let complete = records[index]["percentDone"] as? Double == 1
            records[index]["status"] = method == "torrent-stop" ? 0 : method == "torrent-verify" ? 2 : complete ? 6 : 4
            records[index]["isFinished"] = method == "torrent-stop" && complete
            clearActivity(at: index)
        }
    }

    private func indices(_ args: [String: Any]) throws -> [Int] {
        guard let value = args["ids"] else { return Array(records.indices) }
        guard let ids = value as? [Int] else { throw Failure.invalid("ids") }
        return records.indices.filter { ids.contains(records[$0]["id"] as? Int ?? -1) }
    }

    private func project(_ object: [String: Any], fields value: Any?) throws -> [String: Any] {
        guard let value else { return object }
        guard let fields = value as? [String] else { throw Failure.invalid("fields") }
        for field in fields where object[field] == nil { throw Failure.unsupported("field \(field)") }
        return object.filter { fields.contains($0.key) }
    }

    private func clearActivity(at index: Int) {
        records[index]["rateDownload"] = 0
        records[index]["rateUpload"] = 0
        records[index]["peersConnected"] = 0
        records[index]["peersSendingToUs"] = 0
        records[index]["peersGettingFromUs"] = 0
        records[index]["peers"] = [] as [[String: Any]]
        records[index]["peersFrom"] = ["fromCache": 0, "fromDht": 0, "fromIncoming": 0,
                                        "fromLpd": 0, "fromLtep": 0, "fromPex": 0, "fromTracker": 0]
        records[index]["eta"] = -1
        records[index]["isStalled"] = false
    }

    private func response(_ request: URLRequest, status: Int = 200, body: [String: Any]) throws -> (Data, HTTPURLResponse) {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                             headerFields: [transmissionSessionTokenHeader: token]) else {
            throw Failure.invalid("URL")
        }
        return (try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]), response)
    }

    private static func object<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw Failure.invalid("fixture")
        }
        return result
    }

    private enum Failure: LocalizedError {
        case unsupported(String), invalid(String)
        var errorDescription: String? {
            switch self {
            case .unsupported(let value): "Demo server does not support \(value)."
            case .invalid(let value): "Invalid demo server \(value)."
            }
        }
    }
}

private extension SampleTransmissionServer {
    func update(_ args: [String: Any]) throws {
        let supported: Set<String> = ["ids", "labels", "bandwidthPriority", "files-wanted", "files-unwanted",
                                      "priority-high", "priority-normal", "priority-low"]
        for key in args.keys where !supported.contains(key) { throw Failure.unsupported("torrent field \(key)") }
        var updated = records
        for index in try indices(args) {
            if let labels = args["labels"] as? [String] { updated[index]["labels"] = labels.sorted() }
            if let priority = args["bandwidthPriority"] as? Int { updated[index]["bandwidthPriority"] = priority }
            guard var stats = updated[index]["fileStats"] as? [[String: Any]],
                  let files = updated[index]["files"] as? [[String: Any]] else { throw Failure.invalid("files") }
            try updateFileStats(&stats, args: args)
            updated[index]["fileStats"] = stats
            var wantedSize: Int64 = 0
            var wantedCompleted: Int64 = 0
            for file in files.indices where stats[file]["wanted"] as? Bool == true {
                wantedSize += (files[file]["length"] as? NSNumber)?.int64Value ?? 0
                wantedCompleted += (files[file]["bytesCompleted"] as? NSNumber)?.int64Value ?? 0
            }
            updated[index]["sizeWhenDone"] = wantedSize
            updated[index]["leftUntilDone"] = wantedSize - wantedCompleted
            updated[index]["desiredAvailable"] = wantedSize - wantedCompleted
            updated[index]["percentDone"] = wantedSize == 0 ? 1 : Double(wantedCompleted) / Double(wantedSize)
            updated[index]["isFinished"] = updated[index]["status"] as? Int == 0 && wantedCompleted == wantedSize
            if let status = updated[index]["status"] as? Int, status == 4 || status == 6 {
                let complete = wantedCompleted == wantedSize
                updated[index]["status"] = complete ? 6 : 4
                if complete { stopDownloading(&updated[index]) }
            }
            let rate = (updated[index]["rateDownload"] as? NSNumber)?.int64Value ?? 0
            updated[index]["eta"] = rate > 0 ? Int((wantedSize - wantedCompleted) / rate) : -1
        }
        records = updated
    }

    func stopDownloading(_ record: inout [String: Any]) {
        record["rateDownload"] = 0
        record["peersSendingToUs"] = 0
        record["isStalled"] = false
        guard var peers = record["peers"] as? [[String: Any]] else { return }
        for index in peers.indices {
            peers[index]["rateToClient"] = 0
            peers[index]["isDownloadingFrom"] = false
            peers[index]["clientIsInterested"] = false
            if let flags = peers[index]["flagStr"] as? String {
                peers[index]["flagStr"] = flags.filter { $0 != "D" && $0 != "d" }
            }
        }
        record["peers"] = peers
    }

    func updateFileStats(_ stats: inout [[String: Any]], args: [String: Any]) throws {
        for (key, value) in [("files-wanted", 1), ("files-unwanted", 0),
                             ("priority-high", 1), ("priority-normal", 0), ("priority-low", -1)] {
            guard let selected = args[key] as? [Int] else { continue }
            let targets = selected.isEmpty ? Array(stats.indices) : selected
            for file in targets {
                guard stats.indices.contains(file) else { throw Failure.invalid("file index") }
                if key.hasPrefix("files-") {
                    stats[file]["wanted"] = value == 1
                } else {
                    stats[file]["priority"] = value
                }
            }
        }
    }

    func rename(_ args: [String: Any]) throws -> [String: Any] {
        let selected = try indices(args)
        guard selected.count == 1, let index = selected.first,
              let path = args["path"] as? String, let name = args["name"] as? String,
              !name.isEmpty, !name.contains("/"), name != ".", name != "..",
              var files = records[index]["files"] as? [[String: Any]] else { throw Failure.invalid("rename") }
        let matches = files.indices.filter {
            guard let file = files[$0]["name"] as? String else { return false }
            return file == path || file.hasPrefix(path + "/")
        }
        guard !matches.isEmpty else { throw Failure.invalid("rename path") }
        let parent = path.split(separator: "/").dropLast().joined(separator: "/")
        let replacement = parent.isEmpty ? name : parent + "/" + name
        for file in matches {
            guard let old = files[file]["name"] as? String else { continue }
            files[file]["name"] = replacement + old.dropFirst(path.count)
        }
        records[index]["files"] = files
        if records[index]["name"] as? String == path { records[index]["name"] = name }
        return ["path": path, "name": name, "id": records[index]["id"] ?? 0]
    }

    func add(_ args: [String: Any]) throws -> [String: Any] {
        guard let magnet = args["filename"] as? String,
              let item = (SampleLibrary.items + [SampleLibrary.addedItem]).first(where: { SampleFixtures.magnet(id: $0.id) == magnet }) else {
            throw Failure.unsupported("this input; use the sample magnet from docs/demo-mode.md")
        }
        let duplicate = records.first { $0["magnetLink"] as? String == magnet }
        if let duplicate {
            return ["torrent-duplicate": ["id": duplicate["id"] ?? item.id,
                                           "name": duplicate["name"] ?? item.name,
                                           "hashString": String(format: "%040x", item.id)]]
        }
        var record = try Self.object(SampleFixtures.torrent(item)).merging(Self.object(SampleFixtures.detail(item))) { _, new in new }
        record["id"] = nextID
        record["queuePosition"] = records.count
        record["downloadDir"] = args["download-dir"] ?? session["download-dir"]
        record["status"] = session["start-added-torrents"] as? Bool == true ? (item.completed == item.size ? 6 : 4) : 0
        records.append(record)
        clearActivity(at: records.count - 1)
        defer { nextID += 1 }
        return ["torrent-added": ["id": nextID, "name": item.name, "hashString": String(format: "%040x", item.id)]]
    }

    func normalizeQueue() {
        records.sort { ($0["queuePosition"] as? Int ?? 0) < ($1["queuePosition"] as? Int ?? 0) }
        for index in records.indices { records[index]["queuePosition"] = index }
    }

    func moveQueue(_ method: String, _ args: [String: Any]) throws {
        normalizeQueue()
        let selectedIDs = Set(try indices(args).compactMap { records[$0]["id"] as? Int })
        func selected(_ record: [String: Any]) -> Bool { selectedIDs.contains(record["id"] as? Int ?? -1) }
        switch method {
        case "queue-move-top": records = records.filter(selected) + records.filter { !selected($0) }
        case "queue-move-bottom": records = records.filter { !selected($0) } + records.filter(selected)
        case "queue-move-up":
            for index in records.indices.dropFirst() where selected(records[index]) && !selected(records[index - 1]) {
                records.swapAt(index, index - 1)
            }
        default:
            for index in records.indices.dropLast().reversed() where selected(records[index]) && !selected(records[index + 1]) {
                records.swapAt(index, index + 1)
            }
        }
        for index in records.indices { records[index]["queuePosition"] = index }
    }
}
#endif
