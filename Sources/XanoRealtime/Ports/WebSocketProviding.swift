import Foundation

/// Transport-agnostic WebSocket text or binary frame.
public enum WebSocketMessage: Sendable, Equatable {
    /// UTF-8 text frame.
    case string(String)
    /// Binary frame.
    case data(Data)
}

/// Receives socket open and close notifications from a transport adapter.
public protocol WebSocketLifecycleSink: Sendable {
    /// Called when the adapter reports the socket is open.
    func webSocketDidOpen() async
    /// Called when the adapter reports the socket is closed.
    ///
    /// - Parameters:
    ///   - code: Close code.
    ///   - reason: Optional close reason bytes.
    func webSocketDidClose(code: WebSocketCloseCode, reason: Data?) async
}

/// A single WebSocket conversation created by ``WebSocketProviding``.
///
/// Implementations must not expose `URLSession` types. Domain code depends only on this port.
public protocol WebSocketTasking: Sendable {
    /// Starts the handshake.
    func resume() async
    /// Waits for the next inbound frame.
    ///
    /// - Returns: The next message.
    /// - Throws: A transport error when the socket fails or is cancelled.
    func receive() async throws -> WebSocketMessage
    /// Sends an outbound frame.
    ///
    /// - Parameter message: Text or binary payload.
    /// - Throws: A transport error when the write fails.
    func send(_ message: WebSocketMessage) async throws
    /// Sends a WebSocket ping and waits for the corresponding pong.
    ///
    /// - Throws: A transport error when the ping fails or the pong never arrives.
    func sendPing() async throws
    /// Cancels the socket with `code`.
    ///
    /// - Parameters:
    ///   - code: Close code to send.
    ///   - reason: Optional close reason.
    func cancel(with code: WebSocketCloseCode, reason: Data?) async
}

/// Factory for WebSocket conversations.
///
/// Production code uses ``URLSessionWebSocketProvider``. Tests inject a fake.
public protocol WebSocketProviding: Sendable {
    /// Creates a task for `url` using `protocols` as `Sec-WebSocket-Protocol` values.
    ///
    /// - Parameters:
    ///   - url: Realtime WebSocket URL.
    ///   - protocols: Subprotocols; typically a single JWT.
    ///   - sink: Open/close observer.
    /// - Returns: A task that has not been resumed yet.
    func makeTask(
        url: URL,
        protocols: [String],
        sink: WebSocketLifecycleSink
    ) async -> any WebSocketTasking
}

/// Suspends for a duration; injectable so reconnect tests do not wait on the wall clock.
public protocol DelayProviding: Sendable {
    /// Waits for `duration` or until cancelled.
    ///
    /// - Parameter duration: Requested delay.
    /// - Throws: `CancellationError` when the waiting task is cancelled.
    func wait(_ duration: Duration) async throws
}

/// Production delay that uses `Task.sleep`.
public struct ContinuousClockDelay: DelayProviding {
    /// Creates a clock-based delay.
    public init() {}

    /// Sleeps for `duration` using the cooperative clock.
    ///
    /// - Parameter duration: Sleep length.
    /// - Throws: `CancellationError` if the task is cancelled.
    public func wait(_ duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

/// Test delay that returns immediately after checking cancellation.
public struct ImmediateDelay: DelayProviding {
    /// Creates an immediate delay.
    public init() {}

    /// Returns immediately unless the task is already cancelled.
    ///
    /// - Parameter duration: Ignored.
    /// - Throws: `CancellationError` if the task is cancelled.
    public func wait(_ duration: Duration) async throws {
        try Task.checkCancellation()
    }
}
