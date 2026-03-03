import Foundation
import CoreData

// TODO(remove-credentialkey-backfill): Delete this file after migration sunset.
// Keep only a permanent credential-key helper where needed, and remove runtime backfill paths.

@discardableResult
func ensureCredentialKey(for host: Host) -> String {
    if let existing = host.credentialKey?.trimmingCharacters(in: .whitespacesAndNewlines), !existing.isEmpty {
        if host.credentialKey != existing {
            host.credentialKey = existing
        }
        return existing
    }

    let generated = UUID().uuidString
    host.credentialKey = generated
    return generated
}

func backfillMissingCredentialKeys(in viewContext: NSManagedObjectContext) {
    viewContext.performAndWait {
        let request = NSFetchRequest<Host>(entityName: "Host")
        request.predicate = NSPredicate(format: "credentialKey == nil OR credentialKey == ''")

        do {
            let hosts = try viewContext.fetch(request)
            guard !hosts.isEmpty else { return }

            hosts.forEach { host in
                _ = ensureCredentialKey(for: host)
            }

            if viewContext.hasChanges {
                try viewContext.save()
            }
        } catch {
            print("Failed to backfill host credential keys: \(error)")
        }
    }
}
