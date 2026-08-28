import Foundation

/// Handle for one realtime channel multiplexed on the shared socket.
///
/// ```swift
/// let lobby = await client.channel("lobby", options: ChannelOptions(presence: true))
/// for await event in await lobby.events {
///     // handle event
/// }
/// try await lobby.send(["text": "hello"])
/// ```
///
/// Dropping the `events` iterator does **not** leave the channel. Call ``leave()``.
public actor XanoRealtimeChannel {
    // MARK: - Properties

    /// Channel name sent in envelope `options.channel`.
    public let name: String
    /// Join and lifecycle options for this channel.
    public let options: ChannelOptions
    /// Filtered events for this channel.
    public let events: AsyncStream<RealtimeEvent>
    /// Continuation that feeds ``events``.
    private let eventsContinuation: AsyncStream<RealtimeEvent>.Continuation
    /// Cached presence list from `presence_full` / `presence_update`.
    private var presenceCache: [RealtimePeer] = []
    /// Outbound router (the owning client).
    private let router: any ChannelOutboundRouting
    /// Envelope builder.
    private let coder: RealtimeCoder
    /// Whether ``leave()`` has already run.
    private var hasLeft = false

    // MARK: - Initialization

    /// Creates a channel handle.
    ///
    /// - Parameters:
    ///   - name: Channel name.
    ///   - options: Join options.
    ///   - router: Owning client.
    ///   - bufferSize: Newest-event buffer size.
    ///   - coder: Envelope builder.
    init(
        name: String,
        options: ChannelOptions,
        router: any ChannelOutboundRouting,
        bufferSize: Int,
        coder: RealtimeCoder = .shared
    ) {
        self.name = name
        self.options = options
        self.router = router
        self.coder = coder
        let pair = AsyncStreamFactory.make(
            of: RealtimeEvent.self,
            bufferingPolicy: .bufferingNewest(max(bufferSize, 1))
        )
        self.events = pair.stream
        self.eventsContinuation = pair.continuation
    }

    // MARK: - Public API

    /// Snapshot of the last presence list received for this channel.
    public var presence: [RealtimePeer] {
        presenceCache
    }

    /// Sends an application payload on this channel.
    ///
    /// - Parameters:
    ///   - payload: `Encodable` body placed in `payload`.
    ///   - authenticated: Restrict delivery to authenticated members.
    /// - Throws: Encoding or connection errors.
    public func send(_ payload: some Encodable, authenticated: Bool = false) async throws {
        let body = try JSONValue(encoding: payload)
        try await sendValue(body, authenticated: authenticated, socketId: nil)
    }

    /// Sends a private message to one peer on this channel.
    ///
    /// - Parameters:
    ///   - payload: `Encodable` body.
    ///   - socketId: Target peer socket identifier.
    /// - Throws: Encoding or connection errors.
    public func message(_ payload: some Encodable, to socketId: String) async throws {
        let body = try JSONValue(encoding: payload)
        try await sendValue(body, authenticated: false, socketId: socketId)
    }

    /// Requests a history batch for this channel.
    ///
    /// - Throws: Connection errors.
    public func requestHistory() async throws {
        try await router.ensureConnected()
        try await router.sendEnvelope(coder.history(channel: name))
    }

    /// Sends `leave` and unregisters this channel. Does not finish ``events``.
    public func leave() async {
        guard !hasLeft else {
            return
        }
        hasLeft = true
        do {
            try await router.sendEnvelope(coder.leave(channel: name))
        } catch {
            eventsContinuation.yield(.error(mapSendError(error)))
        }
        await router.channelDidLeave(name)
    }

    // MARK: - Package API

    /// Applies an inbound envelope that already belongs to this channel (or is global).
    ///
    /// - Parameter envelope: Inbound envelope.
    func deliver(_ envelope: RealtimeEnvelope) {
        applyPresence(from: envelope)
        eventsContinuation.yield(envelope.asEvent())
    }

    /// Publishes a transport or coding failure to this channel's stream.
    ///
    /// - Parameter error: Failure to publish.
    func deliverFailure(_ error: XanoRealtimeError) {
        eventsContinuation.yield(.error(error))
    }

    /// Join envelope for the current options.
    var joinEnvelope: RealtimeEnvelope {
        coder.join(channel: name, history: options.history, presence: options.presence)
    }

    /// Whether foreground reconnect should request history.
    var shouldCatchUpOnForeground: Bool {
        options.catchUpOnForeground
    }

    // MARK: - Private Helpers

    /// Sends a JSON value as a `message` action.
    ///
    /// - Parameters:
    ///   - payload: JSON body.
    ///   - authenticated: Auth filter.
    ///   - socketId: Optional private-message target.
    /// - Throws: Connection errors.
    private func sendValue(
        _ payload: JSONValue,
        authenticated: Bool,
        socketId: String?
    ) async throws {
        try await router.ensureConnected()
        let envelope = coder.message(
            channel: name,
            payload: payload,
            authenticated: authenticated ? true : nil,
            socketId: socketId
        )
        try await router.sendEnvelope(envelope)
    }

    /// Updates ``presenceCache`` from presence envelopes before the event is emitted.
    ///
    /// - Parameter envelope: Inbound envelope.
    private func applyPresence(from envelope: RealtimeEnvelope) {
        switch envelope.action {
        case .presenceFull:
            guard let payload = envelope.payload else {
                return
            }
            do {
                let decoded = try payload.decode(as: PresenceFullPayload.self)
                presenceCache = decoded.presence
            } catch {
                eventsContinuation.yield(.error(.decodingFailed(String(describing: error))))
            }
        case .presenceUpdate:
            guard let payload = envelope.payload else {
                return
            }
            do {
                let decoded = try payload.decode(as: PresenceUpdatePayload.self)
                applyPresenceUpdate(decoded)
            } catch {
                eventsContinuation.yield(.error(.decodingFailed(String(describing: error))))
            }
        default:
            break
        }
    }

    /// Applies a single join/leave delta to ``presenceCache``.
    ///
    /// - Parameter update: Decoded presence update.
    private func applyPresenceUpdate(_ update: PresenceUpdatePayload) {
        switch update.action {
        case .join:
            if !presenceCache.contains(where: { $0.socketId == update.presence.socketId }) {
                presenceCache.append(update.presence)
            }
        case .leave:
            presenceCache.removeAll { $0.socketId == update.presence.socketId }
        }
    }

    /// Maps a thrown send error into ``XanoRealtimeError``.
    ///
    /// - Parameter error: Thrown error.
    /// - Returns: Domain error.
    private func mapSendError(_ error: Error) -> XanoRealtimeError {
        if let domain = error as? XanoRealtimeError {
            return domain
        }
        return .encodingFailed(String(describing: error))
    }
}
