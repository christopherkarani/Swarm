// PersistedMessage.swift
// Swarm Framework
//
// SwiftData model for persistent message storage.

#if canImport(SwiftData)
    import Foundation
    import Logging
    import SwiftData

    /// SwiftData model for persistent message storage.
    ///
    /// `PersistedMessage` is the database representation of `MemoryMessage`,
    /// enabling long-term storage across app launches.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let container = try ModelContainer(for: PersistedMessage.self)
    /// let context = ModelContext(container)
    ///
    /// let message = MemoryMessage.user("Hello")
    /// let persisted = PersistedMessage(from: message, conversationId: "chat-123")
    /// context.insert(persisted)
    /// try context.save()
    /// ```
    @Model
    final class PersistedMessage {
        /// Unique identifier matching the original MemoryMessage.
        @Attribute(.unique) var id: UUID

        /// Message role as string (user, assistant, system, tool).
        var role: String

        /// Message content.
        var content: String

        /// Creation timestamp.
        var timestamp: Date

        /// Serialized metadata as JSON string.
        var metadataJSON: String

        /// Conversation/session identifier for grouping messages.
        var conversationId: String

        /// Creates a new persisted message.
        init(
            id: UUID = UUID(),
            role: String,
            content: String,
            timestamp: Date = Date(),
            metadataJSON: String = "{}",
            conversationId: String = "default"
        ) {
            self.id = id
            self.role = role
            self.content = content
            self.timestamp = timestamp
            self.metadataJSON = metadataJSON
            self.conversationId = conversationId
        }

        /// Creates a persisted message from a MemoryMessage.
        convenience init(from message: MemoryMessage, conversationId: String = "default") {
            let metadataJSON: String = if let data = try? JSONEncoder().encode(message.metadata),
                                          let json = String(data: data, encoding: .utf8) {
                json
            } else {
                "{}"
            }

            self.init(
                id: message.id,
                role: message.role.rawValue,
                content: message.content,
                timestamp: message.timestamp,
                metadataJSON: metadataJSON,
                conversationId: conversationId
            )
        }

        /// Converts back to a MemoryMessage.
        func toMemoryMessage() -> MemoryMessage? {
            guard let messageRole = MemoryMessage.Role(rawValue: role) else {
                Log.memory.warning(
                    "Failed to deserialize PersistedMessage: invalid role '\(role)' for message id: \(id)"
                )
                return nil
            }

            let metadata: [String: String]
            if let data = metadataJSON.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
                metadata = decoded
            } else {
                if !metadataJSON.isEmpty, metadataJSON != "{}" {
                    Log.memory.warning(
                        "Failed to deserialize metadata for message \(id), using empty metadata. JSON: \(metadataJSON.prefix(100))"
                    )
                }
                metadata = [:]
            }

            return MemoryMessage(
                id: id,
                role: messageRole,
                content: content,
                timestamp: timestamp,
                metadata: metadata
            )
        }
    }

    // MARK: - Fetch Descriptors

    extension PersistedMessage {
        /// Fetch descriptor for all conversations (unique conversation IDs).
        static var allConversationsDescriptor: FetchDescriptor<PersistedMessage> {
            FetchDescriptor<PersistedMessage>(
                sortBy: [SortDescriptor(\.conversationId)]
            )
        }

        /// Fetch descriptor for all messages in a conversation, sorted by timestamp.
        static func fetchDescriptor(
            forConversation conversationId: String
        ) -> FetchDescriptor<PersistedMessage> {
            FetchDescriptor<PersistedMessage>(
                predicate: #Predicate { $0.conversationId == conversationId },
                sortBy: [SortDescriptor(\.timestamp, order: .forward)]
            )
        }

        /// Fetch descriptor for recent messages in a conversation.
        static func fetchDescriptor(
            forConversation conversationId: String,
            limit: Int
        ) -> FetchDescriptor<PersistedMessage> {
            var descriptor = FetchDescriptor<PersistedMessage>(
                predicate: #Predicate { $0.conversationId == conversationId },
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            descriptor.fetchLimit = limit
            return descriptor
        }
    }

    // MARK: - Versioned Schema

    /// First shipped SwiftData schema for Swarm memory.
    ///
    /// Existing stores created with `Schema([PersistedMessage.self])` before
    /// versioning share this model shape. Future schema changes must add a new
    /// `VersionedSchema` and a ``MemoryMigrationPlan`` stage.
    @available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
    enum MemorySchemaV1: VersionedSchema {
        static let versionIdentifier = Schema.Version(1, 0, 0)

        static var models: [any PersistentModel.Type] {
            [PersistedMessage.self]
        }
    }

    /// Migration plan for SwiftData memory stores.
    ///
    /// Current schema is ``MemorySchemaV1``. Stages are empty until a v2
    /// model change ships.
    @available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
    enum MemoryMigrationPlan: SchemaMigrationPlan {
        static var schemas: [any VersionedSchema.Type] {
            [MemorySchemaV1.self]
        }

        static var stages: [MigrationStage] {
            []
        }
    }

    // MARK: - Model Container Configuration

    extension PersistedMessage {
        /// Creates a model container configured for PersistedMessage.
        ///
        /// Uses ``MemorySchemaV1`` with ``MemoryMigrationPlan`` so existing
        /// v1 stores continue to open after future schema additions.
        static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
            let schema = Schema(versionedSchema: MemorySchemaV1.self)
            let configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: inMemory
            )
            return try ModelContainer(
                for: schema,
                migrationPlan: MemoryMigrationPlan.self,
                configurations: [configuration]
            )
        }

        /// Creates a v1-only container without a migration plan.
        ///
        /// Used by tests to seed a store that must then reopen through
        /// ``MemoryMigrationPlan``.
        static func makeV1Container(url: URL) throws -> ModelContainer {
            let schema = Schema(versionedSchema: MemorySchemaV1.self)
            let configuration = ModelConfiguration(schema: schema, url: url)
            return try ModelContainer(for: schema, configurations: [configuration])
        }

        /// Reopens a store with the current migration plan.
        static func makeMigratedContainer(url: URL) throws -> ModelContainer {
            let schema = Schema(versionedSchema: MemorySchemaV1.self)
            let configuration = ModelConfiguration(schema: schema, url: url)
            return try ModelContainer(
                for: schema,
                migrationPlan: MemoryMigrationPlan.self,
                configurations: [configuration]
            )
        }
    }
#endif
