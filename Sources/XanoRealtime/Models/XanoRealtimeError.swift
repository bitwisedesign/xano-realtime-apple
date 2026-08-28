import Foundation

/// Errors produced by the SDK (configuration, transport, coding, or server).
public enum XanoRealtimeError: Error, Sendable, Equatable {
    /// Configuration cannot produce a valid connection URL or credentials.
    case invalidConfiguration(String)
    /// An outbound action was attempted while the socket was not connected.
    case notConnected
    /// The socket closed with the given code.
    case connectionClosed(code: WebSocketCloseCode)
    /// An inbound frame could not be decoded.
    case decodingFailed(String)
    /// An outbound envelope could not be encoded.
    case encodingFailed(String)
    /// The server sent an `error` action; the payload is the server body.
    case server(JSONValue)
    /// A heartbeat ping did not receive a pong in time.
    case pingTimedOut
}

extension XanoRealtimeError: LocalizedError {
    /// Human-readable description of the error.
    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message):
            return "Invalid realtime configuration: \(message)"
        case .notConnected:
            return "The realtime socket is not connected."
        case .connectionClosed(let code):
            return "The realtime socket closed with code \(code.rawValue)."
        case .decodingFailed(let message):
            return "Failed to decode a realtime frame: \(message)"
        case .encodingFailed(let message):
            return "Failed to encode a realtime frame: \(message)"
        case .server:
            return "The realtime server reported an error."
        case .pingTimedOut:
            return "The realtime heartbeat ping timed out."
        }
    }
}
