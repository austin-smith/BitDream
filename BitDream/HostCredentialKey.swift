import Foundation

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
