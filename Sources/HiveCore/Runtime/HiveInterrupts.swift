/// Stable identifier for an interrupt.
public struct HiveInterruptID: Hashable, Codable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

/// Interrupt request emitted by a node.
public struct HiveInterruptRequest<Schema: HiveSchema>: Codable, Sendable {
    public let payload: Schema.InterruptPayload

    public init(payload: Schema.InterruptPayload) {
        self.payload = payload
    }
}

/// Selected interrupt value persisted for resume.
public struct HiveInterrupt<Schema: HiveSchema>: Codable, Sendable {
    public let id: HiveInterruptID
    public let payload: Schema.InterruptPayload

    public init(id: HiveInterruptID, payload: Schema.InterruptPayload) {
        self.id = id
        self.payload = payload
    }
}

/// Resume payload delivered to the first step after resume.
public struct HiveResume<Schema: HiveSchema>: Codable, Sendable {
    public let interruptID: HiveInterruptID
    public let payload: Schema.ResumePayload

    public init(interruptID: HiveInterruptID, payload: Schema.ResumePayload) {
        self.interruptID = interruptID
        self.payload = payload
    }
}

/// Interrupted run outcome payload.
public struct HiveInterruption<Schema: HiveSchema>: Codable, Sendable {
    public let interrupt: HiveInterrupt<Schema>
    public let checkpointID: HiveCheckpointID

    public init(interrupt: HiveInterrupt<Schema>, checkpointID: HiveCheckpointID) {
        self.interrupt = interrupt
        self.checkpointID = checkpointID
    }
}
