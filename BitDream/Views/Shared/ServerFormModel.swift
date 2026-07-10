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
    }

    enum Field: Equatable {
        case address
        case port
    }

    enum SaveResult {
        case validationFailed(Field)
        case saved(Host)
    }

    nonisolated static let defaultPort = 9091
    nonisolated static let portRange = 1...65535

    private(set) var host: Host?
    var values = Values()
    private var initialValues = Values()
    private(set) var isSaving = false
    private(set) var hasAttemptedSave = false

    nonisolated init() {}

    var isAddNew: Bool { host == nil }

    var hasUnsavedChanges: Bool { values != initialValues }

    var isAddressValid: Bool {
        !values.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isPortValid: Bool {
        Self.portRange.contains(values.port)
    }

    private var firstInvalidField: Field? {
        if !isAddressValid { return .address }
        if !isPortValid { return .port }
        return nil
    }

    /// Message for the first invalid field, shown once a save has been attempted.
    var validationMessage: String? {
        guard hasAttemptedSave else { return nil }
        if !isAddressValid { return "Address is required." }
        if !isPortValid { return "Port must be between 1 and 65535." }
        return nil
    }

    /// Loads the form from the given host, or prepares defaults for a new server.
    func configure(host: Host?, store: TransmissionStore) {
        self.host = host

        if let host {
            values = Values(
                name: host.name ?? "",
                address: host.server ?? "",
                port: Int(host.port),
                username: host.username ?? "",
                password: storedPassword(for: host),
                isDefault: host.isDefault,
                isSSL: host.isSSL
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
            password: values.password
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
