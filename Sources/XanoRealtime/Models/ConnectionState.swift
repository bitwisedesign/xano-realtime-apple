import Foundation

/// Lifecycle state of the multiplexed realtime socket.
public enum ConnectionState: Sendable, Equatable {
    /// No socket is open and no reconnect is scheduled.
    case disconnected
    /// A socket is being opened.
    case connecting
    /// The socket is open and ready to send.
    case connected
    /// A recoverable close occurred and another attempt is scheduled.
    case reconnecting(attempt: Int)
}
