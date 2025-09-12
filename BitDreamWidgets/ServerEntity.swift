import AppIntents
import Foundation

struct ServerEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Server"

    static var defaultQuery = ServerQuery()

    @Property(title: "Server")
    var name: String

    @Property(title: "ID")
    var id: String

    var displayRepresentation: DisplayRepresentation {
        .init(stringLiteral: name)
    }

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

struct ServerQuery: EntityQuery {
    func entities(for identifiers: [ServerEntity.ID]) async throws -> [ServerEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ServerEntity] {
        guard let url = AppGroup.Files.serversIndexURL(),
              let index: ServerIndex = AppGroupJSON.read(ServerIndex.self, from: url) else {
            return []
        }
        return index.servers.map { ServerEntity(id: $0.id, name: $0.name) }
    }
}


