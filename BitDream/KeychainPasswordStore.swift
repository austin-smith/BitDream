import Foundation
import Security
import CoreData

enum KeychainPasswordStore {
    private static let service = "crapshack.BitDream"

    static func readPassword(for host: Host) -> String {
        let primaryAccount = accountForPrimaryCredential(for: host)

        if let password = readPassword(account: primaryAccount) {
            return password
        }

        // TODO(remove-legacy-keychain): Delete this fallback after the legacy name/server-based
        // credential migration window has passed and all supported installs are on credentialKey.
        let legacyAccounts = legacyAccounts(for: host)
        for legacyAccount in legacyAccounts {
            guard let legacyPassword = readPassword(account: legacyAccount) else { continue }

            if upsertPassword(legacyPassword, account: primaryAccount) {
                _ = deletePassword(account: legacyAccount)
            }

            return legacyPassword
        }

        return ""
    }

    static func savePassword(_ password: String, for host: Host, previousLegacyName: String? = nil) {
        let primaryAccount = accountForPrimaryCredential(for: host)
        _ = upsertPassword(password, account: primaryAccount)

        // TODO(remove-legacy-keychain): Remove legacy-account cleanup once all users are migrated.
        var accountsToDelete = Set(legacyAccounts(for: host))
        if let previousLegacyName {
            let trimmed = previousLegacyName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                accountsToDelete.insert(trimmed)
            }
        }

        for account in accountsToDelete {
            _ = deletePassword(account: account)
        }
    }

    static func deletePassword(for host: Host, legacyNames: [String] = []) {
        let primaryAccount = accountForPrimaryCredential(for: host)
        _ = deletePassword(account: primaryAccount)

        // TODO(remove-legacy-keychain): Remove legacy-name deletes after migration cleanup sunset.
        var accountsToDelete = Set(legacyAccounts(for: host))
        for legacyName in legacyNames {
            let trimmed = legacyName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                accountsToDelete.insert(trimmed)
            }
        }

        for account in accountsToDelete {
            _ = deletePassword(account: account)
        }
    }

    private static func accountForPrimaryCredential(for host: Host) -> String {
        "host:\(ensureCredentialKey(for: host))"
    }

    private static func legacyAccounts(for host: Host) -> [String] {
        var accounts: [String] = []
        appendUniqueAccount(host.name, to: &accounts)
        appendUniqueAccount(host.server, to: &accounts)
        return accounts
    }

    private static func appendUniqueAccount(_ candidate: String?, to accounts: inout [String]) {
        guard let candidate else { return }

        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if !accounts.contains(trimmed) {
            accounts.append(trimmed)
        }
    }

    private static func baseQuery(account: String) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]

        #if os(macOS)
        query[kSecUseDataProtectionKeychain] = true
        #endif

        return query
    }

    private static func readPassword(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData] = kCFBooleanTrue
        query[kSecMatchLimit] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                logKeychainError(status: errSecInternalComponent, operation: "decode")
                return nil
            }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            logKeychainError(status: status, operation: "read")
            return nil
        }
    }

    @discardableResult
    private static func upsertPassword(_ password: String, account: String) -> Bool {
        guard let data = password.data(using: .utf8) else {
            print("KeychainPasswordStore: Unable to encode password data.")
            return false
        }

        var addQuery = baseQuery(account: account)
        addQuery[kSecValueData] = data
        addQuery[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return true
        }

        if addStatus == errSecDuplicateItem {
            let query = baseQuery(account: account)
            let updates: [CFString: Any] = [
                kSecValueData: data
            ]
            let updateStatus = SecItemUpdate(query as CFDictionary, updates as CFDictionary)
            if updateStatus == errSecSuccess {
                return true
            }

            logKeychainError(status: updateStatus, operation: "update")
            return false
        }

        logKeychainError(status: addStatus, operation: "add")
        return false
    }

    @discardableResult
    private static func deletePassword(account: String) -> Bool {
        let query = baseQuery(account: account)
        let status = SecItemDelete(query as CFDictionary)

        if status == errSecSuccess || status == errSecItemNotFound {
            return true
        }

        logKeychainError(status: status, operation: "delete")
        return false
    }

    private static func logKeychainError(status: OSStatus, operation: String) {
        if status == errSecSuccess || status == errSecItemNotFound {
            return
        }

        let message = (SecCopyErrorMessageString(status, nil) as String?) ?? "Unknown error"
        print("KeychainPasswordStore \(operation) failed (\(status)): \(message)")
    }
}
