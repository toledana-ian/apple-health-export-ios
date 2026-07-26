import Foundation
import Security

/// Stores per-server auth secrets in the Keychain. Secrets are never written to UserDefaults or logs.
enum KeychainService {
    private static let service = "com.brtkwr.HealthExport.server-secrets"

    enum SecretKind: String {
        case bearer
        case customHeader
    }

    enum KeychainError: Error {
        case unexpectedStatus(OSStatus)
    }

    private static func account(serverID: UUID, kind: SecretKind) -> String {
        "\(serverID.uuidString).\(kind.rawValue)"
    }

    static func saveSecret(_ secret: String, serverID: UUID, kind: SecretKind) throws {
        let data = Data(secret.utf8)
        let account = account(serverID: serverID, kind: kind)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess {
            return
        }
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
            return
        }
        throw KeychainError.unexpectedStatus(status)
    }

    static func loadSecret(serverID: UUID, kind: SecretKind) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(serverID: serverID, kind: kind),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func deleteSecrets(for serverID: UUID) {
        for kind in [SecretKind.bearer, .customHeader] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account(serverID: serverID, kind: kind),
            ]
            SecItemDelete(query as CFDictionary)
        }
    }

    static func secretKind(for auth: AuthMetadata) -> SecretKind? {
        switch auth.type {
        case .none: return nil
        case .bearer: return .bearer
        case .customHeader: return .customHeader
        }
    }
}
