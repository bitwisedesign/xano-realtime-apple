import Foundation

/// Production WebSocket adapter backed by `URLSessionWebSocketTask`.
///
/// This is the only production type allowed to use `URLSession` networking APIs.
public actor URLSessionWebSocketProvider: WebSocketProviding {
    // MARK: - Properties

    /// Session that vends WebSocket tasks.
    private let session: URLSession
    /// Delegate that forwards open/close to per-task sinks.
    private let sessionDelegate: WebSocketSessionDelegate
    /// Registry of lifecycle sinks keyed by `URLSessionTask.taskIdentifier`.
    private let registry: WebSocketLifecycleRegistry
    /// Bound applied around `sendPing` pong wait.
    private let pingTimeout: Duration

    // MARK: - Initialization

    /// Creates a provider with a dedicated `URLSession`.
    ///
    /// - Parameter pingTimeout: How long each ping waits for a pong.
    public init(pingTimeout: Duration = .seconds(10)) {
        let registry = WebSocketLifecycleRegistry()
        let sessionDelegate = WebSocketSessionDelegate(registry: registry)
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        self.registry = registry
        self.sessionDelegate = sessionDelegate
        self.session = URLSession(
            configuration: configuration,
            delegate: sessionDelegate,
            delegateQueue: nil
        )
        self.pingTimeout = pingTimeout
    }

    deinit {
        session.invalidateAndCancel()
    }

    // MARK: - Public API

    /// Creates a `URLSessionWebSocketTask` wrapper for `url`.
    ///
    /// - Parameters:
    ///   - url: Realtime WebSocket URL.
    ///   - protocols: Subprotocols (JWT when present).
    ///   - sink: Open/close observer.
    /// - Returns: An unstarted task.
    public func makeTask(
        url: URL,
        protocols: [String],
        sink: WebSocketLifecycleSink
    ) async -> any WebSocketTasking {
        let socket = session.webSocketTask(with: url, protocols: protocols)
        await registry.register(taskIdentifier: socket.taskIdentifier, sink: sink)
        return URLSessionWebSocketTaskAdapter(task: socket, pingTimeout: pingTimeout)
    }
}

/// Maps `URLSessionTask.taskIdentifier` to a lifecycle sink.
actor WebSocketLifecycleRegistry {
    // MARK: - Properties

    /// Active sinks.
    private var sinks: [Int: WebSocketLifecycleSink] = [:]

    // MARK: - Public API

    /// Records `sink` for `taskIdentifier`.
    ///
    /// - Parameters:
    ///   - taskIdentifier: Session task identifier.
    ///   - sink: Observer to notify.
    func register(taskIdentifier: Int, sink: WebSocketLifecycleSink) {
        sinks[taskIdentifier] = sink
    }

    /// Forwards an open event.
    ///
    /// - Parameter taskIdentifier: Session task identifier.
    func notifyOpen(taskIdentifier: Int) async {
        await sinks[taskIdentifier]?.webSocketDidOpen()
    }

    /// Forwards a close event and drops the sink.
    ///
    /// - Parameters:
    ///   - taskIdentifier: Session task identifier.
    ///   - code: Close code.
    ///   - reason: Optional reason bytes.
    func notifyClose(taskIdentifier: Int, code: WebSocketCloseCode, reason: Data?) async {
        let sink = sinks.removeValue(forKey: taskIdentifier)
        await sink?.webSocketDidClose(code: code, reason: reason)
    }
}

/// `URLSession` delegate that hops open/close onto ``WebSocketLifecycleRegistry``.
final class WebSocketSessionDelegate: NSObject, URLSessionWebSocketDelegate {
    // MARK: - Properties

    /// Registry that holds sinks.
    private let registry: WebSocketLifecycleRegistry

    // MARK: - Initialization

    /// Creates a delegate.
    ///
    /// - Parameter registry: Sink registry.
    init(registry: WebSocketLifecycleRegistry) {
        self.registry = registry
    }

    // MARK: - URLSessionWebSocketDelegate

    /// Forwards socket open.
    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        let identifier = webSocketTask.taskIdentifier
        Task {
            await registry.notifyOpen(taskIdentifier: identifier)
        }
    }

    /// Forwards socket close.
    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        let identifier = webSocketTask.taskIdentifier
        let code = WebSocketCloseCode(rawValue: Int(closeCode.rawValue))
        Task {
            await registry.notifyClose(taskIdentifier: identifier, code: code, reason: reason)
        }
    }
}

/// Actor wrapping one `URLSessionWebSocketTask`.
actor URLSessionWebSocketTaskAdapter: WebSocketTasking {
    // MARK: - Properties

    /// Underlying session task.
    private let task: URLSessionWebSocketTask
    /// Pong wait bound.
    private let pingTimeout: Duration

    // MARK: - Initialization

    /// Creates an adapter.
    ///
    /// - Parameters:
    ///   - task: Session WebSocket task.
    ///   - pingTimeout: Pong wait bound.
    init(task: URLSessionWebSocketTask, pingTimeout: Duration) {
        self.task = task
        self.pingTimeout = pingTimeout
    }

    // MARK: - Public API

    /// Starts the handshake.
    func resume() async {
        task.resume()
    }

    /// Receives the next frame.
    ///
    /// - Returns: Mapped ``WebSocketMessage``.
    /// - Throws: The underlying session error.
    func receive() async throws -> WebSocketMessage {
        let message = try await task.receive()
        switch message {
        case .string(let text):
            return .string(text)
        case .data(let data):
            return .data(data)
        @unknown default:
            throw XanoRealtimeError.decodingFailed("Unknown WebSocket message kind")
        }
    }

    /// Sends a frame.
    ///
    /// - Parameter message: Text or binary payload.
    /// - Throws: The underlying session error.
    func send(_ message: WebSocketMessage) async throws {
        switch message {
        case .string(let text):
            try await task.send(.string(text))
        case .data(let data):
            try await task.send(.data(data))
        }
    }

    /// Sends a ping and waits for a pong or ``XanoRealtimeError/pingTimedOut``.
    ///
    /// - Throws: A transport error or ``XanoRealtimeError/pingTimedOut``.
    func sendPing() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.performPing()
            }
            group.addTask {
                try await Task.sleep(for: self.pingTimeout)
                throw XanoRealtimeError.pingTimedOut
            }
            try await group.next()
            group.cancelAll()
        }
    }

    /// Cancels the session task.
    ///
    /// - Parameters:
    ///   - code: Close code.
    ///   - reason: Optional reason.
    func cancel(with code: WebSocketCloseCode, reason: Data?) async {
        let sessionCode = URLSessionWebSocketTask.CloseCode(rawValue: code.rawValue) ?? .invalid
        task.cancel(with: sessionCode, reason: reason)
    }

    // MARK: - Private Helpers

    /// Wraps `sendPing` in a throwing continuation.
    ///
    /// - Throws: The ping handler error.
    private func performPing() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            task.sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
