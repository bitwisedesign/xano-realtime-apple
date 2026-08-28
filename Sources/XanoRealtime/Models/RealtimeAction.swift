import Foundation

/// Wire-level action string used in Xano Realtime envelopes.
///
/// Unknown future actions decode as ``unknown(_:)`` so the SDK stays
/// forward-compatible with server additions.
public enum RealtimeAction: Sendable, Hashable {
    /// Socket open or close status (`connection_status`).
    case connectionStatus
    /// Server-reported error (`error`).
    case error
    /// Generic server event (`event`).
    case event
    /// History batch (`history`).
    case history
    /// Channel join (`join`).
    case join
    /// Channel leave (`leave`).
    case leave
    /// Application message (`message`).
    case message
    /// Full presence snapshot (`presence_full`).
    case presenceFull
    /// Incremental presence change (`presence_update`).
    case presenceUpdate
    /// Action string the SDK does not recognize.
    case unknown(String)

    /// Canonical wire string for this action.
    public var rawValue: String {
        switch self {
        case .connectionStatus: return "connection_status"
        case .error: return "error"
        case .event: return "event"
        case .history: return "history"
        case .join: return "join"
        case .leave: return "leave"
        case .message: return "message"
        case .presenceFull: return "presence_full"
        case .presenceUpdate: return "presence_update"
        case .unknown(let value): return value
        }
    }

    /// Creates an action from a wire string, using ``unknown(_:)`` for unrecognized values.
    ///
    /// - Parameter rawValue: Action string from a JSON envelope.
    public init(rawValue: String) {
        switch rawValue {
        case "connection_status": self = .connectionStatus
        case "error": self = .error
        case "event": self = .event
        case "history": self = .history
        case "join": self = .join
        case "leave": self = .leave
        case "message": self = .message
        case "presence_full": self = .presenceFull
        case "presence_update": self = .presenceUpdate
        default: self = .unknown(rawValue)
        }
    }
}

extension RealtimeAction: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
