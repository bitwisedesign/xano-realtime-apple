import Foundation
import Testing
@testable import XanoRealtime

@Test("connects with the assembled URL and optional subprotocol")
func connectionUsesURLAndSubprotocol() async throws {
    let configuration = try testConfiguration()
    var configured = configuration
    configured.realtimeAuthToken = "jwt-abc"
    let provider = FakeWebSocketProvider()
    let connection = WebSocketConnection(
        configuration: configured,
        provider: provider,
        delay: ImmediateDelay()
    )
    let states = await collect(connection.stateStream)

    try await connection.connect()

    let connected = try await states.wait(matching: { $0 == .connected })
    #expect(connected == .connected)

    let url = try #require(await provider.lastURL)
    #expect(url.absoluteString == "wss://example.xano.io/rt/testCanonical")
    #expect(await provider.lastProtocols == ["jwt-abc"])
}

@Test("close code 1006 reconnects and creates a new task")
func abnormalCloseReconnects() async throws {
    let provider = FakeWebSocketProvider()
    let connection = WebSocketConnection(
        configuration: try testConfiguration(),
        provider: provider,
        delay: ImmediateDelay()
    )
    let states = await collect(connection.stateStream)
    try await connection.connect()
    _ = try await states.wait(matching: { $0 == .connected })
    let baseline = await states.all.count

    let first = try #require(await provider.latestTask)
    await first.simulateClose(code: .abnormalClosure)

    _ = try await states.wait(after: baseline, matching: { state in
        if case .reconnecting = state { return true }
        return false
    })
    _ = try await states.wait(after: baseline, matching: { $0 == .connected })
    #expect(await provider.tasks.count >= 2)
}

@Test("close code 1000 stays disconnected")
func normalCloseDoesNotReconnect() async throws {
    let provider = FakeWebSocketProvider()
    let connection = WebSocketConnection(
        configuration: try testConfiguration(),
        provider: provider,
        delay: ImmediateDelay()
    )
    let states = await collect(connection.stateStream)
    try await connection.connect()
    _ = try await states.wait(matching: { $0 == .connected })
    let baseline = await states.all.count

    await connection.disconnect()
    let disconnected = try await states.wait(after: baseline, matching: { $0 == .disconnected })
    #expect(disconnected == .disconnected)
    #expect(await provider.tasks.count == 1)
    #expect(await provider.latestTask?.cancelCode == .normalClosure)
}

@Test("queues outbound envelopes until the socket connects")
func offlineQueueFlushesInOrder() async throws {
    let provider = FakeWebSocketProvider()
    await provider.setAutoOpenOnResume(false)
    let connection = WebSocketConnection(
        configuration: try testConfiguration(queueOfflineActions: true),
        provider: provider,
        delay: ImmediateDelay()
    )
    let states = await collect(connection.stateStream)

    let first = RealtimeCoder.shared.message(channel: "a", payload: .string("one"))
    let second = RealtimeCoder.shared.message(channel: "a", payload: .string("two"))
    try await connection.send(first)
    try await connection.send(second)

    try await connection.connect()
    let task = try #require(await provider.latestTask)
    await task.simulateOpen()

    _ = try await states.wait(matching: { $0 == .connected })

    let sent = try await task.sentEnvelopes
    #expect(sent.map(\.payload) == [first.payload, second.payload])
}

@Test("send throws notConnected when queuing is disabled")
func sendThrowsWhenDisconnected() async throws {
    let connection = WebSocketConnection(
        configuration: try testConfiguration(queueOfflineActions: false),
        provider: FakeWebSocketProvider(),
        delay: ImmediateDelay()
    )
    let envelope = RealtimeCoder.shared.message(channel: "a", payload: .string("x"))
    await #expect(throws: XanoRealtimeError.notConnected) {
        try await connection.send(envelope)
    }
}

@Test("setAuthToken cancels with code 4000")
func setAuthTokenUsesReconnectCloseCode() async throws {
    let provider = FakeWebSocketProvider()
    let connection = WebSocketConnection(
        configuration: try testConfiguration(),
        provider: provider,
        delay: ImmediateDelay()
    )
    let states = await collect(connection.stateStream)
    try await connection.connect()
    _ = try await states.wait(matching: { $0 == .connected })
    let baseline = await states.all.count

    let first = try #require(await provider.latestTask)
    await connection.setAuthToken("new-jwt")

    #expect(await first.cancelCode == .reconnectRequested)
    _ = try await states.wait(after: baseline, matching: { $0 == .connected })
    #expect(await provider.lastProtocols == ["new-jwt"])
}

@Test("failed heartbeat ping reconnects")
func heartbeatFailureReconnects() async throws {
    let provider = FakeWebSocketProvider()
    await provider.setPingError(XanoRealtimeError.pingTimedOut)
    let connection = WebSocketConnection(
        configuration: try testConfiguration(),
        provider: provider,
        delay: ImmediateDelay()
    )
    let states = await collect(connection.stateStream)
    try await connection.connect()
    _ = try await states.wait(matching: { $0 == .connected })
    let baseline = await states.all.count

    await connection.performHeartbeatTick()

    _ = try await states.wait(after: baseline, matching: { $0 == .connected })
    #expect(await provider.tasks.count >= 2)
}
