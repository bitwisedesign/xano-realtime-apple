import Foundation

/// Exponential reconnect delay: start at 1 second, double each attempt, cap at 60 seconds.
///
/// Matches the official JS SDK (`defaultReconnectInterval` 1000, multiply by 2, max 60000).
struct ExponentialBackoff: Sendable, Equatable {
    // MARK: - Properties

    /// Delay used for the first attempt and after ``reset()``.
    var initial: Duration
    /// Maximum delay.
    var cap: Duration
    /// Delay that ``next()`` will return.
    private(set) var current: Duration
    /// Number of times ``next()`` has been called since the last reset.
    private(set) var attempt: Int

    // MARK: - Initialization

    /// Creates a backoff sequence.
    ///
    /// ``current`` is clamped to ``cap`` when `initial` is larger.
    ///
    /// - Parameters:
    ///   - initial: First delay. Defaults to 1 second.
    ///   - cap: Maximum delay. Defaults to 60 seconds.
    init(initial: Duration = .seconds(1), cap: Duration = .seconds(60)) {
        self.initial = initial
        self.cap = cap
        self.current = min(initial, cap)
        self.attempt = 0
    }

    // MARK: - Public API

    /// Returns the current delay and advances to the next (doubled, capped) value.
    ///
    /// The returned delay is never larger than ``cap``, including after ``initial``
    /// or ``cap`` are mutated.
    ///
    /// - Returns: Delay to wait before the next connect attempt.
    mutating func next() -> Duration {
        let value = min(current, cap)
        attempt += 1
        current = min(value * 2, cap)
        return value
    }

    /// Restores ``current`` to ``initial`` (clamped to ``cap``) and clears ``attempt``.
    mutating func reset() {
        current = min(initial, cap)
        attempt = 0
    }
}
