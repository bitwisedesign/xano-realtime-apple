import Foundation

/// Event the connection actor publishes to the client facade.
enum ConnectionEvent: Sendable, Equatable {
    /// A decoded inbound envelope, including synthetic connection-status frames.
    case envelope(RealtimeEnvelope)
    /// A transport or coding failure that should reach channel streams.
    case failure(XanoRealtimeError)
}
