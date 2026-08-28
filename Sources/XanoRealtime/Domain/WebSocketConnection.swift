import Foundation

/// Actor that owns one multiplexed realtime socket, its state machine, and reliability loops.
///
/// Depends only on ``WebSocketProviding`` / ``WebSocketTasking``. It never imports
/// `URLSession` networking types.
actor WebSocketConnection: WebSocketLifecycleSink {
    // MARK: - Properties

    /// Current connection settings; mutated when the auth token changes.
    private var configuration: XanoRealtimeConfiguration
    /// Transport factory.
    private let provider: any WebSocketProviding
    /// Delay used for reconnect backoff (injectable for tests).
    private let delay: any DelayProviding
    /// JSON coder for inbound and outbound frames.
    private let coder: RealtimeCoder
    /// Current lifecycle state.
    private var state: ConnectionState = .disconnected
    /// Active transport task, when any.
    private var task: (any WebSocketTasking)?
    /// Receive-loop task.
    private var receiveTask: Task<Void, Never>?
    /// Heartbeat-loop task.
    private var heartbeatTask: Task<Void, Never>?
    /// Reconnect-loop task.
    private var reconnectTask: Task<Void, Never>?
    /// Backoff sequence for reconnect delays.
    private var backoff = ExponentialBackoff()
    /// When `true`, close events must not schedule reconnect (disconnect / background).
    private var suppressReconnect = false
    /// Prevents double-handling of receive-loop errors and `didClose`.
    private var isHandlingClose = false
    /// Generation of the active socket; stale open/close from a replaced task are ignored.
    private var socketEpoch = 0
    /// Last close code reported by the adapter.
    private var lastCloseCode: WebSocketCloseCode = .unknown
    /// Outbound envelopes waiting for the next `connected` state.
    private var offlineQueue: [RealtimeEnvelope] = []
    /// Subscribers for ``ConnectionEvent`` values.
    private let eventsContinuation: AsyncStream<ConnectionEvent>.Continuation
    /// Public event stream consumed by ``XanoRealtimeClient``.
    nonisolated let events: AsyncStream<ConnectionEvent>
    /// Subscribers for ``ConnectionState`` values.
    private let stateContinuation: AsyncStream<ConnectionState>.Continuation
    /// Stream of lifecycle state changes.
    nonisolated let stateStream: AsyncStream<ConnectionState>

    // MARK: - Initialization

    /// Creates a connection manager.
    ///
    /// - Parameters:
    ///   - configuration: URL, auth, heartbeat, and queue settings.
    ///   - provider: Transport adapter.
    ///   - delay: Reconnect sleeper.
    ///   - coder: Envelope coder.
    init(
        configuration: XanoRealtimeConfiguration,
        provider: any WebSocketProviding,
        delay: any DelayProviding,
        coder: RealtimeCoder = .shared
    ) {
        self.configuration = configuration
        self.provider = provider
        self.delay = delay
        self.coder = coder
        let eventBuffer = max(configuration.eventBufferSize, 1)
        let eventsPair = AsyncStreamFactory.make(
            of: ConnectionEvent.self,
            bufferingPolicy: .bufferingNewest(eventBuffer)
        )
        self.events = eventsPair.stream
        self.eventsContinuation = eventsPair.continuation
        let statePair = AsyncStreamFactory.make(
            of: ConnectionState.self,
            bufferingPolicy: .bufferingNewest(8)
        )
        self.stateStream = statePair.stream
        self.stateContinuation = statePair.continuation
        stateContinuation.yield(.disconnected)
    }

    // MARK: - Public API

    /// Current lifecycle state.
    var connectionState: ConnectionState {
        state
    }

    /// Whether outbound actions should be queued while disconnected.
    var queuesOfflineActions: Bool {
        configuration.queueOfflineActions
    }

    /// Opens the socket when disconnected or reconnecting.
    ///
    /// - Throws: ``XanoRealtimeError/invalidConfiguration(_:)`` when the URL cannot be built.
    func connect() async throws {
        switch state {
        case .connected, .connecting:
            return
        case .disconnected, .reconnecting:
            break
        }
        suppressReconnect = false
        reconnectTask?.cancel()
        reconnectTask = nil
        try await openSocket()
    }

    /// Closes the socket with a normal closure and does not reconnect.
    func disconnect() async {
        suppressReconnect = true
        reconnectTask?.cancel()
        reconnectTask = nil
        await closeActiveSocket(code: .normalClosure)
        applyState(.disconnected)
        publishEnvelope(
            RealtimeEnvelope(
                action: .connectionStatus,
                options: RealtimeActionOptions(),
                payload: .object(["status": .string("disconnected")])
            )
        )
    }

    /// Closes the socket as an intentional background suspend (no reconnect).
    func enterBackground() async {
        await disconnect()
    }

    /// Reopens the socket after a background suspend.
    ///
    /// - Throws: ``XanoRealtimeError/invalidConfiguration(_:)`` when the URL cannot be built.
    func enterForeground() async throws {
        try await connect()
    }

    /// Updates the auth token and forces a reconnect with close code `4000`.
    ///
    /// - Parameter token: New JWT, or `nil` to clear the subprotocol.
    func setAuthToken(_ token: String?) async {
        configuration.realtimeAuthToken = token
        guard state == .connected || isConnectingOrReconnecting else {
            return
        }
        suppressReconnect = false
        await closeActiveSocket(code: .reconnectRequested)
        scheduleReconnect(code: .reconnectRequested)
    }

    /// Encodes and writes `envelope`, or queues it when offline queuing is enabled.
    ///
    /// - Parameter envelope: Outbound action.
    /// - Throws: ``XanoRealtimeError/notConnected`` when disconnected and queuing is off.
    func send(_ envelope: RealtimeEnvelope) async throws {
        if state != .connected {
            if configuration.queueOfflineActions {
                offlineQueue.append(envelope)
                return
            }
            throw XanoRealtimeError.notConnected
        }
        try await write(envelope)
    }

    /// Sends a single heartbeat ping; used by tests and the heartbeat loop.
    ///
    /// A failed ping is treated as a transport failure and triggers reconnect.
    func performHeartbeatTick() async {
        guard let task, state == .connected else {
            return
        }
        do {
            try await task.sendPing()
        } catch is CancellationError {
            return
        } catch {
            await handleTransportFailure(code: lastCloseCode == .unknown ? .abnormalClosure : lastCloseCode)
        }
    }

    // MARK: - WebSocketLifecycleSink

    /// Flushes the offline queue, marks the socket connected, and synthesizes `connection_status`.
    func webSocketDidOpen() async {
        await webSocketDidOpen(epoch: socketEpoch)
    }

    /// Handles adapter-reported close.
    ///
    /// - Parameters:
    ///   - code: Close code.
    ///   - reason: Unused close reason.
    func webSocketDidClose(code: WebSocketCloseCode, reason: Data?) async {
        await webSocketDidClose(epoch: socketEpoch, code: code, reason: reason)
    }

    /// Applies an open event when `epoch` is still the active socket.
    ///
    /// - Parameter epoch: Socket generation that reported open.
    func webSocketDidOpen(epoch: Int) async {
        guard epoch == socketEpoch else {
            return
        }
        isHandlingClose = false
        lastCloseCode = .unknown
        backoff.reset()
        await flushOfflineQueue()
        guard epoch == socketEpoch else {
            return
        }
        applyState(.connected)
        publishEnvelope(
            RealtimeEnvelope(
                action: .connectionStatus,
                options: RealtimeActionOptions(),
                payload: .object(["status": .string("connected")])
            )
        )
        startHeartbeat()
    }

    /// Applies a close event when `epoch` is still the active socket.
    ///
    /// - Parameters:
    ///   - epoch: Socket generation that reported close.
    ///   - code: Close code.
    ///   - reason: Unused close reason.
    func webSocketDidClose(epoch: Int, code: WebSocketCloseCode, reason: Data?) async {
        guard epoch == socketEpoch else {
            return
        }
        lastCloseCode = code
        await handleTransportFailure(code: code)
    }

    // MARK: - Private Helpers

    /// Whether the state machine is currently opening or backing off.
    private var isConnectingOrReconnecting: Bool {
        switch state {
        case .connecting, .reconnecting:
            return true
        case .connected, .disconnected:
            return false
        }
    }

    /// Creates a task, resumes it, and starts the receive loop.
    ///
    /// After ``makeTask(url:protocols:sink:)`` returns, the captured epoch must
    /// still be current and the connection must still be opening. Otherwise the
    /// new task is cancelled and discarded (a concurrent close invalidated it).
    ///
    /// - Throws: ``XanoRealtimeError/invalidConfiguration(_:)`` when the URL cannot be built.
    private func openSocket() async throws {
        let url = try configuration.makeConnectionURL()
        socketEpoch += 1
        let epoch = socketEpoch
        isHandlingClose = false
        applyState(.connecting)
        let nextTask = await provider.makeTask(
            url: url,
            protocols: configuration.webSocketProtocols,
            sink: SocketEpochSink(connection: self, epoch: epoch)
        )
        guard epoch == socketEpoch, isConnectingOrReconnecting else {
            await nextTask.cancel(with: .normalClosure, reason: nil)
            return
        }
        task = nextTask
        await nextTask.resume()
        startReceiveLoop(on: nextTask, epoch: epoch)
    }

    /// Starts a detached receive loop for `socket`.
    ///
    /// - Parameters:
    ///   - socket: Active task.
    ///   - epoch: Socket generation that owns this loop.
    private func startReceiveLoop(on socket: any WebSocketTasking, epoch: Int) {
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in
            await self?.runReceiveLoop(on: socket, epoch: epoch)
        }
    }

    /// Reads frames until the socket fails or the task is cancelled.
    ///
    /// - Parameters:
    ///   - socket: Active task.
    ///   - epoch: Socket generation that owns this loop.
    private func runReceiveLoop(on socket: any WebSocketTasking, epoch: Int) async {
        while !Task.isCancelled {
            let message: WebSocketMessage
            do {
                message = try await socket.receive()
            } catch is CancellationError {
                return
            } catch {
                guard epoch == socketEpoch else {
                    return
                }
                await handleTransportFailure(
                    code: lastCloseCode == .unknown ? .abnormalClosure : lastCloseCode
                )
                return
            }
            guard epoch == socketEpoch else {
                return
            }
            handleInbound(message)
        }
    }

    /// Decodes one inbound frame and publishes it.
    ///
    /// Malformed JSON is published as a failure and does not close the socket (JS SDK swallows parse errors).
    ///
    /// - Parameter message: Inbound text or data.
    private func handleInbound(_ message: WebSocketMessage) {
        let data: Data
        switch message {
        case .string(let text):
            guard let encoded = text.data(using: .utf8) else {
                eventsContinuation.yield(.failure(.decodingFailed("Inbound text is not valid UTF-8")))
                return
            }
            data = encoded
        case .data(let payload):
            data = payload
        }
        do {
            let envelope = try coder.decode(from: data)
            eventsContinuation.yield(.envelope(envelope))
        } catch let error as XanoRealtimeError {
            eventsContinuation.yield(.failure(error))
        } catch {
            eventsContinuation.yield(.failure(.decodingFailed(String(describing: error))))
        }
    }

    /// Encodes and writes `envelope` on the current task.
    ///
    /// - Parameter envelope: Outbound envelope.
    /// - Throws: ``XanoRealtimeError/notConnected`` or ``XanoRealtimeError/encodingFailed(_:)``.
    private func write(_ envelope: RealtimeEnvelope) async throws {
        guard let task else {
            throw XanoRealtimeError.notConnected
        }
        let data = try coder.encode(envelope)
        guard let text = String(data: data, encoding: .utf8) else {
            throw XanoRealtimeError.encodingFailed("Encoded envelope was not UTF-8")
        }
        do {
            try await task.send(.string(text))
        } catch {
            throw XanoRealtimeError.connectionClosed(code: lastCloseCode)
        }
    }

    /// Writes queued envelopes in insertion order after reconnect.
    ///
    /// Drains ``offlineQueue`` itself so envelopes appended during a suspended
    /// write are sent before the socket is marked connected. A transport failure
    /// stops the flush and puts the failed envelope back at the front, leaving
    /// any not-yet-written envelopes (including those appended during the write)
    /// on the queue for the next reconnect. Encoding failures are reported and
    /// skipped so they cannot block the queue.
    private func flushOfflineQueue() async {
        while !offlineQueue.isEmpty {
            let envelope = offlineQueue.removeFirst()
            do {
                try await write(envelope)
            } catch let error as XanoRealtimeError {
                eventsContinuation.yield(.failure(error))
                if case .encodingFailed = error {
                    continue
                }
                offlineQueue.insert(envelope, at: 0)
                return
            } catch {
                eventsContinuation.yield(.failure(.connectionClosed(code: lastCloseCode)))
                offlineQueue.insert(envelope, at: 0)
                return
            }
        }
    }

    /// Starts the heartbeat loop when the policy is enabled.
    private func startHeartbeat() {
        heartbeatTask?.cancel()
        guard configuration.heartbeatPolicy.isEnabled else {
            heartbeatTask = nil
            return
        }
        let interval = configuration.heartbeatPolicy.interval ?? .seconds(20)
        heartbeatTask = Task { [weak self] in
            await self?.runHeartbeat(interval: interval)
        }
    }

    /// Sleeps, then pings, until cancelled.
    ///
    /// - Parameter interval: Delay between pings.
    private func runHeartbeat(interval: Duration) async {
        while !Task.isCancelled {
            do {
                try await delay.wait(interval)
            } catch {
                return
            }
            await performHeartbeatTick()
        }
    }

    /// Cancels loops and the active socket.
    ///
    /// Increments ``socketEpoch`` first so an in-flight ``openSocket()`` that is
    /// still awaiting ``makeTask(url:protocols:sink:)`` will discard the result.
    /// Sets ``isHandlingClose`` next so the adapter's close callback and a cancelled
    /// receive loop do not enter ``handleTransportFailure(code:)`` for an intentional
    /// disconnect or auth-token reconnect.
    ///
    /// - Parameter code: Close code to send.
    private func closeActiveSocket(code: WebSocketCloseCode) async {
        socketEpoch += 1
        isHandlingClose = true
        heartbeatTask?.cancel()
        heartbeatTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        let existing = task
        task = nil
        await existing?.cancel(with: code, reason: nil)
    }

    /// Handles a receive-loop error or adapter close exactly once.
    ///
    /// - Parameter code: Close code that ended the socket.
    private func handleTransportFailure(code: WebSocketCloseCode) async {
        guard !isHandlingClose else {
            return
        }
        isHandlingClose = true
        lastCloseCode = code
        await closeActiveSocket(code: code)
        publishEnvelope(
            RealtimeEnvelope(
                action: .connectionStatus,
                options: RealtimeActionOptions(),
                payload: .object(["status": .string("disconnected")])
            )
        )
        if suppressReconnect || !code.shouldReconnect {
            applyState(.disconnected)
            eventsContinuation.yield(.failure(.connectionClosed(code: code)))
            return
        }
        scheduleReconnect(code: code)
    }

    /// Schedules another ``connect()`` after the next backoff delay.
    ///
    /// - Parameter code: Close code that triggered reconnect.
    private func scheduleReconnect(code: WebSocketCloseCode) {
        let wait = backoff.next()
        applyState(.reconnecting(attempt: backoff.attempt))
        eventsContinuation.yield(.failure(.connectionClosed(code: code)))
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            do {
                try await self?.delay.wait(wait)
            } catch {
                return
            }
            guard let self else {
                return
            }
            do {
                try await self.connect()
            } catch let error as XanoRealtimeError {
                await self.publishFailure(error)
            } catch {
                await self.publishFailure(.invalidConfiguration(String(describing: error)))
            }
        }
    }

    /// Publishes a failure to event subscribers.
    ///
    /// - Parameter error: Failure to publish.
    private func publishFailure(_ error: XanoRealtimeError) {
        eventsContinuation.yield(.failure(error))
    }

    /// Yields an envelope to event subscribers.
    ///
    /// - Parameter envelope: Envelope to publish.
    private func publishEnvelope(_ envelope: RealtimeEnvelope) {
        eventsContinuation.yield(.envelope(envelope))
    }

    /// Updates ``state`` and yields it on ``stateStream``.
    ///
    /// - Parameter next: New state.
    private func applyState(_ next: ConnectionState) {
        state = next
        stateContinuation.yield(next)
    }
}

// MARK: - Extensions

/// Forwards adapter lifecycle events only for one ``WebSocketConnection`` socket generation.
private struct SocketEpochSink: WebSocketLifecycleSink {
    // MARK: - Properties

    /// Connection that owns the socket.
    let connection: WebSocketConnection
    /// Socket generation this sink reports for.
    let epoch: Int

    // MARK: - Public API

    /// Forwards open when this generation is still active.
    func webSocketDidOpen() async {
        await connection.webSocketDidOpen(epoch: epoch)
    }

    /// Forwards close when this generation is still active.
    ///
    /// - Parameters:
    ///   - code: Close code.
    ///   - reason: Unused close reason.
    func webSocketDidClose(code: WebSocketCloseCode, reason: Data?) async {
        await connection.webSocketDidClose(epoch: epoch, code: code, reason: reason)
    }
}
