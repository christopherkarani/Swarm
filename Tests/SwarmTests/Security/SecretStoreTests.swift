import Foundation
import Testing
@testable import Swarm

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
#if canImport(Security)
import Security
#endif

@Suite("Secret stores")
struct SecretStoreTests {
    private static let reference = SecretReference(
        service: "com.swarm.tests",
        account: "test-api-key"
    )

    @Test("SecretReference round-trips through Codable")
    func referenceCodableRoundTrip() throws {
        let encoded = try JSONEncoder().encode(Self.reference)
        let decoded = try JSONDecoder().decode(SecretReference.self, from: encoded)
        #expect(decoded == Self.reference)
    }

    @Test("InMemorySecretStore saves, loads, overwrites, and deletes")
    func inMemoryRoundTrip() async throws {
        let store = InMemorySecretStore()
        #expect(try await store.secret(for: Self.reference) == nil)
        try await store.save("first-value", for: Self.reference)
        #expect(try await store.secret(for: Self.reference) == "first-value")
        try await store.save("second-value", for: Self.reference)
        #expect(try await store.secret(for: Self.reference) == "second-value")
        try await store.delete(Self.reference)
        #expect(try await store.secret(for: Self.reference) == nil)
        // Deleting an absent secret is a no-op.
        try await store.delete(Self.reference)
        #expect(try await store.secret(for: Self.reference) == nil)
    }

    @Test("EnvironmentSecretStore reads the account-named variable")
    func environmentLoadsAccountVariable() async throws {
        let store = EnvironmentSecretStore(environment: [
            "SWARM_TEST_KEY": "  env-value  ",
            "SWARM_TEST_BLANK": "   ",
        ])
        let hit = SecretReference(service: "ignored", account: "SWARM_TEST_KEY")
        #expect(try await store.secret(for: hit) == "env-value")
        let missing = SecretReference(service: "ignored", account: "SWARM_TEST_ABSENT")
        #expect(try await store.secret(for: missing) == nil)
        let blank = SecretReference(service: "ignored", account: "SWARM_TEST_BLANK")
        #expect(try await store.secret(for: blank) == nil)
    }

    @Test("Saving trims whitespace and rejects empty secrets")
    func saveTrimsAndRejectsEmpty() async throws {
        let store = InMemorySecretStore()
        try await store.save("  padded-value\n", for: Self.reference)
        #expect(try await store.secret(for: Self.reference) == "padded-value")

        do {
            try await store.save("  \n ", for: Self.reference)
            Issue.record("expected SecretStoreError.saveFailed for an empty secret")
        } catch {
            guard case .saveFailed = error as? SecretStoreError else {
                Issue.record("expected saveFailed, got \(error)")
                return
            }
        }
        // The rejected save leaves the previous value untouched.
        #expect(try await store.secret(for: Self.reference) == "padded-value")
    }

    @Test("EnvironmentSecretStore reads the live process environment at request time")
    func environmentReadsLiveProcessEnvironment() async throws {
        let name = "SWARM_TEST_LIVE_\(UUID().uuidString.replacingOccurrences(of: "-", with: "_"))"
        let store = EnvironmentSecretStore()
        let reference = SecretReference(service: "ignored", account: name)
        // Absent when the store is created...
        #expect(try await store.secret(for: reference) == nil)
        // ...visible once exported, without recreating the store.
        setenv(name, "live-value", 1)
        defer { unsetenv(name) }
        #expect(try await store.secret(for: reference) == "live-value")
    }

    @Test("EnvironmentSecretStore is read-only")
    func environmentIsReadOnly() async {
        let store = EnvironmentSecretStore(environment: [:])
        do {
            try await store.save("value", for: Self.reference)
            Issue.record("expected SecretStoreError.readOnly from save")
        } catch {
            #expect(error as? SecretStoreError == .readOnly)
        }
        do {
            try await store.delete(Self.reference)
            Issue.record("expected SecretStoreError.readOnly from delete")
        } catch {
            #expect(error as? SecretStoreError == .readOnly)
        }
    }

    #if canImport(Security)
    @Test("KeychainSecretStore round-trips an isolated item")
    func keychainRoundTrip() async throws {
        // Sandboxed runners (and locked keychains) cannot touch the Keychain
        // at all; skip the live round-trip there and rely on the
        // query-construction test below. Genuine failures still throw.
        guard try await keychainIsAvailable() else { return }

        let store = KeychainSecretStore()
        let reference = SecretReference(
            service: "com.swarm.keychain-tests",
            account: "ephemeral-\(UUID().uuidString)"
        )
        try await store.delete(reference)
        #expect(try await store.secret(for: reference) == nil)
        try await store.save("chain-value", for: reference)
        #expect(try await store.secret(for: reference) == "chain-value")
        // Saving again exercises the update path.
        try await store.save("chain-value-2", for: reference)
        #expect(try await store.secret(for: reference) == "chain-value-2")
        try await store.delete(reference)
        #expect(try await store.secret(for: reference) == nil)
    }

    @Test("Keychain queries target unsynced generic-password items")
    func keychainQueriesAreWellFormed() {
        let reference = SecretReference(service: "com.swarm.tests", account: "query-check")

        let lookup = KeychainSecretStore.lookupQuery(for: reference)
        #expect(lookup[kSecClass as String] as? String == (kSecClassGenericPassword as String))
        #expect(lookup[kSecAttrService as String] as? String == "com.swarm.tests")
        #expect(lookup[kSecAttrAccount as String] as? String == "query-check")
        #expect(lookup[kSecAttrSynchronizable as String] as? Bool == false)
        #expect(lookup[kSecReturnData as String] as? Bool == true)
        #expect((lookup[kSecMatchLimit as String] as? String) == (kSecMatchLimitOne as String))

        let add = KeychainSecretStore.addQuery(
            for: reference,
            data: Data("value".utf8),
            accessible: .whenUnlockedThisDeviceOnly
        )
        #expect(add[kSecValueData as String] as? Data == Data("value".utf8))
        #expect(
            (add[kSecAttrAccessible as String] as? String)
                == (kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        )
        #expect(add[kSecUseDataProtectionKeychain as String] as? Bool == true)

        let update = KeychainSecretStore.updateQuery(for: reference)
        #expect(update[kSecAttrService as String] as? String == "com.swarm.tests")
        #expect(update[kSecUseDataProtectionKeychain as String] as? Bool == true)
    }

    @Test("KeychainAccessible maps to the matching protection constants")
    func keychainAccessibleMapping() {
        #expect(
            KeychainAccessible.whenUnlockedThisDeviceOnly.protection
                == kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        )
        #expect(
            KeychainAccessible.afterFirstUnlockThisDeviceOnly.protection
                == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        )
        #expect(KeychainAccessible.whenUnlocked.protection == kSecAttrAccessibleWhenUnlocked)
        #expect(KeychainAccessible.afterFirstUnlock.protection == kSecAttrAccessibleAfterFirstUnlock)
    }
    #endif
}

#if canImport(Security)

/// Probes whether this process can touch the Keychain.
///
/// Returns `false` only for errors that mean "no keychain access here"
/// (`errSecMissingEntitlement`, `errSecInteractionNotAllowed`); rethrows
/// anything else so genuine bugs still fail.
private func keychainIsAvailable() async throws -> Bool {
    let probe = SecretReference(
        service: "com.swarm.keychain-tests",
        account: "availability-probe-\(UUID().uuidString)"
    )
    let store = KeychainSecretStore()
    do {
        try await store.save("probe", for: probe)
        try await store.delete(probe)
        return true
    } catch {
        guard isKeychainUnavailable(error) else { throw error }
        return false
    }
}

private func isKeychainUnavailable(_ error: Error) -> Bool {
    let reason: String
    switch error as? SecretStoreError {
    case .saveFailed(let message), .loadFailed(let message), .deleteFailed(let message):
        reason = message
    case .readOnly, nil:
        return false
    }
    return reason.contains("\(errSecMissingEntitlement)")
        || reason.contains("\(errSecInteractionNotAllowed)")
}
#endif
