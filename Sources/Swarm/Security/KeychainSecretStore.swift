// KeychainSecretStore.swift
// Swarm Framework
//
// Keychain-backed SecretStore for Apple platforms.

import Foundation

#if canImport(Security)
import Security

/// Data-protection class for items written by ``KeychainSecretStore``.
///
/// The `ThisDeviceOnly` variants never migrate to a new device via backups;
/// prefer them for API keys and tokens.
public enum KeychainAccessible: Sendable {
    /// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. Default.
    case whenUnlockedThisDeviceOnly
    /// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
    case afterFirstUnlockThisDeviceOnly
    /// `kSecAttrAccessibleWhenUnlocked`.
    case whenUnlocked
    /// `kSecAttrAccessibleAfterFirstUnlock`.
    case afterFirstUnlock

    var protection: CFString {
        switch self {
        case .whenUnlockedThisDeviceOnly: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        case .afterFirstUnlockThisDeviceOnly: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        case .whenUnlocked: kSecAttrAccessibleWhenUnlocked
        case .afterFirstUnlock: kSecAttrAccessibleAfterFirstUnlock
        }
    }
}

/// A ``SecretStore`` backed by the OS Keychain (Apple platforms only).
///
/// Secrets are stored as generic-password items keyed by
/// `reference.service` / `reference.account`, with the data-protection class
/// from ``KeychainAccessible`` (default
/// `whenUnlockedThisDeviceOnly`) and no iCloud sync.
///
/// ```swift
/// let store = KeychainSecretStore()
/// let reference = SecretReference(service: "com.example.app", account: "openai-api-key")
/// try await store.save(key, for: reference)
/// ```
///
/// On Linux and other platforms without the Security framework this type is
/// unavailable; use ``EnvironmentSecretStore`` or ``InMemorySecretStore``.
public actor KeychainSecretStore: SecretStore {
    private let accessible: KeychainAccessible

    /// Creates a store writing items with the given data-protection class.
    ///
    /// - Parameter accessible: Keychain protection class. Default:
    ///   ``KeychainAccessible/whenUnlockedThisDeviceOnly``.
    public init(accessible: KeychainAccessible = .whenUnlockedThisDeviceOnly) {
        self.accessible = accessible
    }

    /// Loads the secret for `reference`, or `nil` when no item exists.
    public func secret(for reference: SecretReference) throws -> String? {
        let query = Self.lookupQuery(for: reference)

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let secret = String(data: data, encoding: .utf8)
            else {
                throw SecretStoreError.loadFailed("Keychain item for \(reference.service)/\(reference.account) is not UTF-8 text")
            }
            return secret
        case errSecItemNotFound:
            return nil
        default:
            throw SecretStoreError.loadFailed("Keychain lookup failed (OSStatus \(status))")
        }
    }

    /// Saves `secret` under `reference`, replacing any existing item.
    public func save(_ secret: String, for reference: SecretReference) throws {
        guard let data = secret.data(using: .utf8) else {
            throw SecretStoreError.saveFailed("Secret is not UTF-8 encodable")
        }

        let updateStatus = SecItemUpdate(
            Self.updateQuery(for: reference) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            break
        default:
            throw SecretStoreError.saveFailed("Keychain update failed (OSStatus \(updateStatus))")
        }

        let addStatus = SecItemAdd(Self.addQuery(for: reference, data: data, accessible: accessible) as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SecretStoreError.saveFailed("Keychain insert failed (OSStatus \(addStatus))")
        }
    }

    /// Deletes the item for `reference`. A no-op when no item exists.
    public func delete(_ reference: SecretReference) throws {
        let status = SecItemDelete(Self.baseQuery(for: reference) as CFDictionary)
        switch status {
        case errSecSuccess, errSecItemNotFound:
            return
        default:
            throw SecretStoreError.deleteFailed("Keychain delete failed (OSStatus \(status))")
        }
    }

    static func baseQuery(for reference: SecretReference) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: reference.service,
            kSecAttrAccount as String: reference.account,
            kSecAttrSynchronizable as String: false,
        ]
    }

    static func lookupQuery(for reference: SecretReference) -> [String: Any] {
        var query = baseQuery(for: reference)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return query
    }

    static func updateQuery(for reference: SecretReference) -> [String: Any] {
        var query = baseQuery(for: reference)
        query[kSecUseDataProtectionKeychain as String] = true
        return query
    }

    static func addQuery(for reference: SecretReference, data: Data, accessible: KeychainAccessible) -> [String: Any] {
        var query = baseQuery(for: reference)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = accessible.protection
        query[kSecUseDataProtectionKeychain as String] = true
        return query
    }
}
#endif
