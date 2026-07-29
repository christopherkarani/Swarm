import Foundation

public struct HiveRunEvent: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case started(threadID: HiveThreadID)
        case finished
        case interrupted(interruptID: HiveInterruptID)
        case resumed(interruptID: HiveInterruptID)
        case cancelled(cause: HiveRunCancellationCause)
    }

    public let id: HiveEventID
    public let metadata: [String: String]
    public let kind: Kind
}

public struct HiveStepEvent: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case started(stepIndex: Int, frontierCount: Int)
        case finished(stepIndex: Int, nextFrontierCount: Int)
    }

    public let id: HiveEventID
    public let metadata: [String: String]
    public let kind: Kind
}

public struct HiveTaskEvent: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case started(node: HiveNodeID, taskID: HiveTaskID)
        case finished(node: HiveNodeID, taskID: HiveTaskID)
        case failed(node: HiveNodeID, taskID: HiveTaskID, errorDescription: String)
    }

    public let id: HiveEventID
    public let metadata: [String: String]
    public let kind: Kind
}

public struct HiveWriteEvent: Sendable, Equatable {
    public let id: HiveEventID
    public let metadata: [String: String]
    public let channelID: HiveChannelID
    public let payloadHash: String
}

public struct HiveCheckpointEvent: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case saved(checkpointID: HiveCheckpointID)
        case loaded(checkpointID: HiveCheckpointID)
    }

    public let id: HiveEventID
    public let metadata: [String: String]
    public let kind: Kind
}

public struct HiveDebugEvent: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case streamBackpressure(droppedDebugEvents: Int)
        case customDebug(name: String)
    }

    public let id: HiveEventID
    public let metadata: [String: String]
    public let kind: Kind
}

public struct HiveEventStreamViews: Sendable {
    private let hub: HiveEventStreamViewsHub

    public init(_ source: AsyncThrowingStream<HiveEvent, Error>) {
        self.hub = HiveEventStreamViewsHub(source: source)
    }

    public func runs() -> AsyncThrowingStream<HiveRunEvent, Error> {
        makeViewStream { event in
            switch event.kind {
            case .runStarted(let threadID):
                return HiveRunEvent(id: event.id, metadata: event.metadata, kind: .started(threadID: threadID))
            case .runFinished:
                return HiveRunEvent(id: event.id, metadata: event.metadata, kind: .finished)
            case .runInterrupted(let interruptID):
                return HiveRunEvent(id: event.id, metadata: event.metadata, kind: .interrupted(interruptID: interruptID))
            case .runResumed(let interruptID):
                return HiveRunEvent(id: event.id, metadata: event.metadata, kind: .resumed(interruptID: interruptID))
            case .runCancelled(let cause):
                return HiveRunEvent(id: event.id, metadata: event.metadata, kind: .cancelled(cause: cause))
            default:
                return nil
            }
        }
    }

    public func steps() -> AsyncThrowingStream<HiveStepEvent, Error> {
        makeViewStream { event in
            switch event.kind {
            case .stepStarted(let stepIndex, let frontierCount):
                return HiveStepEvent(
                    id: event.id,
                    metadata: event.metadata,
                    kind: .started(stepIndex: stepIndex, frontierCount: frontierCount)
                )
            case .stepFinished(let stepIndex, let nextFrontierCount):
                return HiveStepEvent(
                    id: event.id,
                    metadata: event.metadata,
                    kind: .finished(stepIndex: stepIndex, nextFrontierCount: nextFrontierCount)
                )
            default:
                return nil
            }
        }
    }

    public func tasks() -> AsyncThrowingStream<HiveTaskEvent, Error> {
        makeViewStream { event in
            switch event.kind {
            case .taskStarted(let node, let taskID):
                return HiveTaskEvent(id: event.id, metadata: event.metadata, kind: .started(node: node, taskID: taskID))
            case .taskFinished(let node, let taskID):
                return HiveTaskEvent(id: event.id, metadata: event.metadata, kind: .finished(node: node, taskID: taskID))
            case .taskFailed(let node, let taskID, let errorDescription):
                return HiveTaskEvent(
                    id: event.id,
                    metadata: event.metadata,
                    kind: .failed(node: node, taskID: taskID, errorDescription: errorDescription)
                )
            default:
                return nil
            }
        }
    }

    public func writes() -> AsyncThrowingStream<HiveWriteEvent, Error> {
        makeViewStream { event in
            guard case .writeApplied(let channelID, let payloadHash) = event.kind else { return nil }
            return HiveWriteEvent(id: event.id, metadata: event.metadata, channelID: channelID, payloadHash: payloadHash)
        }
    }

    public func checkpoints() -> AsyncThrowingStream<HiveCheckpointEvent, Error> {
        makeViewStream { event in
            switch event.kind {
            case .checkpointSaved(let checkpointID):
                return HiveCheckpointEvent(id: event.id, metadata: event.metadata, kind: .saved(checkpointID: checkpointID))
            case .checkpointLoaded(let checkpointID):
                return HiveCheckpointEvent(id: event.id, metadata: event.metadata, kind: .loaded(checkpointID: checkpointID))
            default:
                return nil
            }
        }
    }

    public func debug() -> AsyncThrowingStream<HiveDebugEvent, Error> {
        makeViewStream { event in
            switch event.kind {
            case .streamBackpressure(let droppedDebugEvents):
                return HiveDebugEvent(
                    id: event.id,
                    metadata: event.metadata,
                    kind: .streamBackpressure(droppedDebugEvents: droppedDebugEvents)
                )
            case .customDebug(let name):
                return HiveDebugEvent(id: event.id, metadata: event.metadata, kind: .customDebug(name: name))
            default:
                return nil
            }
        }
    }

    private func makeViewStream<T: Sendable>(
        _ transform: @escaping @Sendable (HiveEvent) -> T?
    ) -> AsyncThrowingStream<T, Error> {
        AsyncThrowingStream { continuation in
            let id = UUID()
            Task {
                await hub.addSubscriber(
                    id: id,
                    onEvent: { event in
                        if let mapped = transform(event) {
                            continuation.yield(mapped)
                        }
                    },
                    onFinish: { result in
                        switch result {
                        case .success:
                            continuation.finish()
                        case .failure(let error):
                            continuation.finish(throwing: error)
                        }
                    }
                )
            }
            continuation.onTermination = { _ in
                Task { await hub.removeSubscriber(id: id) }
            }
        }
    }
}

actor HiveEventStreamViewsHub {
    private struct Subscriber {
        let onEvent: (HiveEvent) -> Void
        let onFinish: (Result<Void, Error>) -> Void
    }

    private let source: AsyncThrowingStream<HiveEvent, Error>
    private var subscribers: [UUID: Subscriber] = [:]
    private var pumpTask: Task<Void, Never>?
    private var finished: Result<Void, Error>?

    init(source: AsyncThrowingStream<HiveEvent, Error>) {
        self.source = source
    }

    deinit {
        pumpTask?.cancel()
    }

    func addSubscriber(
        id: UUID,
        onEvent: @escaping (HiveEvent) -> Void,
        onFinish: @escaping (Result<Void, Error>) -> Void
    ) {
        if let finished {
            onFinish(finished)
            return
        }

        subscribers[id] = Subscriber(onEvent: onEvent, onFinish: onFinish)
        startPumpIfNeeded()
    }

    func removeSubscriber(id: UUID) {
        subscribers.removeValue(forKey: id)
    }

    private func startPumpIfNeeded() {
        guard pumpTask == nil else { return }
        pumpTask = Task(priority: .userInitiated) { [weak self, source] in
            do {
                for try await event in source {
                    guard let self else { return }
                    await self.broadcast(event)
                }
                guard let self else { return }
                await self.finishAll(.success(()))
            } catch is CancellationError {
                guard let self else { return }
                await self.clearPumpTask()
            } catch {
                guard let self else { return }
                await self.finishAll(.failure(error))
            }
        }
    }

    private func clearPumpTask() {
        pumpTask = nil
    }

    private func broadcast(_ event: HiveEvent) {
        for subscriber in subscribers.values {
            subscriber.onEvent(event)
        }
    }

    private func finishAll(_ result: Result<Void, Error>) {
        finished = result
        let current = subscribers.values
        subscribers.removeAll()
        pumpTask = nil

        for subscriber in current {
            subscriber.onFinish(result)
        }
    }
}
