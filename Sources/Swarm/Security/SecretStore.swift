// SecretStore.swift
// Swarm Framework
//
// Abstraction over secret backends (Keychain, environment, in-memory).

import Foundation

/// Errors thrown by ``SecretStore`` backends.
///
/// The associated strings describe the failing operation. They never contain
/// the secret value itself.
public enum SecretStoreError: Error, Sendable, Equatable {
    /// The backend is read-only (``EnvironmentSecretStore``).
    case readOnly
    /// Saving the secret failed. The payload is a backend-provided reason.
    case saveFailed(String)
    /// Loading the secret failed. The payload is a backend-provided reason.
    case loadFailed(String)
    /// Deleting the secret failed. The payload is a backend-provided reason.
    case deleteFailed(String)
}

/// A backend that holds secrets outside persisted configuration.
///
/// Use ``KeychainSecretStore`` on Apple platforms, ``EnvironmentSecretStore``
/// for twelve-factor deployments and CI, and ``InMemorySecretStore`` for
/// tests and previews.
///
/// ```swift
/// let store = InMemorySecretStore()
/// let reference = SecretReference(service: "com.example.app", account: "openai-api-key")
/// try await store.save("sk-live", for: reference)
/// let key = try await store.secret(for: reference)
/// ```
public protocol SecretStore: Sendable {
    /// Loads the secret for `reference`, or `nil` when no secret is stored.
    ///
    /// - Parameter reference: Pointer to the secret.
    /// - Returns: The stored secret, or `nil` when absent.
    func secret(for reference: SecretReference) async throws -> String?

    /// Saves `secret` under `reference`, replacing any existing value.
    ///
    /// - Parameters:
    ///   - secret: The secret value. Must not be empty.
    ///   - reference: Pointer the secret is stored under.
    func save(_ secret: String, for reference: SecretReference) async throws

    /// Deletes any secret stored under `reference`. Deleting an absent
    /// secret is a no-op.
    ///
    /// - Parameter reference: Pointer to the secret.
    func delete(_ reference: SecretReference) async throws
}

/// An in-memory ``SecretStore`` for tests, previews, and ephemeral runs.
///
/// Values live in process memory only and are dropped with the store. Never
/// use for production secrets — prefer ``KeychainSecretStore``.
public actor InMemorySecretStore: SecretStore {
    private var secrets: [SecretReference: String]

    /// Creates an empty store.
    public init() {
        secrets = [:]
    }

    /// Creates a store preloaded with `secrets`.
    ///
    /// - Parameter secrets: Initial reference-to-value mapping.
    public init(secrets: [SecretReference: String]) {
        self.secrets = secrets
    }

    /// Loads the secret for `reference`, or `nil` when absent.
    public func secret(for reference: SecretReference) -> String? {
        secrets[reference]
    }

    /// Saves `secret` under `reference`.
    public func save(_ secret: String, for reference: SecretReference) {
        secrets[reference] = secret
    }

    /// Deletes any secret stored under `reference`.
    public func delete(_ reference: SecretReference) {
        secrets.removeValue(forKey: reference)
    }
}

/// A read-only ``SecretStore`` backed by process environment variables.
///
/// `secret(for:)` reads the variable named by `reference.account`;
/// `service` is ignored. `save` and `delete` throw
/// ``SecretStoreError/readOnly``.
///
/// ```swift
/// // Reads $OPENAI_API_KEY at request time.
/// let reference = SecretReference(service: "com.example.app", account: "OPENAI_API_KEY")
/// let key = try await EnvironmentSecretStore().secret(for: reference)
/// ```
public struct EnvironmentSecretStore: SecretStore, Sendable {
    private let environment: [String: String]

    /// Creates a store reading `environment`.
    ///
    /// - Parameter environment: Variable mapping. Defaults to the live
    ///   process environment. Inject a dictionary in tests.
    public init(environment: [String: String]? = nil) {
        self.environment = environment ?? ProcessInfo.processInfo.environment
    }

    /// Reads the variable named by `reference.account`.
    public func secret(for reference: SecretReference) -> String? {
        let value = environment[reference.account]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    /// Always throws ``SecretStoreError/readOnly``.
    public func save(_: String, for _: SecretReference) throws {
        throw SecretStoreError.readOnly
    }

    /// Always throws ``SecretStoreError/readOnly``.
    public func delete(_: SecretReference) throws {
        throw SecretStoreError.readOnly
    }
}
