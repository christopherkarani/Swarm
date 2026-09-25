// SecretReference.swift
// Swarm Framework
//
// A portable pointer to a secret held outside process memory.

import Foundation

/// A portable pointer to a secret held outside process memory.
///
/// Store a `SecretReference` in persisted configuration (provider configs,
/// checkpoint metadata) instead of the raw secret. The secret itself lives in
/// a ``SecretStore`` — the OS Keychain via ``KeychainSecretStore`` on Apple
/// platforms, the process environment via ``EnvironmentSecretStore``, or a
/// test double via ``InMemorySecretStore`` — and is resolved only when needed.
///
/// ## Resolution precedence
///
/// Types that accept both an inline secret and a reference (for example
/// ``OpenAICompatibleProviderConfiguration``) always prefer the inline value
/// when it is non-empty, then fall back to the reference:
///
/// ```swift
/// let configuration = OpenAICompatibleProviderConfiguration.openAI(
///     apiKey: "",
///     model: "gpt-4o"
/// )
/// // configuration.apiKeyReference = SecretReference(service: "com.example.app", account: "openai-api-key")
/// ```
///
/// ## Thread safety
///
/// `SecretReference` is a value type and `Sendable`.
public struct SecretReference: Sendable, Codable, Hashable {
    /// Namespaces the secret (Keychain service, store bucket).
    ///
    /// Use a reverse-DNS string owned by your app, for example
    /// `"com.example.app"`.
    public var service: String

    /// Identifies the secret within `service`.
    ///
    /// For ``EnvironmentSecretStore`` this is the environment variable name.
    /// For ``KeychainSecretStore`` this is the Keychain account.
    public var account: String

    /// Creates a reference to a secret held in a ``SecretStore``.
    ///
    /// - Parameters:
    ///   - service: Namespace for the secret (reverse-DNS recommended).
    ///   - account: Identifier within `service`.
    public init(service: String, account: String) {
        self.service = service
        self.account = account
    }
}
