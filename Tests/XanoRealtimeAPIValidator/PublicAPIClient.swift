import Testing
import XanoRealtime

@Test("public XanoRealtimeClient API exists")
func publicClientAPIExists() {
    let _: (XanoRealtimeConfiguration) -> XanoRealtimeClient = XanoRealtimeClient.init
    let lock: (XanoRealtimeClient) async throws -> Void = { client in
        let _: AsyncStream<ConnectionState> = await client.connectionState
        let _: ConnectionState = await client.currentConnectionState
        let _: XanoRealtimeChannel = await client.channel("lobby")
        let _: XanoRealtimeChannel = await client.channel("lobby", options: ChannelOptions())
        try await client.connect()
        await client.disconnect()
        await client.setAuthToken(nil)
        await client.enterBackground()
        await client.enterForeground()
    }
    _ = lock
}

@Test("public XanoRealtimeChannel API exists")
func publicChannelAPIExists() {
    let lock: (XanoRealtimeChannel) async throws -> Void = { channel in
        let _: String = await channel.name
        let _: ChannelOptions = await channel.options
        let _: AsyncStream<RealtimeEvent> = await channel.events
        let _: [RealtimePeer] = await channel.presence
        try await channel.send("payload", authenticated: true)
        try await channel.send("payload")
        try await channel.message("payload", to: "socket")
        try await channel.requestHistory()
        await channel.leave()
    }
    _ = lock
}
