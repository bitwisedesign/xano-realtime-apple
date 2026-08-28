import Foundation

/// Per-action options embedded in a Xano Realtime envelope.
public struct RealtimeActionOptions: Codable, Sendable, Equatable {
    /// Channel this action targets, when the action is channel-scoped.
    public var channel: String?
    /// Peer socket identifier for private messages.
    public var socketId: String?
    /// When `true`, the server delivers the message only to authenticated members.
    public var authenticated: Bool?

    /// Creates action options.
    ///
    /// - Parameters:
    ///   - channel: Channel name, when required by the action.
    ///   - socketId: Target peer for a private message.
    ///   - authenticated: Restrict delivery to authenticated members.
    public init(
        channel: String? = nil,
        socketId: String? = nil,
        authenticated: Bool? = nil
    ) {
        self.channel = channel
        self.socketId = socketId
        self.authenticated = authenticated
    }
}
