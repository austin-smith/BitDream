import Foundation
import Observation

/// Draft state, validation, and save flow for the server editor form.
/// Shared by the iOS and macOS editors so field handling cannot drift between platforms.
@MainActor
@Observable
final class ServerFormModel {
    struct Values: Equatable {
        var name = ""
        var address = ""
        var port = ServerFormModel.defaultPort
        var username = ""
        var password = ""
        var isDefault = false
        var isSSL = false
        var connectionRoute = "system"
        var tailscaleAccountID: String?
    }

    enum Field: Equatable {
        case address
        case port
    }

    enum SaveResult {
        case validationFailed(Field)
        case saved(Host)
    }

    enum TailscaleDestination: Hashable {
        case none
        case machine(String)
        case manual
    }

    private enum TailscaleAddressEntry {
        case inferred
        case machine
        case manual
    }

    nonisolated static let defaultPort = 9091
    nonisolated static let portRange = 1...65535

    private(set) var host: Host?
    var values = Values()
    private var initialValues = Values()
    private(set) var isSaving = false
    private(set) var hasAttemptedSave = false
    private var tailscaleAddressEntry = TailscaleAddressEntry.inferred

    nonisolated init() {}

    var isAddNew: Bool { host == nil }

    var hasUnsavedChanges: Bool { values != initialValues }

    var isAddressValid: Bool {
        !values.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isPortValid: Bool {
        Self.portRange.contains(values.port)
    }

    var isEnteringTailscaleAddress: Bool { tailscaleAddressEntry == .manual }

    func tailscaleDestination(in peers: [TailscalePeer]) -> TailscaleDestination {
        if isEnteringTailscaleAddress { return .manual }
        return selectedTailscalePeerID(in: peers).map(TailscaleDestination.machine) ?? .none
    }

    /// Infer how to edit an existing destination once machines are available.
    /// Subsequent refreshes must never switch an explicitly chosen entry method.
    func resolveTailscaleAddressEntry(in peers: [TailscalePeer]) {
        guard tailscaleAddressEntry == .inferred, !peers.isEmpty else { return }
        tailscaleAddressEntry = values.address.isEmpty || selectedTailscalePeerID(in: peers) != nil
            ? .machine : .manual
    }

    func selectTailscaleDestination(_ destination: TailscaleDestination, from peers: [TailscalePeer]) {
        switch destination {
        case .none: break
        case .manual: tailscaleAddressEntry = .manual
        case .machine(let id): selectTailscalePeer(id: id, from: peers)
        }
    }

    /// Derive selection from the saved address so refreshes and manual edits
    /// cannot leave a separate device selection out of sync with the RPC target.
    func selectedTailscalePeerID(in peers: [TailscalePeer]) -> String? {
        let matches = peers.filter { $0.matches(host: values.address) }
        return matches.count == 1 ? matches.first?.id : nil
    }

    func selectTailscalePeer(id: String?, from peers: [TailscalePeer]) {
        guard let peer = peers.first(where: { $0.id == id }) else { return }
        tailscaleAddressEntry = .machine
        values.address = peer.address
        if values.name.isEmpty { values.name = peer.name }
    }

    private var firstInvalidField: Field? {
        if !isAddressValid { return .address }
        if !isPortValid { return .port }
        return nil
    }

    /// Message for the first invalid field, shown once a save has been attempted.
    var validationMessage: String? {
        guard hasAttemptedSave else { return nil }
        if !isAddressValid {
            return values.connectionRoute == "tailscale" && !isEnteringTailscaleAddress
                ? "Choose a machine." : "Address is required."
        }
        if !isPortValid { return "Port must be between 1 and 65535." }
        return nil
    }

    /// Loads the form from the given host, or prepares defaults for a new server.
    func configure(host: Host?, store: TransmissionStore) {
        self.host = host
        tailscaleAddressEntry = .inferred

        if let host {
            values = Values(
                name: host.name ?? "",
                address: host.server ?? "",
                port: Int(host.port),
                username: host.username ?? "",
                password: storedPassword(for: host),
                isDefault: host.isDefault,
                isSSL: host.isSSL,
                connectionRoute: host.connectionRoute ?? "system",
                tailscaleAccountID: host.tailscaleAccountID
            )
        } else {
            values = Values(isDefault: store.host == nil)
        }

        initialValues = values
        hasAttemptedSave = false
        isSaving = false
    }

    /// The Default toggle is locked when the choice is forced:
    /// the first server is always the default, and the only remaining server stays the default.
    func canEditDefaultToggle(hostCount: Int) -> Bool {
        isAddNew ? hostCount > 0 : hostCount > 1
    }

    func save(
        store: TransmissionStore,
        hostRepository: any HostPersisting = HostRepository.shared
    ) async throws -> SaveResult {
        hasAttemptedSave = true
        if let firstInvalidField {
            return .validationFailed(firstInvalidField)
        }

        isSaving = true
        defer { isSaving = false }

        let draft = HostDraft(
            name: values.name,
            server: values.address,
            port: values.port,
            username: values.username,
            isSSL: values.isSSL,
            isDefault: values.isDefault,
            password: values.password,
            connectionRoute: values.connectionRoute,
            tailscaleAccountID: values.tailscaleAccountID
        )

        let savedHost: Host
        if let host {
            savedHost = try await updateExistingServer(
                host: host,
                draft: draft,
                store: store,
                hostRepository: hostRepository
            )
        } else {
            savedHost = try await saveNewServer(
                draft: draft,
                store: store,
                hostRepository: hostRepository
            )
        }

        initialValues = values
        return .saved(savedHost)
    }

    private func storedPassword(for host: Host) -> String {
        guard let credentialKey = KeychainService.credentialKeyIfPresent(for: host) else { return "" }
        return KeychainService.readPassword(credentialKey: credentialKey)
    }
}
