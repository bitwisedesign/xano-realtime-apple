import Foundation

/// Encodes and decodes Xano Realtime envelopes and builds outbound actions.
///
/// Mirrors `realtime-build-action.util.ts` in the official JS SDK.
struct RealtimeCoder: Sendable {
    /// Shared coder using default JSON encoder and decoder settings.
    static let shared = RealtimeCoder()

    /// Encodes an envelope to UTF-8 JSON data.
    ///
    /// - Parameter envelope: Envelope to encode.
    /// - Returns: JSON bytes.
    /// - Throws: ``XanoRealtimeError/encodingFailed(_:)`` when encoding fails.
    func encode(_ envelope: RealtimeEnvelope) throws -> Data {
        let encoder = JSONEncoder()
        do {
            return try encoder.encode(envelope)
        } catch {
            throw XanoRealtimeError.encodingFailed(String(describing: error))
        }
    }

    /// Decodes an envelope from UTF-8 JSON data.
    ///
    /// Frames without an `action` field are rejected.
    ///
    /// - Parameter data: Raw WebSocket text payload as data.
    /// - Returns: The decoded envelope.
    /// - Throws: ``XanoRealtimeError/decodingFailed(_:)`` when decoding fails.
    func decode(from data: Data) throws -> RealtimeEnvelope {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(RealtimeEnvelope.self, from: data)
        } catch {
            throw XanoRealtimeError.decodingFailed(String(describing: error))
        }
    }

    /// Decodes an envelope from a WebSocket text frame.
    ///
    /// - Parameter text: UTF-8 JSON string.
    /// - Returns: The decoded envelope.
    /// - Throws: ``XanoRealtimeError/decodingFailed(_:)`` when the string is not UTF-8 JSON.
    func decode(from text: String) throws -> RealtimeEnvelope {
        guard let data = text.data(using: .utf8) else {
            throw XanoRealtimeError.decodingFailed("Inbound text is not valid UTF-8")
        }
        return try decode(from: data)
    }

    /// Builds a `join` envelope for `channel`.
    ///
    /// - Parameters:
    ///   - channel: Channel name.
    ///   - history: Request history replay.
    ///   - presence: Request presence updates.
    /// - Returns: Outbound join envelope.
    func join(channel: String, history: Bool, presence: Bool) -> RealtimeEnvelope {
        let payload: JSONValue
        do {
            payload = try JSONValue(encoding: JoinPayload(history: history, presence: presence))
        } catch {
            payload = .object([
                "history": .bool(history),
                "presence": .bool(presence)
            ])
        }
        return RealtimeEnvelope(
            action: .join,
            options: RealtimeActionOptions(channel: channel),
            payload: payload
        )
    }

    /// Builds a `leave` envelope for `channel`.
    ///
    /// - Parameter channel: Channel name.
    /// - Returns: Outbound leave envelope with a null payload.
    func leave(channel: String) -> RealtimeEnvelope {
        RealtimeEnvelope(
            action: .leave,
            options: RealtimeActionOptions(channel: channel),
            payload: .null
        )
    }

    /// Builds a `message` envelope.
    ///
    /// - Parameters:
    ///   - channel: Channel name.
    ///   - payload: Application JSON body.
    ///   - authenticated: Restrict delivery to authenticated members.
    ///   - socketId: Optional target peer for a private message.
    /// - Returns: Outbound message envelope.
    func message(
        channel: String,
        payload: JSONValue,
        authenticated: Bool? = nil,
        socketId: String? = nil
    ) -> RealtimeEnvelope {
        RealtimeEnvelope(
            action: .message,
            options: RealtimeActionOptions(
                channel: channel,
                socketId: socketId,
                authenticated: authenticated
            ),
            payload: payload
        )
    }

    /// Builds a `history` request envelope for `channel`.
    ///
    /// - Parameter channel: Channel name.
    /// - Returns: Outbound history envelope with a null payload.
    func history(channel: String) -> RealtimeEnvelope {
        RealtimeEnvelope(
            action: .history,
            options: RealtimeActionOptions(channel: channel),
            payload: .null
        )
    }
}

extension RealtimeEnvelope {
    /// Maps this envelope to a public ``RealtimeEvent``.
    ///
    /// - Returns: The corresponding stream event.
    func asEvent() -> RealtimeEvent {
        switch action {
        case .connectionStatus:
            return connectionStatusEvent()
        case .message:
            return .message(
                RealtimeMessage(
                    payload: payload ?? .null,
                    sender: client,
                    options: options
                )
            )
        case .presenceFull:
            return presenceFullEvent()
        case .presenceUpdate:
            return presenceUpdateEvent()
        case .history:
            return .history(payload ?? .null)
        case .error:
            return .error(.server(payload ?? .null))
        case .event, .join, .leave, .unknown:
            return .unhandled(action: action.rawValue, payload: payload)
        }
    }

    /// Converts a `connection_status` payload into a connected or disconnected event.
    ///
    /// - Returns: Mapped event, or ``RealtimeEvent/unhandled(action:payload:)`` when the payload is not recognized.
    private func connectionStatusEvent() -> RealtimeEvent {
        guard let payload else {
            return .unhandled(action: action.rawValue, payload: nil)
        }
        do {
            let decoded = try payload.decode(as: ConnectionStatusPayload.self)
            switch decoded.status {
            case .connected:
                return .connected
            case .disconnected:
                return .disconnected
            }
        } catch {
            return .error(.decodingFailed(String(describing: error)))
        }
    }

    /// Converts a `presence_full` payload into a presence snapshot event.
    ///
    /// - Returns: Mapped event, or a decode error event.
    private func presenceFullEvent() -> RealtimeEvent {
        guard let payload else {
            return .error(.decodingFailed("presence_full payload was empty"))
        }
        do {
            let decoded = try payload.decode(as: PresenceFullPayload.self)
            return .presenceFull(decoded.presence)
        } catch {
            return .error(.decodingFailed(String(describing: error)))
        }
    }

    /// Converts a `presence_update` payload into a presence delta event.
    ///
    /// - Returns: Mapped event, or a decode error event.
    private func presenceUpdateEvent() -> RealtimeEvent {
        guard let payload else {
            return .error(.decodingFailed("presence_update payload was empty"))
        }
        do {
            let decoded = try payload.decode(as: PresenceUpdatePayload.self)
            return .presenceUpdate(action: decoded.action, peer: decoded.presence)
        } catch {
            return .error(.decodingFailed(String(describing: error)))
        }
    }
}
