import Foundation
import Testing
@testable import XanoRealtime

@Test("backoff starts at 1s, doubles, and caps at 60s")
func exponentialBackoffSequenceAndReset() {
    var backoff = ExponentialBackoff()
    #expect(backoff.next() == .seconds(1))
    #expect(backoff.next() == .seconds(2))
    #expect(backoff.next() == .seconds(4))
    #expect(backoff.next() == .seconds(8))
    #expect(backoff.next() == .seconds(16))
    #expect(backoff.next() == .seconds(32))
    #expect(backoff.next() == .seconds(60))
    #expect(backoff.next() == .seconds(60))
    #expect(backoff.attempt == 8)

    backoff.reset()
    #expect(backoff.current == .seconds(1))
    #expect(backoff.attempt == 0)
    #expect(backoff.next() == .seconds(1))
}

@Test("backoff clamps current and next() to cap when initial exceeds cap or properties change")
func exponentialBackoffClampsToCap() {
    var backoff = ExponentialBackoff(initial: .seconds(120), cap: .seconds(60))
    #expect(backoff.current == .seconds(60))
    #expect(backoff.next() == .seconds(60))
    #expect(backoff.current == .seconds(60))

    backoff.initial = .seconds(90)
    backoff.reset()
    #expect(backoff.current == .seconds(60))
    #expect(backoff.next() == .seconds(60))

    backoff = ExponentialBackoff(initial: .seconds(8), cap: .seconds(60))
    #expect(backoff.next() == .seconds(8))
    backoff.cap = .seconds(4)
    #expect(backoff.next() == .seconds(4))
    #expect(backoff.current == .seconds(4))
}

@Test("close codes 1006 1011 1012 1013 1014 4000 reconnect; 1000 does not")
func closeCodeClassification() {
    #expect(WebSocketCloseCode.abnormalClosure.shouldReconnect)
    #expect(WebSocketCloseCode.internalError.shouldReconnect)
    #expect(WebSocketCloseCode.serviceRestart.shouldReconnect)
    #expect(WebSocketCloseCode.tryAgainLater.shouldReconnect)
    #expect(WebSocketCloseCode.badGateway.shouldReconnect)
    #expect(WebSocketCloseCode.reconnectRequested.shouldReconnect)
    #expect(!WebSocketCloseCode.normalClosure.shouldReconnect)
    #expect(!WebSocketCloseCode.unknown.shouldReconnect)
}

@Test("heartbeat is disabled when the interval is nil or zero")
func heartbeatPolicyDisabledStates() {
    #expect(!HeartbeatPolicy(interval: nil).isEnabled)
    #expect(!HeartbeatPolicy(interval: .zero).isEnabled)
    #expect(HeartbeatPolicy(interval: .seconds(20)).isEnabled)
}
