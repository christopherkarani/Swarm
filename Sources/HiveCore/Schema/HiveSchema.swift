/// Defines the channels and input mapping for a Hive graph.
public protocol HiveSchema: Sendable {
    associatedtype Context: Sendable = Void
    associatedtype Input: Sendable = Void
    associatedtype InterruptPayload: Codable & Sendable = String
    associatedtype ResumePayload: Codable & Sendable = String

    static var channelSpecs: [AnyHiveChannelSpec<Self>] { get }

    /// Converts a typed run input into synthetic writes applied before step 0.
    static func inputWrites(_ input: Input, inputContext: HiveInputContext) throws -> [AnyHiveWrite<Self>]
}

public extension HiveSchema where Input == Void {
    static func inputWrites(_ input: Void, inputContext: HiveInputContext) throws -> [AnyHiveWrite<Self>] { [] }
}
