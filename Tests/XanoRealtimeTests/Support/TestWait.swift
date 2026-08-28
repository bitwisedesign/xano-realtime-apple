import Foundation
import Testing
@testable import XanoRealtime

/// Errors thrown by test wait helpers.
enum TestWaitError: Error, Equatable {
    /// The wait deadline elapsed.
    case timedOut
    /// The stream ended before a value arrived.
    case streamEnded
}

/// Awaits the next value from `stream` or fails after `timeout`.
///
/// - Parameters:
///   - stream: Stream to read.
///   - timeout: Bound; defaults to 2 seconds for CI slack.
/// - Returns: The next element.
/// - Throws: ``TestWaitError`` when the deadline elapses or the stream ends.
func nextValue<Element: Sendable>(
    from stream: AsyncStream<Element>,
    timeout: Duration = .seconds(2)
) async throws -> Element {
    try await withThrowingTaskGroup(of: Element.self) { group in
        group.addTask {
            var iterator = stream.makeAsyncIterator()
            guard let value = await iterator.next() else {
                throw TestWaitError.streamEnded
            }
            return value
        }
        group.addTask {
            try await Task.sleep(for: timeout)
            throw TestWaitError.timedOut
        }
        do {
            let value = try await group.next()
            group.cancelAll()
            guard let value else {
                throw TestWaitError.streamEnded
            }
            return value
        } catch {
            group.cancelAll()
            throw error
        }
    }
}

/// Awaits until `stream` yields a value matching `predicate`.
///
/// - Parameters:
///   - stream: Stream to read.
///   - timeout: Bound; defaults to 2 seconds.
///   - predicate: Match condition.
/// - Returns: The matching element.
/// - Throws: ``TestWaitError/timedOut`` when the deadline elapses.
func nextValue<Element: Sendable>(
    from stream: AsyncStream<Element>,
    timeout: Duration = .seconds(2),
    matching predicate: @escaping @Sendable (Element) -> Bool
) async throws -> Element {
    try await withThrowingTaskGroup(of: Element.self) { group in
        group.addTask {
            for await value in stream where predicate(value) {
                return value
            }
            throw TestWaitError.streamEnded
        }
        group.addTask {
            try await Task.sleep(for: timeout)
            throw TestWaitError.timedOut
        }
        do {
            let value = try await group.next()
            group.cancelAll()
            guard let value else {
                throw TestWaitError.streamEnded
            }
            return value
        } catch {
            group.cancelAll()
            throw error
        }
    }
}

/// Creates a ``StreamCollector`` and starts pumping `stream`.
///
/// - Parameter stream: Stream to consume exactly once.
/// - Returns: The running collector.
func collect<Element: Sendable>(_ stream: AsyncStream<Element>) async -> StreamCollector<Element> {
    let collector = StreamCollector<Element>()
    await collector.start(stream: stream)
    return collector
}

/// Builds a configuration that talks to a mock provider (heartbeat disabled).
func testConfiguration(
    queueOfflineActions: Bool = false,
    connectionCanonical: String = "testCanonical"
) throws -> XanoRealtimeConfiguration {
    let base = try #require(URL(string: "https://example.xano.io/api:group"))
    return XanoRealtimeConfiguration(
        instanceBaseUrl: base,
        connectionCanonical: connectionCanonical,
        realtimeAuthToken: nil,
        pingInterval: nil,
        queueOfflineActions: queueOfflineActions
    )
}

/// Sample authenticated peer used in envelope fixtures.
func samplePeer(socketId: String = "sock-1") -> RealtimePeer {
    RealtimePeer(
        socketId: socketId,
        extras: ["role": .string("player")],
        permissions: RealtimePermissions(dboID: 12, rowID: 34)
    )
}
