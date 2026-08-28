import Foundation

/// Join payload sent when subscribing to a channel.
public struct JoinPayload: Codable, Sendable, Equatable {
    /// Requests the server replay recent history after join.
    public var history: Bool
    /// Requests presence snapshots and updates for the channel.
    public var presence: Bool

    /// Creates a join payload.
    ///
    /// - Parameters:
    ///   - history: Whether to request history.
    ///   - presence: Whether to request presence.
    public init(history: Bool = false, presence: Bool = false) {
        self.history = history
        self.presence = presence
    }
}

/// Connection status payload (`connected` or `disconnected`).
public struct ConnectionStatusPayload: Codable, Sendable, Equatable {
    /// Reported status string.
    public var status: ConnectionStatusValue

    /// Creates a connection-status payload.
    ///
    /// - Parameter status: `connected` or `disconnected`.
    public init(status: ConnectionStatusValue) {
        self.status = status
    }
}

/// Status values used in ``ConnectionStatusPayload``.
public enum ConnectionStatusValue: String, Codable, Sendable {
    /// The socket is open.
    case connected
    /// The socket is closed.
    case disconnected
}

/// Full presence list replacing the local cache.
public struct PresenceFullPayload: Codable, Sendable, Equatable {
    /// Current members of the channel.
    public var presence: [RealtimePeer]

    /// Creates a full-presence payload.
    ///
    /// - Parameter presence: Current members.
    public init(presence: [RealtimePeer]) {
        self.presence = presence
    }
}

/// Incremental presence change for a single peer.
public struct PresenceUpdatePayload: Codable, Sendable, Equatable {
    /// Whether the peer joined or left.
    public var action: PresenceChange
    /// Peer that changed membership.
    public var presence: RealtimePeer

    /// Creates a presence-update payload.
    ///
    /// - Parameters:
    ///   - action: Join or leave.
    ///   - presence: Affected peer.
    public init(action: PresenceChange, presence: RealtimePeer) {
        self.action = action
        self.presence = presence
    }
}

/// Presence delta action (`join` or `leave`).
public enum PresenceChange: String, Codable, Sendable {
    /// A peer joined the channel.
    case join
    /// A peer left the channel.
    case leave
}
