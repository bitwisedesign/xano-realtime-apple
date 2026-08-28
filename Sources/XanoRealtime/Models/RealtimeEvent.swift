import Foundation

/// Application-facing event emitted on a channel ``AsyncStream``.
public enum RealtimeEvent: Sendable, Equatable {
    /// The multiplexed socket became connected (or reconnected).
    case connected
    /// The multiplexed socket became disconnected.
    case disconnected
    /// An application message arrived on the channel.
    case message(RealtimeMessage)
    /// Full presence list replaced the local cache.
    case presenceFull([RealtimePeer])
    /// A single peer joined or left.
    case presenceUpdate(action: PresenceChange, peer: RealtimePeer)
    /// History batch from the server.
    case history(JSONValue)
    /// Transport, decode, or server error.
    case error(XanoRealtimeError)
    /// Uninterpreted wire action (`event`, `join`, `leave`, unknown, or a
    /// `connection_status` payload the SDK did not recognize).
    case unhandled(action: String, payload: JSONValue?)
}

/// Application message delivered on a channel.
public struct RealtimeMessage: Sendable, Equatable {
    /// Message body as JSON.
    public var payload: JSONValue
    /// Sender identity when the server included one.
    public var sender: RealtimePeer?
    /// Channel name from the envelope options, when present.
    public var channel: String?
    /// Target peer socket identifier from the envelope options, when present.
    public var socketId: String?
    /// Whether the server marked the message as authenticated-only.
    public var authenticated: Bool?

    /// Creates a message event payload.
    ///
    /// - Parameters:
    ///   - payload: Message body.
    ///   - sender: Optional sender identity.
    ///   - options: Optional envelope options copied onto ``channel``, ``socketId``,
    ///     and ``authenticated``.
    init(
        payload: JSONValue,
        sender: RealtimePeer? = nil,
        options: RealtimeActionOptions? = nil
    ) {
        self.payload = payload
        self.sender = sender
        self.channel = options?.channel
        self.socketId = options?.socketId
        self.authenticated = options?.authenticated
    }
}
