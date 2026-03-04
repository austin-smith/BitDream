import Foundation
import Security

enum KeychainPasswordStore {
    private static let service = "crapshack.BitDream"

    static func readPassword(for host: Host) -> String {
        readPassword(credentialKey: host.ensureCredentialKey())
    }

    @discardableResult
    static func savePassword(_ password: String, for host: Host) -> Bool {
        savePassword(password, credentialKey: host.ensureCredentialKey())
    }

    @discardableResult
    static func deletePassword(for host: Host) -> Bool {
        deletePassword(credentialKey: host.ensureCredentialKey())
    }

    static func readPassword(credentialKey: String) -> String {
        guard let password = readPassword(account: accountForCredentialKey(credentialKey)) else {
            return ""
        }

        return password
    }

    @discardableResult
    static func savePassword(_ password: String, credentialKey: String) -> Bool {
        upsertPassword(password, account: accountForCredentialKey(credentialKey))
    }

    @discardableResult
    static func deletePassword(credentialKey: String) -> Bool {
        deletePassword(account: accountForCredentialKey(credentialKey))
    }

    static func credentialKeyIfPresent(for host: Host) -> String? {
        guard let key = host.credentialKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            return nil
        }
        return key
    }

    private static func accountForCredentialKey(_ credentialKey: String) -> String {
        "host:\(credentialKey.trimmingCharacters(in: .whitespacesAndNewlines))"
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
