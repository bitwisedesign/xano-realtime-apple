import Foundation

/// Join payload sent when subscribing to a channel.
struct JoinPayload: Codable, Sendable, Equatable {
    /// Requests the server replay recent history after join.
    var history: Bool
    /// Requests presence snapshots and updates for the channel.
    var presence: Bool

    /// Creates a join payload.
    ///
    /// - Parameters:
    ///   - history: Whether to request history.
    ///   - presence: Whether to request presence.
    init(history: Bool = false, presence: Bool = false) {
        self.history = history
        self.presence = presence
    }
}

/// Connection status payload (`connected` or `disconnected`).
struct ConnectionStatusPayload: Codable, Sendable, Equatable {
    /// Reported status string.
    var status: ConnectionStatusValue
}

/// Status values used in ``ConnectionStatusPayload``.
enum ConnectionStatusValue: String, Codable, Sendable {
    /// The socket is open.
    case connected
    /// The socket is closed.
    case disconnected
}

/// Full presence list replacing the local cache.
struct PresenceFullPayload: Codable, Sendable, Equatable {
    /// Current members of the channel.
    var presence: [RealtimePeer]
}

/// Incremental presence change for a single peer.
struct PresenceUpdatePayload: Codable, Sendable, Equatable {
    /// Whether the peer joined or left.
    var action: PresenceChange
    /// Peer that changed membership.
    var presence: RealtimePeer
}

/// Presence delta action (`join` or `leave`).
public enum PresenceChange: String, Codable, Sendable {
    /// A peer joined the channel.
    case join
    /// A peer left the channel.
    case leave
}
