import SwiftData

struct PersistenceController {
    static let shared = PersistenceController()
    private static let hostStoreID = "bitdream.persistence.hosts"
    private static let hostSchema = Schema([Host.self])

    let container: ModelContainer

    init() {
        let config = ModelConfiguration(
            Self.hostStoreID,
            schema: Self.hostSchema,
            cloudKitDatabase: .none
        )

        do {
            container = try ModelContainer(for: Self.hostSchema, configurations: [config])
        } catch {
            fatalError("Failed to initialize SwiftData container: \(error.localizedDescription)")
        }
    }
}
