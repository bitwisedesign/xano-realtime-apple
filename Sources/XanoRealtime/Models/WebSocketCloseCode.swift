import Foundation

/// RFC 6455 close code used by the transport port (integer, not `URLSession` types).
public struct WebSocketCloseCode: RawRepresentable, Sendable, Equatable, Hashable {
    /// Numeric close code.
    public let rawValue: Int

    /// Creates a close code from its numeric value.
    ///
    /// - Parameter rawValue: RFC 6455 or application close code.
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Normal closure (`1000`). Does not trigger auto-reconnect.
    public static let normalClosure = WebSocketCloseCode(rawValue: 1000)
    /// Abnormal closure (`1006`).
    public static let abnormalClosure = WebSocketCloseCode(rawValue: 1006)
    /// Internal error (`1011`).
    public static let internalError = WebSocketCloseCode(rawValue: 1011)
    /// Service restart (`1012`).
    public static let serviceRestart = WebSocketCloseCode(rawValue: 1012)
    /// Try again later (`1013`).
    public static let tryAgainLater = WebSocketCloseCode(rawValue: 1013)
    /// Bad gateway (`1014`).
    public static let badGateway = WebSocketCloseCode(rawValue: 1014)
    /// SDK-internal reconnect request (`4000`), matching the JS SDK.
    public static let reconnectRequested = WebSocketCloseCode(rawValue: 4000)
    /// Used when the transport did not report a code.
    public static let unknown = WebSocketCloseCode(rawValue: -1)

    /// Whether the JS SDK would schedule another connection attempt for this code.
    public var shouldReconnect: Bool {
        switch rawValue {
        case 1006, 1011, 1012, 1013, 1014, 4000:
            return true
        default:
            return false
        }
    }
}
