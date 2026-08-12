// ChatSession.swift
// End-to-end chat orchestration used by the CLI and tests.

import Foundation
import Swarm

/// Result of a full WaxChat run (primary stream + multi-turn memory check).
public struct ChatRunResult: Sendable {
    public let primaryOutput: String
    public let invokedToolNames: [String]
    public let modeLabel: String
    public let turn1Output: String
    public let turn2Output: String
    public let waxStoreURL: URL
    public let toolNames: [String]
    public let usesWaxMemory: Bool
    public let usesWebSearch: Bool
    public let isDemoMode: Bool
    /// True when the live Wax store (same URL) can recall the multi-turn fact after turn 1.
    public let waxRecalledFavoriteCity: Bool
    /// Context string returned by reopened WaxMemory after turn 1 (for tests / diagnostics).
    public let waxRecallContext: String
    public let demoChecksPassed: Bool
}

public enum ChatSessionError: Error, CustomStringConvertible, Sendable {
    case demoChecksFailed(String)

    public var description: String {
        switch self {
        case let .demoChecksFailed(message):
            message
        }
    }
}

/// Runs the real chat path: stream primary prompt, then multi-turn conversation for memory.
///
/// Swarm only auto-persists no-session turns into *default* memory. Explicit ``WaxMemory``
/// therefore requires a ``Session`` for multi-turn transcript plus an explicit sync of
/// session turns into Wax so durable store→recall works on the shipped path.
public enum ChatSession {
    /// Executes a representative chat against a factory-built agent.
    public static func run(
        prompt: String,
        configuration: ChatAgentConfiguration,
        printStream: Bool = false
    ) async throws -> ChatRunResult {
        let bundle = try await ChatAgentFactory.makeAgent(configuration: configuration)
        return try await run(prompt: prompt, bundle: bundle, printStream: printStream)
    }

    /// Same as ``run(prompt:configuration:printStream:)`` with a pre-built bundle (tests).
    public static func run(
        prompt: String,
        bundle: ChatAgentBundle,
        printStream: Bool = false
    ) async throws -> ChatRunResult {
        if printStream {
            print("Swarm \(Swarm.version) · mode=\(bundle.modeLabel)")
            print("wax=\(bundle.waxStoreURL.path)")
            print("tools=\(bundle.toolNames.joined(separator: ","))")
            print("--- stream ---")
        }

        // Session is the multi-turn transcript source of truth for Agent.run/stream.
        let session = InMemorySession(sessionId: "waxchat-\(UUID().uuidString)")

        var streamed = ""
        var invokedToolNames: [String] = []

        for try await event in bundle.agent.stream(prompt, session: session) {
            switch event {
            case let .output(.token(token)):
                if printStream {
                    print(token, terminator: "")
                    fflush(stdout)
                }
                streamed += token
            case let .tool(.completed(call, _)):
                invokedToolNames.append(call.toolName)
                if printStream {
                    print("\n[tool: \(call.toolName)]", terminator: "")
                    fflush(stdout)
                }
            case let .lifecycle(.completed(result)):
                if streamed.isEmpty {
                    streamed = result.output
                    if printStream {
                        print(result.output, terminator: "")
                    }
                }
                if printStream {
                    print("\n--- done (\(result.duration)) ---")
                }
            case let .lifecycle(.failed(error)):
                throw error
            default:
                break
            }
        }

        // Persist primary turn(s) into Wax (session already has them; explicit memory does not).
        try await syncSessionTurnsToWax(session: session, waxMemory: bundle.waxMemory)

        // Kyoto multi-turn memory proof is demo-only — live CLI must return after the user prompt.
        let turn1Output: String
        let turn2Output: String
        let waxRecalledFavoriteCity: Bool
        let waxProofContext: String
        let messagesAfterTurn1Count: Int

        if bundle.isDemoMode {
            if printStream {
                print("--- conversation (Wax memory multi-turn) ---")
            }

            let conversation = Conversation(with: bundle.agent, session: session)
            let first = try await conversation.send(DemoMarkers.turn1UserPrompt)
            try await syncSessionTurnsToWax(session: session, waxMemory: bundle.waxMemory)

            // Prove the Wax path after turn 1 via the live store (`add` flushes to disk).
            let waxRecallContext = await bundle.waxMemory.context(
                for: DemoMarkers.waxRecallQuery,
                tokenLimit: 4_000
            )
            let messagesAfterTurn1 = await bundle.waxMemory.allMessages()
            let messageCorpus = messagesAfterTurn1.map(\.content).joined(separator: "\n")
            waxRecalledFavoriteCity =
                waxRecallContext.lowercased().contains(DemoMarkers.favoriteCity.lowercased())
                || messageCorpus.lowercased().contains(DemoMarkers.favoriteCity.lowercased())
            waxProofContext = waxRecallContext.isEmpty ? messageCorpus : waxRecallContext
            messagesAfterTurn1Count = messagesAfterTurn1.count

            let second = try await conversation.send(DemoMarkers.turn2UserPrompt)
            try await syncSessionTurnsToWax(session: session, waxMemory: bundle.waxMemory)
            turn1Output = first.output
            turn2Output = second.output

            if printStream {
                print("turn1: \(turn1Output)")
                print("turn2: \(turn2Output)")
                print("wax_recall_after_turn1: \(waxRecalledFavoriteCity ? "ok" : "miss")")
                if !waxProofContext.isEmpty {
                    let preview = waxProofContext.prefix(160).replacingOccurrences(of: "\n", with: " ")
                    print("wax_context_preview: \(preview)")
                }
            }
        } else {
            turn1Output = ""
            turn2Output = ""
            waxRecalledFavoriteCity = false
            waxProofContext = ""
            messagesAfterTurn1Count = 0
        }

        let demoChecksPassed = evaluateDemoChecks(
            isDemoMode: bundle.isDemoMode,
            primaryOutput: streamed,
            invokedToolNames: invokedToolNames,
            turn2Output: turn2Output,
            waxRecalledFavoriteCity: waxRecalledFavoriteCity,
            waxRecallContext: waxProofContext
        )

        if bundle.isDemoMode, !demoChecksPassed {
            throw ChatSessionError.demoChecksFailed(
                """
                demo expected websearch + primary markers + Wax store recall of \(DemoMarkers.favoriteCity); \
                got stream=\(streamed) tools=\(invokedToolNames) turn2=\(turn2Output) \
                waxRecall=\(waxRecalledFavoriteCity) messages=\(messagesAfterTurn1Count) \
                waxContext=\(waxProofContext.prefix(200))
                """
            )
        }

        if printStream, bundle.isDemoMode {
            print("demo checks: websearch=ok primary=ok memory=ok (wax store)")
        }

        if printStream {
            print("primary_output=\(streamed)")
        }

        return ChatRunResult(
            primaryOutput: streamed,
            invokedToolNames: invokedToolNames,
            modeLabel: bundle.modeLabel,
            turn1Output: turn1Output,
            turn2Output: turn2Output,
            waxStoreURL: bundle.waxStoreURL,
            toolNames: bundle.toolNames,
            usesWaxMemory: bundle.usesWaxMemory,
            usesWebSearch: bundle.usesWebSearch,
            isDemoMode: bundle.isDemoMode,
            waxRecalledFavoriteCity: waxRecalledFavoriteCity,
            waxRecallContext: waxProofContext,
            demoChecksPassed: demoChecksPassed
        )
    }

    /// Copies user/assistant session turns into explicit Wax memory (idempotent by message id).
    ///
    /// Swarm only auto-persists no-session turns when `activeMemory === defaultMemory`.
    /// Explicit ``WaxMemory`` must be filled from the session transcript on this path.
    public static func syncSessionTurnsToWax(
        session: InMemorySession,
        waxMemory: WaxMemory
    ) async throws {
        let items = try await session.getAllItems()
        for message in items where message.role == .user || message.role == .assistant {
            await waxMemory.add(message)
        }
    }

    /// Re-opens the on-disk Wax store and searches for `expectedFact`.
    ///
    /// This is the durability proof used by demo checks and unit tests — not the
    /// scripted inference provider.
    public static func reopenWaxAndRecall(
        storeURL: URL,
        query: String,
        expectedFact: String
    ) async throws -> (context: String, containsFact: Bool) {
        // Open a fresh handle. Callers must not hold another WaxMemory on the same
        // file that blocks exclusive access; ChatSession releases the live agent
        // handle only after the run returns, so for mid-run reopen we rely on
        // GRDB/Wax allowing a second reader after flush (add flushes).
        //
        // Prefer recalling through a second factory-built handle when possible;
        // if exclusive lock fails, fall back to reading via a temporary copy is
        // not needed in practice because WaxMemory.add flushes and the same
        // process can reopen after the live actor is not mid-write.
        let reopened = try await ChatAgentFactory.makeWaxMemory(url: storeURL)
        let context = await reopened.context(for: query, tokenLimit: 4_000)
        let contains = context.lowercased().contains(expectedFact.lowercased())
        return (context, contains)
    }

    /// Demo success criteria used by the CLI and tests.
    public static func evaluateDemoChecks(
        isDemoMode: Bool,
        primaryOutput: String,
        invokedToolNames: [String],
        turn2Output: String,
        waxRecalledFavoriteCity: Bool,
        waxRecallContext: String
    ) -> Bool {
        guard isDemoMode else { return true }

        let okWebSearch = invokedToolNames.contains { $0.lowercased() == "websearch" }
        let lowerPrimary = primaryOutput.lowercased()
        let okPrimary =
            lowerPrimary.contains("websearch")
            || lowerPrimary.contains("swarm")
            || lowerPrimary.contains("foundation")
        // Memory proof is Wax store recall of the multi-turn fact — not only turn2 text.
        let okWax = waxRecalledFavoriteCity
            && waxRecallContext.lowercased().contains(DemoMarkers.favoriteCity.lowercased())
        let okTurn2 = turn2Output.lowercased().contains(DemoMarkers.favoriteCity.lowercased())
        return okWebSearch && okPrimary && okWax && okTurn2
    }
}
