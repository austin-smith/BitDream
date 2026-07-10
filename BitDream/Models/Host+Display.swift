import Foundation

extension Host {
    /// User-facing name, falling back to the server address when no name is set.
    var displayName: String {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedName.isEmpty ? (server ?? "Unnamed Server") : trimmedName
    }

    /// "host:port" description of the server endpoint.
    var endpointDescription: String {
        "\(server ?? "Unknown host"):\(port)"
    }
}

extension [Host] {
    /// Hosts ordered for display: by name, then endpoint.
    func sortedByDisplayName() -> [Host] {
        sorted { lhs, rhs in
            let nameComparison = lhs.displayName.localizedStandardCompare(rhs.displayName)
            if nameComparison != .orderedSame {
                return nameComparison == .orderedAscending
            }
            return lhs.endpointDescription.localizedStandardCompare(rhs.endpointDescription) == .orderedAscending
        }
    }
}
