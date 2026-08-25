// CircuitBreaker.swift
// Swarm Framework
//
// Circuit breaker pattern implementation for fault tolerance and service protection.

import Foundation

// MARK: - CircuitBreaker

/// Actor-based circuit breaker for preventing cascading failures.
///
/// The circuit breaker monitors operation failures and automatically opens (stops allowing operations)
/// when a threshold is reached, then attempts recovery after a timeout period.
///
/// State transitions:
/// - **Closed**: Normal operation, requests allowed
/// - **Open**: Failures exceeded threshold, requests blocked until timeout
/// - **Half-Open**: Testing recovery, limited requests allowed
///
/// Example:
/// ```swift
/// let breaker = CircuitBreaker(
///     name: "payment-service",
///     failureThreshold: 5,
///     resetTimeout: 60.0
/// )
///
/// let result = try await breaker.execute {
///     try await paymentService.charge(amount: 100)
/// }
/// ```
public actor CircuitBreaker {
    // MARK: Public

    // MARK: - State

    /// Circuit breaker state.
    public enum State: Sendable, Equatable {
        /// Circuit is closed, allowing operations.
        case closed

        /// Circuit is open, blocking operations until the specified date.
        case open(until: Date)

        /// Circuit is half-open, allowing limited test operations.
        case halfOpen
    }

    /// Unique name for this circuit breaker.
    public let name: String

    /// Number of consecutive failures before opening the circuit.
    public let failureThreshold: Int

    /// Number of consecutive successes in half-open state to close the circuit.
    public let successThreshold: Int

    /// Time interval to wait before transitioning from open to half-open.
    public let resetTimeout: TimeInterval

    /// Maximum number of requests allowed in half-open state.
    public let halfOpenMaxRequests: Int

    // MARK: - Initialization

    /// Creates a new circuit breaker.
    /// - Parameters:
    ///   - name: Unique name for this breaker.
    ///   - failureThreshold: Number of consecutive failures before opening (default: 5).
    ///   - successThreshold: Number of consecutive successes to close from half-open (default: 2).
    ///   - resetTimeout: Time in seconds before attempting recovery (default: 60.0).
    ///   - halfOpenMaxRequests: Maximum concurrent requests in half-open state (default: 1).
    public init(
        name: String,
        failureThreshold: Int = 5,
        successThreshold: Int = 2,
        resetTimeout: TimeInterval = 60.0,
        halfOpenMaxRequests: Int = 1
    ) {
        self.init(
            name: name,
            failureThreshold: failureThreshold,
            successThreshold: successThreshold,
            resetTimeout: resetTimeout,
            halfOpenMaxRequests: halfOpenMaxRequests,
            clock: LiveSwarmClock.live
        )
    }

    /// Creates a new circuit breaker driven by an injected time source.
    ///
    /// Injecting a virtual clock makes open-window deadlines deterministic for
    /// tests; production callers use the default initializer backed by the
    /// live clock. Declared under `ColonyInternal` because `SwarmClock` is an
    /// SPI protocol and cannot appear in an unannotated public signature.
    /// - Parameters:
    ///   - name: Unique name for this breaker.
    ///   - failureThreshold: Number of consecutive failures before opening.
    ///   - successThreshold: Number of consecutive successes to close from half-open.
    ///   - resetTimeout: Time in seconds before attempting recovery.
    ///   - halfOpenMaxRequests: Maximum concurrent requests in half-open state.
    ///   - clock: Time source driving open-window deadlines and timestamps;
    ///     pass `nil` to use the live clock.
    @_spi(ColonyInternal)
    public init(
        name: String,
        failureThreshold: Int,
        successThreshold: Int,
        resetTimeout: TimeInterval,
        halfOpenMaxRequests: Int,
        clock: (any SwarmClock)?
    ) {
        self.name = name
        self.failureThreshold = max(1, failureThreshold)
        self.successThreshold = max(1, successThreshold)
        self.resetTimeout = max(0, resetTimeout)
        self.halfOpenMaxRequests = max(1, halfOpenMaxRequests)
        let resolvedClock = clock ?? LiveSwarmClock.live
        self.clock = resolvedClock
        self.clockBridge = CircuitBreakerClockBridge(clock: resolvedClock)
    }

    // MARK: - Public API

    /// Executes an operation through the circuit breaker.
    /// - Parameter operation: The async operation to execute.
    /// - Returns: The result of the operation.
    /// - Throws: `ResilienceError.circuitBreakerOpen` if circuit is open, or the operation's error.
    public func execute<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        // Check if we should transition from open to half-open
        try await checkAndTransitionState()

        // Check current state and decide whether to allow execution
        switch state {
        case .closed:
            return try await executeOperation(operation)

        case .open:
            throw ResilienceError.circuitBreakerOpen(serviceName: name)

        case .halfOpen:
            // Check if we can allow another request in half-open state
            guard halfOpenRequestsInFlight < halfOpenMaxRequests else {
                throw ResilienceError.circuitBreakerOpen(serviceName: name)
            }

            halfOpenRequestsInFlight += 1
            defer { halfOpenRequestsInFlight -= 1 }

            return try await executeOperation(operation)
        }
    }

    /// Returns the current state of the circuit breaker.
    public func currentState() -> State {
        state
    }

    /// Manually resets the circuit breaker to closed state.
    public func reset() async {
        state = .closed
        consecutiveFailures = 0
        consecutiveSuccesses = 0
        halfOpenRequestsInFlight = 0
    }

    /// Manually opens the circuit breaker.
    public func trip() async {
        fsmSnapshot = CircuitBreakerTransitions.tripped(
            fsmSnapshot,
            resetTimeout: resetTimeout,
            now: currentDate()
        )
    }

    /// Returns statistics about this circuit breaker.
    public func statistics() -> Statistics {
        Statistics(
            name: name,
            state: state,
            failureCount: totalFailures,
            successCount: totalSuccesses,
            lastFailureTime: lastFailureTime
        )
    }

    // MARK: Private

    /// Injected time source; every deadline and timestamp reads through it.
    private let clock: any SwarmClock

    /// Maps injected-clock readings onto the `Date` timeline of the public state.
    /// Internal (not private) so tests can assert exact instants against the anchor.
    let clockBridge: CircuitBreakerClockBridge

    /// Current state of the circuit breaker.
    private var state: State = .closed

    /// Count of consecutive failures.
    private var consecutiveFailures = 0

    /// Count of consecutive successes in half-open state.
    private var consecutiveSuccesses = 0

    /// Total failure count (lifetime).
    private var totalFailures = 0

    /// Total success count (lifetime).
    private var totalSuccesses = 0

    /// Number of requests currently in flight in half-open state.
    private var halfOpenRequestsInFlight = 0

    /// Timestamp of last failure.
    private var lastFailureTime: Date?

    /// Transition-relevant state as a pure-FSM snapshot, bridged to the stored fields.
    private var fsmSnapshot: CircuitBreakerTransitions.Snapshot {
        get {
            .init(
                state: state,
                consecutiveFailures: consecutiveFailures,
                consecutiveSuccesses: consecutiveSuccesses
            )
        }
        set {
            state = newValue.state
            consecutiveFailures = newValue.consecutiveFailures
            consecutiveSuccesses = newValue.consecutiveSuccesses
        }
    }

    /// Current instant on the breaker's `Date` timeline, read through the injected clock.
    ///
    /// This conversion is part of the clock↔`Date` adapter (AC-007): all breaker
    /// time math flows through here instead of raw wall-clock reads.
    private func currentDate() -> Date {
        clockBridge.date(atNanoseconds: clock.nowNanoseconds())
    }

    // MARK: - Private Helpers

    /// Executes the operation and handles state transitions based on success/failure.
    private func executeOperation<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        do {
            let result = try await operation()
            await recordSuccess()
            return result
        } catch {
            await recordFailure()
            throw error
        }
    }

    /// Records a successful operation and handles state transitions.
    private func recordSuccess() async {
        totalSuccesses += 1
        fsmSnapshot = CircuitBreakerTransitions.success(fsmSnapshot, successThreshold: successThreshold)
    }

    /// Records a failed operation and handles state transitions.
    private func recordFailure() async {
        totalFailures += 1
        let now = currentDate()
        lastFailureTime = now
        fsmSnapshot = CircuitBreakerTransitions.failure(
            fsmSnapshot,
            failureThreshold: failureThreshold,
            resetTimeout: resetTimeout,
            now: now
        )
    }

    /// Checks if the circuit should transition from open to half-open based on timeout.
    private func checkAndTransitionState() async throws {
        if let transitioned = CircuitBreakerTransitions.timeoutCheck(fsmSnapshot, now: currentDate()) {
            fsmSnapshot = transitioned
            halfOpenRequestsInFlight = 0
        }
    }
}

// MARK: - Clock Bridge

/// Maps monotonic `SwarmClock` nanoseconds onto the `Date` timeline used by
/// the breaker's public state (`State.open(until:)`, `Statistics.lastFailureTime`).
///
/// This is the clock↔`Date` adapter (AC-007): construction captures a single
/// wall-clock anchor paired with the injected clock's reading; every later
/// conversion derives purely from injected-clock readings via
/// `date(atNanoseconds:)`.
struct CircuitBreakerClockBridge: Sendable {
    /// Injected-clock reading captured at construction.
    let anchorNanoseconds: UInt64

    /// Wall-clock instant corresponding to `anchorNanoseconds`.
    let anchorDate: Date

    /// Creates a bridge from an explicit anchor pair (test-friendly).
    init(anchorNanoseconds: UInt64, anchorDate: Date) {
        self.anchorNanoseconds = anchorNanoseconds
        self.anchorDate = anchorDate
    }

    /// Anchors one raw wall-clock read to the injected clock's current reading.
    init(clock: any SwarmClock) {
        self.init(anchorNanoseconds: clock.nowNanoseconds(), anchorDate: Date())
    }

    /// Converts an injected-clock reading into its `Date` timeline instant.
    func date(atNanoseconds nanoseconds: UInt64) -> Date {
        let delta = Int64(bitPattern: nanoseconds &- anchorNanoseconds)
        return anchorDate.addingTimeInterval(Double(delta) / 1_000_000_000)
    }
}

// MARK: - Pure FSM Transitions

/// Pure transition math for the circuit-breaker state machine.
///
/// Functions are static and side-effect free: each takes the full pre-event
/// snapshot plus configuration and event instant, returning the post-event
/// snapshot or `nil` when nothing changes. Keeping them off the actor makes
/// every transition rule unit-testable without executing actor code or reading
/// a clock. Behavior mirrors the original inline logic exactly:
/// - Failure in closed state trips once consecutive failures reach the threshold.
/// - Any failure in half-open reopens the window from that instant.
/// - Tripping while open extends the window from the new event's instant.
/// - Success in half-open closes only after the success threshold is met.
enum CircuitBreakerTransitions {
    /// Complete transition-relevant state of a breaker.
    struct Snapshot: Equatable, Sendable {
        /// Current breaker state.
        var state: CircuitBreaker.State

        /// Consecutive failure count driving trip thresholds.
        var consecutiveFailures = 0

        /// Consecutive success count driving half-open recovery.
        var consecutiveSuccesses = 0

        /// Creates a snapshot.
        init(
            state: CircuitBreaker.State,
            consecutiveFailures: Int = 0,
            consecutiveSuccesses: Int = 0
        ) {
            self.state = state
            self.consecutiveFailures = consecutiveFailures
            self.consecutiveSuccesses = consecutiveSuccesses
        }
    }

    /// Applies one failed operation outcome.
    ///
    /// - Parameters:
    ///   - before: Pre-failure snapshot.
    ///   - failureThreshold: Consecutive failures required to trip from closed.
    ///   - resetTimeout: Open-window length applied when tripping/reopening.
    ///   - now: Failure instant; anchors any new `.open(until:)` deadline.
    static func failure(
        _ before: Snapshot,
        failureThreshold: Int,
        resetTimeout: TimeInterval,
        now: Date
    ) -> Snapshot {
        var after = before
        after.consecutiveFailures += 1
        after.consecutiveSuccesses = 0

        switch before.state {
        case .closed:
            if after.consecutiveFailures >= failureThreshold {
                // Transition to open
                after.state = .open(until: now.addingTimeInterval(resetTimeout))
            }
        case .halfOpen:
            // Any failure in half-open transitions back to open
            after.state = .open(until: now.addingTimeInterval(resetTimeout))
        case .open:
            // Already open, no state change needed
            break
        }
        return after
    }

    /// Applies one successful operation outcome.
    ///
    /// - Parameters:
    ///   - before: Pre-success snapshot.
    ///   - successThreshold: Consecutive half-open successes required to close.
    static func success(_ before: Snapshot, successThreshold: Int) -> Snapshot {
        var after = before
        after.consecutiveFailures = 0

        switch before.state {
        case .halfOpen:
            after.consecutiveSuccesses += 1
            if after.consecutiveSuccesses >= successThreshold {
                // Transition to closed
                after.state = .closed
                after.consecutiveSuccesses = 0
            }
        case .closed,
             .open:
            after.consecutiveSuccesses = 0
        }
        return after
    }

    /// Applies a manual trip.
    ///
    /// Opens the window from `now`, extending it even if already open;
    /// resets the half-open success streak without touching failures.
    ///
    /// - Parameters:
    ///   - before: Pre-trip snapshot.
    ///   - resetTimeout: Open-window length.
    ///   - now: Trip instant; anchors the new `.open(until:)` deadline.
    static func tripped(
        _ before: Snapshot,
        resetTimeout: TimeInterval,
        now: Date
    ) -> Snapshot {
        var after = before
        after.state = .open(until: now.addingTimeInterval(resetTimeout))
        after.consecutiveSuccesses = 0
        return after
    }

    /// Applies the open-timeout check performed before each execution.
    ///
    /// Returns the post-transition snapshot when the open window has elapsed by
    /// `now` (`now >= until`), moving to half-open and resetting the success
    /// streak; returns `nil` when no transition occurs.
    static func timeoutCheck(_ before: Snapshot, now: Date) -> Snapshot? {
        guard case let .open(until) = before.state, now >= until else {
            return nil
        }

        var after = before
        after.state = .halfOpen
        after.consecutiveSuccesses = 0
        return after
    }
}

// MARK: - Statistics

/// Statistics about a circuit breaker's operation.
public struct Statistics: Sendable, Equatable {
    /// Name of the circuit breaker.
    public let name: String

    /// Current state.
    public let state: CircuitBreaker.State

    /// Total number of failures.
    public let failureCount: Int

    /// Total number of successes.
    public let successCount: Int

    /// Timestamp of the last failure, if any.
    public let lastFailureTime: Date?

    /// Success rate (0.0 to 1.0), or nil if no operations have been executed.
    public var successRate: Double? {
        let total = successCount + failureCount
        guard total > 0 else { return nil }
        return Double(successCount) / Double(total)
    }
}

// MARK: - CircuitBreakerRegistry

/// Actor for managing multiple circuit breakers.
///
/// Provides centralized registry for circuit breakers, enabling:
/// - Shared circuit breakers across services
/// - Global reset operations
/// - Monitoring and statistics collection
///
/// Example:
/// ```swift
/// let registry = CircuitBreakerRegistry()
///
/// let apiBreaker = await registry.breaker(named: "api") { config in
///     config.failureThreshold = 10
///     config.resetTimeout = 120.0
/// }
///
/// let dbBreaker = await registry.breaker(named: "database")
/// ```
public actor CircuitBreakerRegistry {
    // MARK: Public

    // MARK: - Configuration

    /// Configuration for creating a circuit breaker.
    public struct Configuration: Sendable {
        /// Number of consecutive failures before opening.
        public var failureThreshold: Int = 5

        /// Number of consecutive successes to close from half-open.
        public var successThreshold: Int = 2

        /// Time in seconds before attempting recovery.
        public var resetTimeout: TimeInterval = 60.0

        /// Maximum concurrent requests in half-open state.
        public var halfOpenMaxRequests: Int = 1

        public init() {}
    }

    // MARK: - Initialization

    /// Creates a new circuit breaker registry.
    /// - Parameter defaultConfiguration: Default configuration for new breakers.
    public init(defaultConfiguration: Configuration = Configuration()) {
        self.defaultConfiguration = defaultConfiguration
    }

    // MARK: - Public API

    /// Gets or creates a circuit breaker with the specified name.
    /// - Parameters:
    ///   - name: Unique name for the circuit breaker.
    ///   - configure: Optional closure to customize the configuration.
    /// - Returns: The circuit breaker instance.
    public func breaker(
        named name: String,
        configure: (@Sendable (inout Configuration) -> Void)? = nil
    ) -> CircuitBreaker {
        // Return existing breaker if found
        if let existing = breakers[name] {
            return existing
        }

        // Create new breaker with configuration
        var config = defaultConfiguration
        configure?(&config)

        let breaker = CircuitBreaker(
            name: name,
            failureThreshold: config.failureThreshold,
            successThreshold: config.successThreshold,
            resetTimeout: config.resetTimeout,
            halfOpenMaxRequests: config.halfOpenMaxRequests
        )

        breakers[name] = breaker
        return breaker
    }

    /// Returns all registered circuit breakers.
    public func allBreakers() -> [CircuitBreaker] {
        Array(breakers.values)
    }

    /// Resets all circuit breakers to closed state.
    public func resetAll() async {
        for breaker in breakers.values {
            await breaker.reset()
        }
    }

    /// Removes a circuit breaker from the registry.
    /// - Parameter name: Name of the circuit breaker to remove.
    public func remove(named name: String) {
        breakers.removeValue(forKey: name)
    }

    /// Removes all circuit breakers from the registry.
    public func removeAll() {
        breakers.removeAll()
    }

    /// Collects statistics from all registered circuit breakers.
    public func allStatistics() async -> [Statistics] {
        var stats: [Statistics] = []
        for breaker in breakers.values {
            let stat = await breaker.statistics()
            stats.append(stat)
        }
        return stats
    }

    // MARK: Private

    /// Registry of circuit breakers by name.
    private var breakers: [String: CircuitBreaker] = [:]

    /// Default configuration for new circuit breakers.
    private let defaultConfiguration: Configuration
}

// MARK: - Convenience Extensions

public extension CircuitBreaker {
    /// Returns whether the circuit is currently allowing requests.
    func isAllowingRequests() -> Bool {
        switch state {
        case .closed,
             .halfOpen:
            true
        case .open:
            false
        }
    }
}
