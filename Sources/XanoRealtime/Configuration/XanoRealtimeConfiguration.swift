import Foundation

/// Connection settings for a Xano Realtime client.
///
/// The socket URL is `wss://{host}/rt/{connectionCanonical}`. The host is taken
/// from ``instanceBaseUrl`` (preferred) or ``apiGroupBaseUrl``. Any path on those
/// HTTP URLs is discarded, matching the official JS SDK.
///
/// ```swift
/// let configuration = try XanoRealtimeConfiguration(
///     instanceBaseUrl: URL(string: "https://x8ki-letl-twmt.n7.xano.io")!,
///     connectionCanonical: "1lK90n16tnnylJpJ0Xa7Km6_KxA",
///     realtimeAuthToken: token
/// )
/// ```
public struct XanoRealtimeConfiguration: Sendable, Equatable {
    /// Preferred HTTP origin used only for its hostname.
    public var instanceBaseUrl: URL?
    /// Fallback HTTP origin used only for its hostname when ``instanceBaseUrl`` is missing.
    public var apiGroupBaseUrl: URL?
    /// Current connection identifier (`realtimeConnectionCanonical`).
    public var connectionCanonical: String
    /// Deprecated connection hash used only when ``connectionCanonical`` is empty.
    public var connectionHash: String?
    /// JWT passed as the WebSocket subprotocol (`Sec-WebSocket-Protocol`).
    public var realtimeAuthToken: String?
    /// Interval between heartbeat pings; `nil` disables the heartbeat.
    public var pingInterval: Duration?
    /// How long to wait for a pong before treating the socket as dead.
    public var pingTimeout: Duration
    /// When `true`, outbound envelopes are queued while disconnected and flushed on reconnect.
    public var queueOfflineActions: Bool
    /// When `true` on iOS, observe app foreground/background automatically.
    public var automaticLifecycleHandling: Bool
    /// Per-stream newest-event buffer size.
    public var eventBufferSize: Int

    /// Creates a configuration.
    ///
    /// - Parameters:
    ///   - instanceBaseUrl: Preferred origin for the hostname.
    ///   - apiGroupBaseUrl: Fallback origin for the hostname.
    ///   - connectionCanonical: Realtime connection identifier.
    ///   - connectionHash: Deprecated fallback identifier.
    ///   - realtimeAuthToken: JWT used as the WebSocket subprotocol.
    ///   - pingInterval: Heartbeat interval; `nil` disables pings. Defaults to 20 seconds.
    ///   - pingTimeout: Pong wait bound. Defaults to 10 seconds.
    ///   - queueOfflineActions: Queue outbound actions while disconnected. Defaults to `false`.
    ///   - automaticLifecycleHandling: Opt into the iOS UIKit lifecycle bridge. Defaults to `false`.
    ///   - eventBufferSize: Newest-event buffer for streams. Defaults to 64.
    public init(
        instanceBaseUrl: URL? = nil,
        apiGroupBaseUrl: URL? = nil,
        connectionCanonical: String,
        connectionHash: String? = nil,
        realtimeAuthToken: String? = nil,
        pingInterval: Duration? = .seconds(20),
        pingTimeout: Duration = .seconds(10),
        queueOfflineActions: Bool = false,
        automaticLifecycleHandling: Bool = false,
        eventBufferSize: Int = 64
    ) {
        self.instanceBaseUrl = instanceBaseUrl
        self.apiGroupBaseUrl = apiGroupBaseUrl
        self.connectionCanonical = connectionCanonical
        self.connectionHash = connectionHash
        self.realtimeAuthToken = realtimeAuthToken
        self.pingInterval = pingInterval
        self.pingTimeout = pingTimeout
        self.queueOfflineActions = queueOfflineActions
        self.automaticLifecycleHandling = automaticLifecycleHandling
        self.eventBufferSize = eventBufferSize
    }

    /// Builds `wss://{host}/rt/{canonical}` from this configuration.
    ///
    /// - Returns: The WebSocket URL.
    /// - Throws: ``XanoRealtimeError/invalidConfiguration(_:)`` when host or canonical is missing.
    public func makeConnectionURL() throws -> URL {
        let hostSource = instanceBaseUrl ?? apiGroupBaseUrl
        guard let hostSource else {
            throw XanoRealtimeError.invalidConfiguration(
                "Set instanceBaseUrl or apiGroupBaseUrl before connecting"
            )
        }
        guard let host = hostSource.host, !host.isEmpty else {
            throw XanoRealtimeError.invalidConfiguration(
                "instanceBaseUrl or apiGroupBaseUrl must include a host"
            )
        }
        let identifier = resolvedConnectionIdentifier
        guard !identifier.isEmpty else {
            throw XanoRealtimeError.invalidConfiguration(
                "Set connectionCanonical (or connectionHash) before connecting"
            )
        }
        var components = URLComponents()
        components.scheme = "wss"
        components.host = host
        components.path = "/rt/\(identifier)"
        guard let url = components.url else {
            throw XanoRealtimeError.invalidConfiguration("Could not build the realtime URL")
        }
        return url
    }

    /// WebSocket subprotocols to send; empty when no auth token is set.
    public var webSocketProtocols: [String] {
        guard let realtimeAuthToken, !realtimeAuthToken.isEmpty else {
            return []
        }
        return [realtimeAuthToken]
    }

    /// Heartbeat policy derived from ping interval and timeout.
    var heartbeatPolicy: HeartbeatPolicy {
        HeartbeatPolicy(interval: pingInterval, timeout: pingTimeout)
    }

    /// Canonical identifier, falling back to the deprecated hash.
    var resolvedConnectionIdentifier: String {
        if !connectionCanonical.isEmpty {
            return connectionCanonical
        }
        return connectionHash ?? ""
    }
}

/// Options applied when joining a channel.
public struct ChannelOptions: Sendable, Equatable {
    /// Request history replay after join.
    public var history: Bool
    /// Request presence snapshots and updates.
    public var presence: Bool
    /// Queue this channel's outbound actions while disconnected.
    public var queueOfflineActions: Bool
    /// Request history automatically after returning to the foreground.
    public var catchUpOnForeground: Bool

    /// Creates channel options.
    ///
    /// - Parameters:
    ///   - history: Request history. Defaults to `false`.
    ///   - presence: Request presence. Defaults to `false`.
    ///   - queueOfflineActions: Queue sends while offline. Defaults to `false`.
    ///   - catchUpOnForeground: Request history after `enterForeground()`. Defaults to `false`.
    public init(
        history: Bool = false,
        presence: Bool = false,
        queueOfflineActions: Bool = false,
        catchUpOnForeground: Bool = false
    ) {
        self.history = history
        self.presence = presence
        self.queueOfflineActions = queueOfflineActions
        self.catchUpOnForeground = catchUpOnForeground
    }
}
