import CryptoKit
import Foundation

public enum SwarmTranscriptSchemaVersion: String, Codable, Sendable, Equatable {
    case v1 = "STS1"

    public static let current: SwarmTranscriptSchemaVersion = .v1
}

public struct SwarmTranscriptToolCall: Codable, Sendable, Equatable {
    public let id: String?
    public let name: String
    public let arguments: [String: SendableValue]

    public init(id: String?, name: String, arguments: [String: SendableValue]) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

public struct SwarmTranscriptStructuredOutput: Codable, Sendable, Equatable {
    public let result: StructuredOutputResult

    public init(result: StructuredOutputResult) {
        self.result = result
    }
}

public struct SwarmTranscriptEntry: Codable, Sendable, Equatable {
    public let messageID: UUID
    public let role: MemoryMessage.Role
    public let content: String
    public let timestamp: Date
    public let metadata: [String: String]
    public let toolName: String?
    public let toolCallID: String?
    public let toolCalls: [SwarmTranscriptToolCall]
    public let structuredOutput: SwarmTranscriptStructuredOutput?

    public init(
        messageID: UUID,
        role: MemoryMessage.Role,
        content: String,
        timestamp: Date,
        metadata: [String: String] = [:],
        toolName: String? = nil,
        toolCallID: String? = nil,
        toolCalls: [SwarmTranscriptToolCall] = [],
        structuredOutput: SwarmTranscriptStructuredOutput? = nil
    ) {
        self.messageID = messageID
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.metadata = metadata
        self.toolName = toolName
        self.toolCallID = toolCallID
        self.toolCalls = toolCalls
        self.structuredOutput = structuredOutput
    }
}

public enum SwarmTranscriptReplayCompatibilityError: Error, Sendable, Equatable {
    case incompatibleSchemaVersion(expected: SwarmTranscriptSchemaVersion, found: SwarmTranscriptSchemaVersion)
}

public struct SwarmTranscriptDiff: Sendable, Equatable {
    public let entryIndex: Int
    public let keyPath: String
    public let lhs: String
    public let rhs: String

    public init(entryIndex: Int, keyPath: String, lhs: String, rhs: String) {
        self.entryIndex = entryIndex
        self.keyPath = keyPath
        self.lhs = lhs
        self.rhs = rhs
    }
}

public struct SwarmTranscript: Codable, Sendable, Equatable {
    public let schemaVersion: SwarmTranscriptSchemaVersion
    public let entries: [SwarmTranscriptEntry]

    public init(
        schemaVersion: SwarmTranscriptSchemaVersion = .current,
        entries: [SwarmTranscriptEntry]
    ) {
        self.schemaVersion = schemaVersion
        self.entries = entries
    }

    public init(memoryMessages: [MemoryMessage]) {
        self.schemaVersion = .current
        self.entries = memoryMessages.map { SwarmTranscriptCodec.decodeEntry(from: $0) }
    }

    public func validateReplayCompatibility(
        expected: SwarmTranscriptSchemaVersion = .current
    ) throws {
        guard schemaVersion == expected else {
            throw SwarmTranscriptReplayCompatibilityError.incompatibleSchemaVersion(
                expected: expected,
                found: schemaVersion
            )
        }
    }

    public func stableData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public func transcriptHash() throws -> String {
        let digest = SHA256.hash(data: try stableData())
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public func firstDiff(comparedTo other: SwarmTranscript) -> SwarmTranscriptDiff? {
        if schemaVersion != other.schemaVersion {
            return SwarmTranscriptDiff(
                entryIndex: 0,
                keyPath: "schemaVersion",
                lhs: schemaVersion.rawValue,
                rhs: other.schemaVersion.rawValue
            )
        }

        let sharedCount = min(entries.count, other.entries.count)
        for index in 0..<sharedCount {
            if entries[index] != other.entries[index] {
                return SwarmTranscriptDiff(
                    entryIndex: index,
                    keyPath: "entries[\(index)]",
                    lhs: String(describing: entries[index]),
                    rhs: String(describing: other.entries[index])
                )
            }
        }

        guard entries.count != other.entries.count else {
            return nil
        }

        return SwarmTranscriptDiff(
            entryIndex: sharedCount,
            keyPath: "entries.count",
            lhs: String(entries.count),
            rhs: String(other.entries.count)
        )
    }
}

enum SwarmTranscriptCodec {
    static let schemaVersionKey = "swarm.transcript.schema_version"
    static let entryIDKey = "swarm.transcript.entry_id"
    static let toolCallsKey = "swarm.transcript.tool_calls_json"
    static let toolNameKey = "swarm.transcript.tool_name"
    static let toolCallIDKey = "swarm.transcript.tool_call_id"
    static let structuredOutputKey = "swarm.transcript.structured_output_json"

    static func encodeMessage(
        role: MemoryMessage.Role,
        content: String,
        timestamp: Date = Date(),
        messageID: UUID = UUID(),
        metadata: [String: String] = [:],
        toolName: String? = nil,
        toolCallID: String? = nil,
        toolCalls: [InferenceResponse.ParsedToolCall] = [],
        structuredOutput: StructuredOutputResult? = nil
    ) -> MemoryMessage {
        var storedMetadata = metadata
        storedMetadata[schemaVersionKey] = SwarmTranscriptSchemaVersion.current.rawValue
        storedMetadata[entryIDKey] = messageID.uuidString

        if let toolName {
            storedMetadata[toolNameKey] = toolName
        }
        if let toolCallID {
            storedMetadata[toolCallIDKey] = toolCallID
        }
        if !toolCalls.isEmpty,
           let toolCallsJSON = try? encodeToolCalls(toolCalls.map {
               SwarmTranscriptToolCall(id: $0.id, name: $0.name, arguments: $0.arguments)
           })
        {
            storedMetadata[toolCallsKey] = toolCallsJSON
        }
        if let structuredOutput,
           let raw = try? encodeStructuredOutput(SwarmTranscriptStructuredOutput(result: structuredOutput))
        {
            storedMetadata[structuredOutputKey] = raw
        }

        return MemoryMessage(
            id: messageID,
            role: role,
            content: content,
            timestamp: timestamp,
            metadata: storedMetadata
        )
    }

    static func decodeEntry(from message: MemoryMessage) -> SwarmTranscriptEntry {
        let metadata = customMetadata(from: message.metadata)
        return SwarmTranscriptEntry(
            messageID: entryID(from: message),
            role: message.role,
            content: message.content,
            timestamp: message.timestamp,
            metadata: metadata,
            toolName: message.metadata[toolNameKey] ?? message.metadata["tool_name"],
            toolCallID: message.metadata[toolCallIDKey],
            toolCalls: decodeToolCalls(from: message.metadata[toolCallsKey]),
            structuredOutput: decodeStructuredOutput(from: message.metadata[structuredOutputKey])
        )
    }

    static func customMetadata(from metadata: [String: String]) -> [String: String] {
        metadata.filter { key, _ in
            [
                schemaVersionKey,
                entryIDKey,
                toolCallsKey,
                toolNameKey,
                toolCallIDKey,
                structuredOutputKey,
            ].contains(key) == false
        }
    }

    static func entryID(from message: MemoryMessage) -> UUID {
        if let raw = message.metadata[entryIDKey], let entryID = UUID(uuidString: raw) {
            return entryID
        }

        return message.id
    }

    private static func encodeToolCalls(_ toolCalls: [SwarmTranscriptToolCall]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(toolCalls), as: UTF8.self)
    }

    private static func decodeToolCalls(from raw: String?) -> [SwarmTranscriptToolCall] {
        guard let raw, let data = raw.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([SwarmTranscriptToolCall].self, from: data)) ?? []
    }

    private static func encodeStructuredOutput(_ output: SwarmTranscriptStructuredOutput) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(output), as: UTF8.self)
    }

    private static func decodeStructuredOutput(from raw: String?) -> SwarmTranscriptStructuredOutput? {
        guard let raw, let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SwarmTranscriptStructuredOutput.self, from: data)
    }
}
