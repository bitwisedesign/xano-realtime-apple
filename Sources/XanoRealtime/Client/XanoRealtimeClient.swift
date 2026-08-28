import Foundation

/// Facade for a Xano Realtime session: one socket, many channels.
///
/// Create one client per session, obtain channels with ``channel(_:options:)``, and
/// consume ``XanoRealtimeChannel/events``.
///
/// ```swift
/// let client = XanoRealtimeClient(configuration: configuration)
/// let lobby = await client.channel("lobby", options: ChannelOptions(presence: true))
/// Task {
///     for await event in await lobby.events {
///         print(event)
///     }
/// }
/// ```
public actor XanoRealtimeClient {
    // MARK: - Properties

    /// Connection manager.
    private let connection: WebSocketConnection
    /// Live channels keyed by name.
    private var channels: [String: XanoRealtimeChannel] = [:]
    /// Channel names that have been sent `join` on the current socket.
    private var joinedChannelNames: Set<String> = []
    /// Whether ``joinAllChannels()`` has finished for the current connected socket.
    private var hasFinishedConnectJoin = false
    /// Configuration snapshot used when constructing new channels.
    private let configuration: XanoRealtimeConfiguration
    /// Fan-out task that reads connection events.
    private var fanOutTask: Task<Void, Never>?
    /// Set when ``enterForeground()`` should request history on catch-up channels.
    private var pendingForegroundCatchUp = false
    /// Connection-state stream from the connection actor.
    public let connectionState: AsyncStream<ConnectionState>
    /// Optional iOS lifecycle observer.
    private var lifecycleBridge: LifecycleBridge?
    /// True while a lifecycle-bridge attach Task is outstanding.
    private var isAttachingLifecycleBridge = false

    // MARK: - Initialization

    /// Creates a client with the production `URLSession` adapter.
    ///
    /// - Parameter configuration: Instance URL, connection canonical, and options.
    public init(configuration: XanoRealtimeConfiguration) {
        let provider = URLSessionWebSocketProvider(pingTimeout: configuration.pingTimeout)
        self.init(
            configuration: configuration,
            provider: provider,
            delay: ContinuousClockDelay()
        )
    }

    /// Creates a client with an injected transport for tests.
    ///
    /// - Parameters:
    ///   - configuration: Instance URL, connection canonical, and options.
    ///   - provider: Transport factory.
    ///   - delay: Reconnect sleeper.
    init(
        configuration: XanoRealtimeConfiguration,
        provider: any WebSocketProviding,
        delay: any DelayProviding = ImmediateDelay()
    ) {
        self.configuration = configuration
        let connection = WebSocketConnection(
            configuration: configuration,
            provider: provider,
            delay: delay
        )
        self.connection = connection
        self.connectionState = connection.stateStream
    }

    // MARK: - Public API

    /// Returns the existing channel named `name`, or creates and registers one.
    ///
    /// The first channel triggers ``connect()``. If the socket is already connected
    /// and the connect-time join pass has finished, this sends `join` for the new
    /// channel. Reconnecting later re-sends `join` for every registered channel.
    ///
    /// - Parameters:
    ///   - name: Channel name.
    ///   - options: Join and catch-up options. Ignored when the channel already exists.
    /// - Returns: Channel handle.
    public func channel(_ name: String, options: ChannelOptions = ChannelOptions()) async -> XanoRealtimeChannel {
        if let existing = channels[name] {
            return existing
        }
        let handle = XanoRealtimeChannel(
            name: name,
            options: options,
            router: self,
            bufferSize: configuration.eventBufferSize
        )
        channels[name] = handle
        startServicesIfNeeded()
        if await connection.connectionState == .connected, hasFinishedConnectJoin {
            await sendJoin(for: handle)
        } else {
            Task {
                do {
                    try await connection.connect()
                } catch let error as XanoRealtimeError {
                    await handle.deliverFailure(error)
                } catch {
                    await handle.deliverFailure(.invalidConfiguration(String(describing: error)))
                }
            }
        }
        return handle
    }

    /// Opens the multiplexed socket.
    ///
    /// - Throws: ``XanoRealtimeError/invalidConfiguration(_:)`` when the URL cannot be built.
    public func connect() async throws {
        startServicesIfNeeded()
        try await connection.connect()
    }

    /// Closes the socket with code `1000` and does not reconnect.
    public func disconnect() async {
        await connection.disconnect()
    }

    /// Replaces the realtime auth token and reconnects with close code `4000`.
    ///
    /// - Parameter token: New JWT, or `nil` to clear the subprotocol.
    public func setAuthToken(_ token: String?) async {
        await connection.setAuthToken(token)
    }

    /// Suspends the socket for backgrounding (normal close, no reconnect).
    public func enterBackground() async {
        await connection.enterBackground()
    }

    /// Reopens the socket after foregrounding and optionally requests history.
    public func enterForeground() async {
        startServicesIfNeeded()
        pendingForegroundCatchUp = true
        do {
            try await connection.enterForeground()
        } catch let error as XanoRealtimeError {
            await broadcastFailure(error)
        } catch {
            await broadcastFailure(.invalidConfiguration(String(describing: error)))
        }
    }

    /// Snapshot of the connection state machine.
    public var currentConnectionState: ConnectionState {
        get async {
            await connection.connectionState
        }
    }

    // MARK: - Private Helpers

    /// Starts fan-out and the optional UIKit lifecycle bridge once.
    private func startServicesIfNeeded() {
        if fanOutTask == nil {
            fanOutTask = Task {
                await self.routeConnectionEvents()
            }
        }
        if configuration.automaticLifecycleHandling, lifecycleBridge == nil, !isAttachingLifecycleBridge {
            isAttachingLifecycleBridge = true
            Task {
                await self.attachLifecycleBridge()
            }
        }
    }

    /// Reads connection events and fans them out to channels.
    private func routeConnectionEvents() async {
        for await event in connection.events {
            switch event {
            case .envelope(let envelope):
                await routeEnvelope(envelope)
            case .failure(let error):
                await broadcastFailure(error)
            }
        }
    }

    /// Routes one envelope: global status to every channel, otherwise by `options.channel`.
    ///
    /// - Parameter envelope: Inbound or synthetic envelope.
    private func routeEnvelope(_ envelope: RealtimeEnvelope) async {
        if envelope.action == .connectionStatus {
            await handleConnectionStatus(envelope)
            await deliverToAll(envelope)
            return
        }
        guard let channelName = envelope.options?.channel else {
            await deliverToAll(envelope)
            return
        }
        await channels[channelName]?.deliver(envelope)
    }

    /// Re-joins channels and optionally requests history after a connected status.
    ///
    /// - Parameter envelope: Connection-status envelope.
    private func handleConnectionStatus(_ envelope: RealtimeEnvelope) async {
        guard case .connected = envelope.asEvent() else {
            hasFinishedConnectJoin = false
            joinedChannelNames.removeAll()
            return
        }
        hasFinishedConnectJoin = false
        joinedChannelNames.removeAll()
        await joinAllChannels()
        hasFinishedConnectJoin = true
        await joinAllChannels()
        if pendingForegroundCatchUp {
            pendingForegroundCatchUp = false
            await requestCatchUpHistory()
        }
    }

    /// Sends `join` for every registered channel that is not yet joined on this socket.
    private func joinAllChannels() async {
        let live = Array(channels.values)
        for handle in live {
            await sendJoin(for: handle)
        }
    }

    /// Sends `join` for `handle` unless this socket already joined that channel.
    ///
    /// - Parameter handle: Channel to join.
    private func sendJoin(for handle: XanoRealtimeChannel) async {
        let name = handle.name
        guard !joinedChannelNames.contains(name) else {
            return
        }
        joinedChannelNames.insert(name)
        let envelope = await handle.joinEnvelope
        do {
            try await connection.send(envelope)
        } catch let error as XanoRealtimeError {
            joinedChannelNames.remove(name)
            await handle.deliverFailure(error)
        } catch {
            joinedChannelNames.remove(name)
            await handle.deliverFailure(.encodingFailed(String(describing: error)))
        }
    }

    /// Requests history for channels that opted into ``ChannelOptions/catchUpOnForeground``.
    private func requestCatchUpHistory() async {
        let live = Array(channels.values)
        for handle in live {
            let shouldCatchUp = await handle.shouldCatchUpOnForeground
            guard shouldCatchUp else {
                continue
            }
            do {
                try await handle.requestHistory()
            } catch let error as XanoRealtimeError {
                await handle.deliverFailure(error)
            } catch {
                await handle.deliverFailure(.encodingFailed(String(describing: error)))
            }
        }
    }

    /// Delivers `envelope` to every registered channel.
    ///
    /// - Parameter envelope: Global envelope.
    private func deliverToAll(_ envelope: RealtimeEnvelope) async {
        for handle in channels.values {
            await handle.deliver(envelope)
        }
    }

    /// Publishes `error` on every registered channel.
    ///
    /// - Parameter error: Failure to publish.
    private func broadcastFailure(_ error: XanoRealtimeError) async {
        for handle in channels.values {
            await handle.deliverFailure(error)
        }
    }

    /// Attaches the opt-in UIKit lifecycle bridge when compiling with UIKit.
    private func attachLifecycleBridge() async {
        defer { isAttachingLifecycleBridge = false }
        #if canImport(UIKit) && os(iOS)
        let bridge = await MainActor.run {
            LifecycleBridge(client: self)
        }
        lifecycleBridge = bridge
        #else
        lifecycleBridge = LifecycleBridge(client: self)
        #endif
    }
}

extension XanoRealtimeClient: ChannelOutboundRouting {
    /// Writes `envelope` through the connection actor.
    ///
    /// - Parameter envelope: Outbound action.
    /// - Throws: Connection errors.
    func sendEnvelope(_ envelope: RealtimeEnvelope) async throws {
        try await connection.send(envelope)
    }

    /// Opens the socket if needed.
    ///
    /// - Throws: Configuration errors.
    func ensureConnected() async throws {
        try await connection.connect()
    }

    /// Drops a left channel and disconnects when none remain.
    ///
    /// - Parameter name: Channel that left.
    func channelDidLeave(_ name: String) async {
        channels.removeValue(forKey: name)
        joinedChannelNames.remove(name)
        if channels.isEmpty {
            await connection.disconnect()
        }
    }
}
