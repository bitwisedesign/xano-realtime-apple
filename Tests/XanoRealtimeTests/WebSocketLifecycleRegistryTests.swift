import Foundation
import Testing
@testable import XanoRealtime

@Test("completion close code uses 1006 when a transport error has no close frame")
func completionCloseCodeUsesAbnormalClosureOnTransportError() {
    #expect(
        webSocketTaskCompletionCloseCode(reportedCloseCode: 0, hasError: true)
            == .abnormalClosure
    )
    #expect(
        webSocketTaskCompletionCloseCode(reportedCloseCode: 1000, hasError: true)
            == .normalClosure
    )
    #expect(
        webSocketTaskCompletionCloseCode(reportedCloseCode: 0, hasError: false)
            == .unknown
    )
}

@Test("registry drops the sink on close so a later completion does not notify again")
func registryRemovesSinkOnClose() async {
    let registry = WebSocketLifecycleRegistry()
    let sink = RecordingLifecycleSink()
    await registry.register(taskIdentifier: 7, sink: sink)

    await registry.notifyClose(taskIdentifier: 7, code: .abnormalClosure, reason: nil)
    await registry.notifyClose(taskIdentifier: 7, code: .normalClosure, reason: nil)

    #expect(await sink.closeCodes == [.abnormalClosure])
}

/// Records close notifications for registry tests.
private actor RecordingLifecycleSink: WebSocketLifecycleSink {
    /// Close codes received in order.
    private(set) var closeCodes: [WebSocketCloseCode] = []

    func webSocketDidOpen() async {}

    func webSocketDidClose(code: WebSocketCloseCode, reason: Data?) async {
        closeCodes.append(code)
    }
}
