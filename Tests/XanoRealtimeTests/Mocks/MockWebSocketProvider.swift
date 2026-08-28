import Foundation
@testable import XanoRealtime

/// Test adapter that records outbound frames and lets tests inject inbound ones.
actor MockWebSocketProvider: WebSocketProviding {
    // MARK: - Properties

    /// Most recent URL passed to ``makeTask(url:protocols:sink:)``.
    private(set) var lastURL: URL?
    /// Most recent subprotocols passed to ``makeTask(url:protocols:sink:)``.
    private(set) var lastProtocols: [String] = []
    /// Tasks created in order (one per connect/reconnect).
    private(set) var tasks: [MockWebSocketTask] = []
    /// When `true`, each task reports open from ``MockWebSocketTask/resume()``.
    private(set) var autoOpenOnResume = true
    /// When set, the next `sendPing` on a new task throws this error.
    private(set) var pingError: Error?

    /// Sets whether ``MockWebSocketTask/resume()`` synthesizes an open event.
    ///
    /// - Parameter autoOpenOnResume: New value.
    func setAutoOpenOnResume(_ autoOpenOnResume: Bool) {
        self.autoOpenOnResume = autoOpenOnResume
    }

    /// Sets the error thrown from the next task's ``MockWebSocketTask/sendPing()``.
    ///
    /// - Parameter pingError: Error to throw, or `nil`.
    func setPingError(_ pingError: Error?) {
        self.pingError = pingError
    }

    // MARK: - Public API

    /// Creates a recorded mock task.
    func makeTask(
        url: URL,
        protocols: [String],
        sink: WebSocketLifecycleSink
    ) async -> any WebSocketTasking {
        lastURL = url
        lastProtocols = protocols
        let task = MockWebSocketTask(
            sink: sink,
            autoOpenOnResume: autoOpenOnResume,
            pingError: pingError
        )
        tasks.append(task)
        return task
    }

    /// Most recently created task, if any.
    var latestTask: MockWebSocketTask? {
        tasks.last
    }
}

/// In-memory WebSocket task used by ``MockWebSocketProvider``.
actor MockWebSocketTask: WebSocketTasking {
    // MARK: - Properties

    /// Lifecycle sink for this conversation.
    private let sink: WebSocketLifecycleSink
    /// Whether ``resume()`` synthesizes an open event.
    private let autoOpenOnResume: Bool
    /// Optional error thrown from ``sendPing()``.
    private let pingError: Error?
    /// Optional error thrown from the next ``send(_:)``.
    private var sendError: Error?
    /// Frames waiting to be received.
    private var inbound: [Result<WebSocketMessage, Error>] = []
    /// Continuations blocked in ``receive()``.
    private var receiveWaiters: [CheckedContinuation<WebSocketMessage, Error>] = []
    /// Outbound frames in send order.
    private(set) var sent: [WebSocketMessage] = []
    /// Number of times ``sendPing()`` was called.
    private(set) var pingCount = 0
    /// Last cancel code, if any.
    private(set) var cancelCode: WebSocketCloseCode?
    /// Whether ``resume()`` has been called.
    private(set) var didResume = false

    // MARK: - Initialization

    /// Creates a mock task.
    ///
    /// - Parameters:
    ///   - sink: Open/close observer.
    ///   - autoOpenOnResume: Synthesize open from resume.
    ///   - pingError: Optional ping failure.
    init(
        sink: WebSocketLifecycleSink,
        autoOpenOnResume: Bool,
        pingError: Error?
    ) {
        self.sink = sink
        self.autoOpenOnResume = autoOpenOnResume
        self.pingError = pingError
    }

    // MARK: - WebSocketTasking

    /// Records resume and optionally reports open.
    func resume() async {
        didResume = true
        if autoOpenOnResume {
            await sink.webSocketDidOpen()
        }
    }

    /// Returns a queued frame or waits until one is pushed.
    func receive() async throws -> WebSocketMessage {
        if let next = inbound.first {
            inbound.removeFirst()
            return try next.get()
        }
        return try await withCheckedThrowingContinuation { continuation in
            receiveWaiters.append(continuation)
        }
    }

    /// Records an outbound frame, or throws ``sendError`` when set.
    func send(_ message: WebSocketMessage) async throws {
        // Yield so a caller that publishes `connected` before flushing can lose
        // the race, matching a real transport hop.
        await Task.yield()
        if let sendError {
            throw sendError
        }
        sent.append(message)
    }

    /// Sets the error thrown from the next ``send(_:)``, or `nil` to send normally.
    ///
    /// - Parameter sendError: Error to throw, or `nil`.
    func setSendError(_ sendError: Error?) {
        self.sendError = sendError
    }

    /// Increments ``pingCount`` or throws the configured ping error.
    func sendPing() async throws {
        pingCount += 1
        if let pingError {
            throw pingError
        }
    }

    /// Records the close code, fails waiters, and notifies the sink.
    func cancel(with code: WebSocketCloseCode, reason: Data?) async {
        cancelCode = code
        failWaiters(XanoRealtimeError.connectionClosed(code: code))
        await sink.webSocketDidClose(code: code, reason: reason)
    }

    // MARK: - Test Controls

    /// Delivers `message` to the next ``receive()`` waiter or queue.
    func push(_ message: WebSocketMessage) {
        if let waiter = takeWaiter() {
            waiter.resume(returning: message)
        } else {
            inbound.append(.success(message))
        }
    }

    /// Delivers a JSON envelope as a text frame.
    func push(envelope: RealtimeEnvelope) throws {
        let data = try RealtimeCoder.shared.encode(envelope)
        guard let text = String(data: data, encoding: .utf8) else {
            throw XanoRealtimeError.encodingFailed("Encoded envelope was not UTF-8")
        }
        push(.string(text))
    }

    /// Fails the receive loop with `error`.
    func failReceive(_ error: Error) {
        if let waiter = takeWaiter() {
            waiter.resume(throwing: error)
        } else {
            inbound.append(.failure(error))
        }
    }

    /// Reports close without going through ``cancel(with:reason:)``.
    func simulateClose(code: WebSocketCloseCode) async {
        failWaiters(XanoRealtimeError.connectionClosed(code: code))
        await sink.webSocketDidClose(code: code, reason: nil)
    }

    /// Reports open without ``resume()``.
    func simulateOpen() async {
        await sink.webSocketDidOpen()
    }

    /// Decoded outbound envelopes in send order.
    var sentEnvelopes: [RealtimeEnvelope] {
        get throws {
            try sent.compactMap { message in
                switch message {
                case .string(let text):
                    return try RealtimeCoder.shared.decode(from: text)
                case .data(let data):
                    return try RealtimeCoder.shared.decode(from: data)
                }
            }
        }
    }

    // MARK: - Private Helpers

    /// Removes and returns the oldest receive waiter.
    private func takeWaiter() -> CheckedContinuation<WebSocketMessage, Error>? {
        guard !receiveWaiters.isEmpty else {
            return nil
        }
        return receiveWaiters.removeFirst()
    }

    /// Fails every pending ``receive()`` with `error`.
    private func failWaiters(_ error: Error) {
        let waiters = receiveWaiters
        receiveWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(throwing: error)
        }
    }
}
