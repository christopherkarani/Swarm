import Foundation

internal enum HiveEventEnqueueResult: Sendable {
    case enqueued
    case droppedDebug
    case terminated
}

internal final class HiveEventStreamController: @unchecked Sendable {
    // Uses NSCondition for synchronous producer backpressure and consumer wakeups.
    // NSCondition is not statically Sendable, so this class requires manual synchronization.
    private enum FinishState {
        case finished
        case failed(Error)
    }

    private enum DrainState {
        case hasEvent
        case finished
        case failed(Error)
    }

    private struct EventRingQueue {
        private let capacity: Int
        private var storage: [HiveEvent?]
        private var headIndex: Int = 0
        private(set) var count: Int = 0

        init(capacity: Int) {
            self.capacity = capacity
            self.storage = Array(repeating: nil, count: capacity)
        }

        var isEmpty: Bool {
            count == 0
        }

        var first: HiveEvent? {
            guard count > 0 else { return nil }
            return storage[headIndex]
        }

        var last: HiveEvent? {
            guard count > 0 else { return nil }
            return storage[physicalIndex(offset: count - 1)]
        }

        mutating func append(_ event: HiveEvent) -> Bool {
            guard count < capacity else { return false }
            storage[physicalIndex(offset: count)] = event
            count += 1
            return true
        }

        mutating func replaceLast(with event: HiveEvent) {
            guard count > 0 else { return }
            storage[physicalIndex(offset: count - 1)] = event
        }

        mutating func removeFirst() {
            guard count > 0 else { return }
            storage[headIndex] = nil
            count -= 1
            if count == 0 {
                headIndex = 0
                return
            }
            headIndex = nextIndex(after: headIndex)
        }

        mutating func removeAll(keepingCapacity: Bool) {
            if keepingCapacity {
                if count > 0 {
                    var index = headIndex
                    for _ in 0..<count {
                        storage[index] = nil
                        index = nextIndex(after: index)
                    }
                }
            } else {
                storage = Array(repeating: nil, count: capacity)
            }
            headIndex = 0
            count = 0
        }

        private func physicalIndex(offset: Int) -> Int {
            let raw = headIndex + offset
            return raw < capacity ? raw : raw - capacity
        }

        private func nextIndex(after index: Int) -> Int {
            let next = index + 1
            return next == capacity ? 0 : next
        }
    }

    private let capacity: Int
    private let condition = NSCondition()
    private let pumpQueue: DispatchQueue

    private var queue: EventRingQueue
    private var finishState: FinishState?

    init(capacity: Int) {
        let normalizedCapacity = max(1, capacity)
        self.capacity = normalizedCapacity
        self.pumpQueue = DispatchQueue(
            label: "HiveEventStreamController.pump.\(UUID().uuidString)",
            qos: .userInitiated
        )
        self.queue = EventRingQueue(capacity: normalizedCapacity)
    }

    func makeStream() -> AsyncThrowingStream<HiveEvent, Error> {
        // Use a `.bufferingOldest(...)` continuation so already-buffered events are preserved.
        // When the continuation buffer is full, `yield` reports `.dropped` and the new element was not accepted.
        //
        // NOTE: We keep a minimum continuation buffer to avoid small `eventBufferCapacity` values causing
        // excessive drops of important events in tests and UI streams.
        AsyncThrowingStream(HiveEvent.self, bufferingPolicy: .bufferingOldest(max(64, capacity))) { continuation in
            continuation.onTermination = { [weak self] _ in
                self?.terminateStreamAndUnblockProducers()
            }
            pumpQueue.async { [weak self] in
                self?.pump(into: continuation)
            }
        }
    }

    func finish() {
        condition.lock()
        if finishState == nil {
            finishState = .finished
        }
        condition.broadcast()
        condition.unlock()
    }

    func finish(throwing error: Error) {
        condition.lock()
        if finishState == nil {
            finishState = .failed(error)
        }
        condition.broadcast()
        condition.unlock()
    }

    func enqueue(
        eventIndex: UInt64,
        runID: HiveRunID,
        attemptID: HiveRunAttemptID,
        kind: HiveEventKind,
        stepIndex: Int?,
        taskOrdinal: Int?,
        metadata: [String: String],
        treatAsNonDroppable: Bool = false
    ) -> HiveEventEnqueueResult {
        condition.lock()
        defer { condition.unlock() }

        if finishState != nil {
            return .terminated
        }

        if treatAsNonDroppable == false, isDroppable(kind) {
            if queue.count >= capacity {
                return .droppedDebug
            }

            let id = HiveEventID(
                runID: runID,
                attemptID: attemptID,
                eventIndex: eventIndex,
                stepIndex: stepIndex,
                taskOrdinal: taskOrdinal
            )
            _ = queue.append(HiveEvent(id: id, kind: kind, metadata: metadata))
            condition.signal()
            return .enqueued
        }

        while queue.count >= capacity, finishState == nil {
            condition.wait()
        }

        if finishState != nil {
            return .terminated
        }

        let id = HiveEventID(
            runID: runID,
            attemptID: attemptID,
            eventIndex: eventIndex,
            stepIndex: stepIndex,
            taskOrdinal: taskOrdinal
        )
        _ = queue.append(HiveEvent(id: id, kind: kind, metadata: metadata))
        condition.signal()
        return .enqueued
    }

    func pump(into continuation: AsyncThrowingStream<HiveEvent, Error>.Continuation) {
        while true {
            let state = drainState()
            switch state {
            case .hasEvent:
                while true {
                    guard let event = snapshotFirst() else { break }
                    switch continuation.yield(event) {
                    case .enqueued:
                        consumeFirst()
                        break
                    case .dropped:
                        // `.bufferingOldest` reports `.dropped` when this event could not be delivered.
                        // Droppable events are intentionally discarded; non-droppable events must stay queued
                        // and retry until a consumer makes space. Once the run has finished, an unconsumed
                        // stream must be allowed to terminate instead of keeping the pump alive forever.
                        if isDroppable(event.kind) || isFinished {
                            consumeFirst()
                        } else {
                            Thread.sleep(forTimeInterval: 0.00025)
                        }
                        break
                    case .terminated:
                        terminateStreamAndUnblockProducers()
                        return
                    @unknown default:
                        consumeFirst()
                        break
                    }
                }
            case .finished:
                continuation.finish()
                return
            case .failed(let error):
                continuation.finish(throwing: error)
                return
            }
        }
    }

    private func drainState() -> DrainState {
        condition.lock()
        while queue.isEmpty, finishState == nil {
            condition.wait()
        }

        if !queue.isEmpty {
            condition.unlock()
            return .hasEvent
        }

        let state = finishState
        condition.unlock()

        switch state {
        case .none, .some(.finished):
            return .finished
        case .some(.failed(let error)):
            return .failed(error)
        }
    }

    private func snapshotFirst() -> HiveEvent? {
        condition.lock()
        let first = queue.first
        condition.unlock()
        return first
    }

    private func consumeFirst() {
        condition.lock()
        if !queue.isEmpty {
            queue.removeFirst()
            condition.broadcast()
        }
        condition.unlock()
    }

    private func isDroppable(_ kind: HiveEventKind) -> Bool {
        isDroppableDebug(kind)
    }

    private func isDroppableDebug(_ kind: HiveEventKind) -> Bool {
        if case .customDebug = kind { return true }
        return false
    }

    private func terminateStreamAndUnblockProducers() {
        condition.lock()
        if finishState == nil {
            finishState = .finished
        }
        if !queue.isEmpty {
            queue.removeAll(keepingCapacity: true)
        }
        condition.broadcast()
        condition.unlock()
    }

    private var isFinished: Bool {
        condition.lock()
        let finished = finishState != nil
        condition.unlock()
        return finished
    }
}
