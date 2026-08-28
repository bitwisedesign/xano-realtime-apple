import Foundation

/// Universal Xano Realtime JSON envelope used in both directions.
///
/// Matches the JS SDK shape `{ action, client?, options?, payload }`.
struct RealtimeEnvelope: Codable, Sendable, Equatable {
    /// Action this envelope carries.
    var action: RealtimeAction
    /// Sender identity, when the server includes one.
    var client: RealtimePeer?
    /// Channel, socket, and auth options.
    var options: RealtimeActionOptions?
    /// Action-specific body; `null` is encoded when omitted.
    var payload: JSONValue?

    /// Creates an envelope.
    ///
    /// - Parameters:
    ///   - action: Wire action.
    ///   - client: Optional sender identity.
    ///   - options: Optional action options.
    ///   - payload: Optional payload; use ``JSONValue/null`` for an explicit JSON null.
    init(
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
    init(from decoder: Decoder) throws {
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

    /// Encodes the envelope, always emitting `payload` as JSON `null` when absent.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(action, forKey: .action)
        try container.encodeIfPresent(client, forKey: .client)
        try container.encodeIfPresent(options, forKey: .options)
        try container.encode(payload ?? .null, forKey: .payload)
    }

    enum CodingKeys: String, CodingKey {
        case action
        case client
        case options
        case payload
    }
}
