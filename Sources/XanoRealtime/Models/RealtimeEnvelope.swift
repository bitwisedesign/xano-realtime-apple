import Foundation

/// Universal Xano Realtime JSON envelope used in both directions.
///
/// Matches the JS SDK shape `{ action, client?, options?, payload }`.
public struct RealtimeEnvelope: Codable, Sendable, Equatable {
    /// Action this envelope carries.
    public var action: RealtimeAction
    /// Sender identity, when the server includes one.
    public var client: RealtimePeer?
    /// Channel, socket, and auth options.
    public var options: RealtimeActionOptions?
    /// Action-specific body; `null` is encoded when omitted.
    public var payload: JSONValue?

    /// Creates an envelope.
    ///
    /// - Parameters:
    ///   - action: Wire action.
    ///   - client: Optional sender identity.
    ///   - options: Optional action options.
    ///   - payload: Optional payload; use ``JSONValue/null`` for an explicit JSON null.
    public init(
        action: RealtimeAction,
        client: RealtimePeer? = nil,
        options: RealtimeActionOptions? = nil,
        payload: JSONValue? = nil
    ) {
        self.action = action
        self.client = client
        self.options = options
        self.payload = payload
    }

    /// Decodes an envelope, mapping an explicit JSON `null` payload to ``JSONValue/null``.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        action = try container.decode(RealtimeAction.self, forKey: .action)
        client = try container.decodeIfPresent(RealtimePeer.self, forKey: .client)
        options = try container.decodeIfPresent(RealtimeActionOptions.self, forKey: .options)
        if container.contains(.payload) {
            payload = try container.decode(JSONValue.self, forKey: .payload)
        } else {
            payload = nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case action
        case client
        case options
        case payload
    }
}
