//
//  KeychainService.swift
//  DOSBTS
//

import Foundation
import Security

enum KeychainService {
    private static let serviceName = "com.dosbts.credentials"

    static func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // Try update first (cheaper than delete-then-add, no race condition)
        let updateQuery = baseQuery(key: key)
        let updateStatus = SecItemUpdate(
            updateQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        if updateStatus == errSecSuccess { return }

        guard updateStatus == errSecItemNotFound else {
            throw keychainError(for: updateStatus)
        }

        // Add new item
        var addQuery = baseQuery(key: key)
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        addQuery[kSecAttrSynchronizable as String] = kCFBooleanFalse

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw keychainError(for: addStatus)
        }
    }

    static func read(key: String) -> String? {
        var query = baseQuery(key: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }

        return String(data: data, encoding: .utf8)
    }

    static func delete(key: String) {
        SecItemDelete(baseQuery(key: key) as CFDictionary)
    }

    private static func baseQuery(key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
        ]
    }

    private static func keychainError(for status: OSStatus) -> KeychainError {
        .operationFailed(status: status)
    }
}

// MARK: - KeychainError

enum KeychainError: LocalizedError {
    case encodingFailed
    case operationFailed(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode value"
        case .operationFailed(let status):
            return "Keychain operation failed (status: \(status))"
        }
    }
}
