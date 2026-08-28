import Foundation
@testable import XanoRealtime

/// Single-iterator collector so tests can wait for stream values without racing `AsyncStream`.
actor StreamCollector<Element: Sendable> {
    // MARK: - Properties

    /// Values received so far.
    private var values: [Element] = []
    /// Waiters blocked on a predicate.
    private var waiters: [Waiter] = []
    /// Pump task that owns the stream iterator.
    private var pump: Task<Void, Never>?

    /// A waiter blocked until `predicate` matches.
    private struct Waiter {
        /// Match condition.
        let predicate: @Sendable (Element) -> Bool
        /// Exclusive start index in ``values``.
        let startIndex: Int
        /// Continuation resumed with the match or a timeout/cancel error.
        let continuation: CheckedContinuation<Element, Error>
        /// Identity used to drop this waiter on cancel.
        let id: UUID
    }

    // MARK: - Initialization

    /// Creates an empty collector. Call ``start(stream:)`` before waiting.
    init() {}

    /// Starts pumping `stream`. Safe to call once.
    ///
    /// - Parameter stream: Stream to consume exactly once.
    func start(stream: AsyncStream<Element>) {
        guard pump == nil else {
            return
        }
        pump = Task {
            for await value in stream {
                self.append(value)
            }
        }
    }

    deinit {
        pump?.cancel()
    }

    // MARK: - Public API

    /// Snapshot of received values.
    var all: [Element] {
        values
    }

    /// Waits until a received value matches `predicate`, or fails after `timeout`.
    ///
    /// - Parameters:
    ///   - timeout: Bound; defaults to 2 seconds.
    ///   - predicate: Match condition.
    /// - Returns: The first matching element, including values already received.
    /// - Throws: ``TestWaitError/timedOut`` when the deadline elapses.
    func wait(
        timeout: Duration = .seconds(2),
        matching predicate: @escaping @Sendable (Element) -> Bool
    ) async throws -> Element {
        try await wait(timeout: timeout, after: 0, matching: predicate)
    }

    /// Waits for a match among values received after the current snapshot.
    ///
    /// Use this after an earlier ``wait(timeout:matching:)`` so a reconnect's
    /// second `.connected` is not confused with the first.
    ///
    /// - Parameters:
    ///   - timeout: Bound; defaults to 2 seconds.
    ///   - predicate: Match condition.
    /// - Returns: The first new matching element.
    /// - Throws: ``TestWaitError/timedOut`` when the deadline elapses.
    func waitForNext(
        timeout: Duration = .seconds(2),
        matching predicate: @escaping @Sendable (Element) -> Bool
    ) async throws -> Element {
        try await wait(timeout: timeout, after: values.count, matching: predicate)
    }

    /// Waits for a match among values at index `after` or later.
    ///
    /// Snapshot `after` **before** triggering the transition so already-completed
    /// reconnects are still visible.
    ///
    /// - Parameters:
    ///   - timeout: Bound.
    ///   - after: Start index; `0` searches the full history.
    ///   - predicate: Match condition.
    /// - Returns: The first matching element in range.
    /// - Throws: ``TestWaitError/timedOut`` when the deadline elapses.
    func wait(
        timeout: Duration = .seconds(2),
        after startIndex: Int,
        matching predicate: @escaping @Sendable (Element) -> Bool
    ) async throws -> Element {
        if let existing = values.enumerated().first(where: { $0.offset >= startIndex && predicate($0.element) }) {
            return existing.element
        }
        return try await withThrowingTaskGroup(of: Element.self) { group in
            group.addTask {
                try await self.park(after: startIndex, matching: predicate)
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

    // MARK: - Private Helpers

    /// Records `value` and resumes matching waiters.
    ///
    /// - Parameter value: Newly received element.
    private func append(_ value: Element) {
        values.append(value)
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            let index = values.count - 1
            if index >= waiter.startIndex && waiter.predicate(value) {
                waiter.continuation.resume(returning: value)
            } else {
                waiters.append(waiter)
            }
        }
    }

    /// Parks until `predicate` matches a future value.
    ///
    /// - Parameter predicate: Match condition.
    /// - Returns: The matching element.
    /// - Throws: `CancellationError` when the wait is cancelled.
    private func park(
        after startIndex: Int,
        matching predicate: @escaping @Sendable (Element) -> Bool
    ) async throws -> Element {
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if let existing = values.enumerated().first(
                    where: { $0.offset >= startIndex && predicate($0.element) }
                ) {
                    continuation.resume(returning: existing.element)
                    return
                }
                waiters.append(
                    Waiter(
                        predicate: predicate,
                        startIndex: startIndex,
                        continuation: continuation,
                        id: id
                    )
                )
            }
        } onCancel: {
            Task {
                await self.cancelWaiter(id: id)
            }
        }
    }

    /// Resumes and drops the waiter with `id`.
    ///
    /// - Parameter id: Waiter identity.
    private func cancelWaiter(id: UUID) {
        if let index = waiters.firstIndex(where: { $0.id == id }) {
            let waiter = waiters.remove(at: index)
            waiter.continuation.resume(throwing: CancellationError())
        }
    }
}
