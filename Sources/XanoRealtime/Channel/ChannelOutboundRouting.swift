import Foundation

/// Outbound path a channel uses to send envelopes through the client facade.
protocol ChannelOutboundRouting: Sendable {
    /// Writes `envelope` on the multiplexed socket (or queues it).
    ///
    /// - Parameter envelope: Outbound action.
    /// - Throws: ``XanoRealtimeError/notConnected`` when the socket is down and queuing is off.
    func sendEnvelope(_ envelope: RealtimeEnvelope) async throws
    /// Opens the socket if needed.
    ///
    /// - Throws: ``XanoRealtimeError/invalidConfiguration(_:)`` when the URL cannot be built.
    func ensureConnected() async throws
    /// Called after a channel sends `leave` so the client can drop it from the registry.
    ///
    /// - Parameter name: Channel name that left.
    func channelDidLeave(_ name: String) async
}
