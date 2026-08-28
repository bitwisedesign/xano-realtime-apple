import Foundation

/// Heartbeat timing used to keep carrier NAT mappings warm and detect silent socket death.
///
/// The official JS SDK has no heartbeat. This policy exists for mobile networks: idle
/// cellular NATs drop mappings without a TCP FIN, leaving `URLSessionWebSocketTask`
/// looking open. Periodic `sendPing` frames both refresh the mapping and fail fast
/// when a pong never arrives.
struct HeartbeatPolicy: Sendable, Equatable {
    /// Time between pings; `nil` or non-positive disables the heartbeat.
    var interval: Duration?
    /// How long a ping may wait for a pong before the socket is treated as dead.
    var timeout: Duration

    /// Creates a heartbeat policy.
    ///
    /// - Parameters:
    ///   - interval: Ping interval; `nil` disables pings.
    ///   - timeout: Pong wait bound.
    init(interval: Duration? = .seconds(20), timeout: Duration = .seconds(10)) {
        self.interval = interval
        self.timeout = timeout
    }

    /// Whether a heartbeat loop should run.
    var isEnabled: Bool {
        guard let interval else {
            return false
        }
        return interval > .zero
    }
}
