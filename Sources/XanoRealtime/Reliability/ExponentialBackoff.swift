import Foundation

/// Exponential reconnect delay: start at 1 second, double each attempt, cap at 60 seconds.
///
/// Matches the official JS SDK (`defaultReconnectInterval` 1000, multiply by 2, max 60000).
public struct ExponentialBackoff: Sendable, Equatable {
    /// Delay used for the first attempt and after ``reset()``.
    public var initial: Duration
    /// Maximum delay.
    public var cap: Duration
    /// Delay that ``next()`` will return.
    public private(set) var current: Duration
    /// Number of times ``next()`` has been called since the last reset.
    public private(set) var attempt: Int

    /// Creates a backoff sequence.
    ///
    /// - Parameters:
    ///   - initial: First delay. Defaults to 1 second.
    ///   - cap: Maximum delay. Defaults to 60 seconds.
    public init(initial: Duration = .seconds(1), cap: Duration = .seconds(60)) {
        self.initial = initial
        self.cap = cap
        self.current = initial
        self.attempt = 0
    }

    /// Returns the current delay and advances to the next (doubled, capped) value.
    ///
    /// - Returns: Delay to wait before the next connect attempt.
    public mutating func next() -> Duration {
        let value = current
        attempt += 1
        let doubled = current * 2
        current = doubled < cap ? doubled : cap
        return value
    }

    /// Restores ``current`` to ``initial`` and clears ``attempt``.
    public mutating func reset() {
        current = initial
        attempt = 0
    }
}
