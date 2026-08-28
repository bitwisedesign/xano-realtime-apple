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
    /// Uninterpreted envelope (`event`, `join`, `leave`, or unknown actions).
    case raw(RealtimeEnvelope)
}

/// Application message delivered on a channel.
public struct RealtimeMessage: Sendable, Equatable {
    /// Message body as JSON.
    public var payload: JSONValue
    /// Sender identity when the server included one.
    public var sender: RealtimePeer?
    /// Envelope options (channel, socket, authenticated).
    public var options: RealtimeActionOptions?

    /// Creates a message event payload.
    ///
    /// - Parameters:
    ///   - payload: Message body.
    ///   - sender: Optional sender identity.
    ///   - options: Optional envelope options.
    public init(
        payload: JSONValue,
        sender: RealtimePeer? = nil,
        options: RealtimeActionOptions? = nil
    ) {
        self.payload = payload
        self.sender = sender
        self.options = options
    }
}
