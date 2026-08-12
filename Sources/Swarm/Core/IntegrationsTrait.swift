import Foundation
import Logging

/// Build-time availability of Swarm's Integrations SwiftPM trait.
///
/// Lean (default) builds still type-check trait-gated APIs so apps compile, but
/// the backing implementations are not linked. Query ``isEnabled`` — or a
/// per-feature `isAvailable` flag — before constructing those APIs, or rebuild
/// with `--traits Integrations`.
public enum IntegrationsTrait: Sendable {
    /// Whether this process was compiled with the `Integrations` SwiftPM trait.
    public static var isEnabled: Bool {
        #if SWARM_INTEGRATIONS
        true
        #else
        false
        #endif
    }

    /// User-facing message naming the missing trait and the exact rebuild remedy.
    ///
    /// - Parameter feature: Short name of the gated capability (for example, `"Web search"`).
    /// - Returns: A message that names the Integrations trait and how to enable it.
    public static func requirementMessage(for feature: String) -> String {
        "\(feature) requires the Integrations trait. Rebuild with `--traits Integrations`, or add `traits: [\"Integrations\"]` to the Swarm package dependency."
    }

    /// Logs a once-per-process warning when Integrations is missing.
    ///
    /// Call from non-throwing initializers and factories whose signatures cannot
    /// become `throws` without breaking source compatibility on Integrations builds.
    ///
    /// - Parameters:
    ///   - feature: Short name of the gated capability.
    ///   - logger: Logger used for the warning. Defaults to ``Log/agents``.
    public static func warnIfUnavailable(feature: String, logger: Logger = Log.agents) {
        guard !isEnabled else { return }
        let message = requirementMessage(for: feature)
        if OnceRecorder.shared.record(feature: feature, message: message) {
            logger.warning("\(message)")
        }
    }
}

enum IntegrationsTraitTesting {
    static var warnings: [String] {
        OnceRecorder.shared.messages
    }

    static func reset() {
        OnceRecorder.shared.reset()
    }
}

private final class OnceRecorder: @unchecked Sendable {
    static let shared = OnceRecorder()
    private let lock = NSLock()
    private var warnedFeatures: Set<String> = []
    private var recordedMessages: [String] = []

    var messages: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedMessages
    }

    func record(feature: String, message: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard warnedFeatures.insert(feature).inserted else {
            return false
        }
        recordedMessages.append(message)
        return true
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        warnedFeatures.removeAll()
        recordedMessages.removeAll()
    }
}
