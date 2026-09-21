import Foundation
import SwiftData

struct PersistenceController {
    // The test scheme explicitly requests an ephemeral store. Unsigned test hosts
    // cannot rely on provisioned App Group access, and must not mutate local servers.
    static let shared = PersistenceController(
        inMemory: AppIdentity.isDevelopment && ProcessInfo.processInfo.environment["BITDREAM_TEST_IN_MEMORY_STORE"] == "1"
    )
    private static let hostStoreID = "bitdream.persistence.hosts"
    private static let hostSchema = Schema([Host.self])

    let container: ModelContainer
    let isInMemory: Bool

    init(inMemory: Bool = false) {
        isInMemory = inMemory
        let config = ModelConfiguration(
            Self.hostStoreID,
            schema: Self.hostSchema,
            isStoredInMemoryOnly: inMemory,
            groupContainer: inMemory ? .none : .identifier(AppGroup.identifier),
            cloudKitDatabase: .none
        )

        do {
            container = try ModelContainer(for: Self.hostSchema, configurations: [config])
        } catch {
            fatalError("Failed to initialize SwiftData container: \(error.localizedDescription)")
        }
    }
}
