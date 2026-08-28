import Foundation

/// Authenticated peer identity attached to inbound envelopes and presence lists.
public struct RealtimePeer: Codable, Sendable, Equatable {
    /// Server-assigned socket identifier for this peer.
    public let socketId: String
    /// Extra claims copied from the realtime auth token configuration.
    public var extras: [String: JSONValue]
    /// Table and row identity for the authenticated user.
    public let permissions: RealtimePermissions

    /// Creates a peer identity.
    ///
    /// - Parameters:
    ///   - socketId: Server-assigned socket identifier.
    ///   - extras: Extra claims from the auth token.
    ///   - permissions: Table and row identity.
    public init(
        socketId: String,
        extras: [String: JSONValue] = [:],
        permissions: RealtimePermissions
    ) {
        self.socketId = socketId
        self.extras = extras
        self.permissions = permissions
    }
}
