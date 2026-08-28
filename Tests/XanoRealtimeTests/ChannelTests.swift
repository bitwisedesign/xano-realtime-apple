import Foundation
import Testing
@testable import XanoRealtime

@Test("filters inbound envelopes by options.channel and auto-joins on connect")
func channelFiltersAndAutoJoins() async throws {
    let provider = MockWebSocketProvider()
    let client = XanoRealtimeClient(
        configuration: try testConfiguration(),
        provider: provider,
        delay: ImmediateDelay()
    )
    let lobby = await client.channel("lobby", options: ChannelOptions(presence: true))
    let events = await collect(await lobby.events)

    _ = try await events.wait(matching: { $0 == .connected })

    let task = try #require(await provider.latestTask)
    let sent = try await task.sentEnvelopes
    #expect(sent.contains { $0.action == .join && $0.options?.channel == "lobby" })

    try await task.push(
        envelope: RealtimeEnvelope(
            action: .message,
            options: RealtimeActionOptions(channel: "other"),
            payload: .string("skip")
        )
    )
    try await task.push(
        envelope: RealtimeEnvelope(
            action: .message,
            client: samplePeer(),
            options: RealtimeActionOptions(channel: "lobby"),
            payload: .string("keep")
        )
    )

    let message = try await events.wait { event in
        if case .message(let body) = event, body.payload == .string("keep") {
            return true
        }
        return false
    }
    if case .message(let body) = message {
        #expect(body.sender?.socketId == "sock-1")
    } else {
        Issue.record("Expected a message event")
    }
}

@Test("updates the presence cache from presence_full and presence_update")
func presenceCacheUpdates() async throws {
    let provider = MockWebSocketProvider()
    let client = XanoRealtimeClient(
        configuration: try testConfiguration(),
        provider: provider,
        delay: ImmediateDelay()
    )
    let lobby = await client.channel("lobby", options: ChannelOptions(presence: true))
    let events = await collect(await lobby.events)
    _ = try await events.wait(matching: { $0 == .connected })

    let alpha = samplePeer(socketId: "alpha")
    let bravo = samplePeer(socketId: "bravo")
    let task = try #require(await provider.latestTask)

    try await task.push(
        envelope: RealtimeEnvelope(
            action: .presenceFull,
            options: RealtimeActionOptions(channel: "lobby"),
            payload: try JSONValue(encoding: PresenceFullPayload(presence: [alpha, bravo]))
        )
    )
    _ = try await events.wait { event in
        if case .presenceFull(let peers) = event {
            return peers.count == 2
        }
        return false
    }
    #expect(await lobby.presence.map(\.socketId) == ["alpha", "bravo"])

    try await task.push(
        envelope: RealtimeEnvelope(
            action: .presenceUpdate,
            options: RealtimeActionOptions(channel: "lobby"),
            payload: try JSONValue(
                encoding: PresenceUpdatePayload(action: .leave, presence: alpha)
            )
        )
    )
    _ = try await events.wait { event in
        if case .presenceUpdate(let action, let peer) = event {
            return action == .leave && peer.socketId == "alpha"
        }
        return false
    }
    #expect(await lobby.presence.map(\.socketId) == ["bravo"])
}

@Test("joins a second channel while already connected without a second lobby join")
func joinsAdditionalChannelWhileConnected() async throws {
    let provider = MockWebSocketProvider()
    let client = XanoRealtimeClient(
        configuration: try testConfiguration(),
        provider: provider,
        delay: ImmediateDelay()
    )
    let lobby = await client.channel("lobby")
    let events = await collect(await lobby.events)
    _ = try await events.wait(matching: { $0 == .connected })

    let task = try #require(await provider.latestTask)
    _ = await client.channel("room", options: ChannelOptions(presence: true))

    let sent = try await task.sentEnvelopes
    let lobbyJoins = sent.filter { $0.action == .join && $0.options?.channel == "lobby" }
    let roomJoins = sent.filter { $0.action == .join && $0.options?.channel == "room" }
    #expect(lobbyJoins.count == 1)
    #expect(roomJoins.count == 1)
}

@Test("resends join after reconnect")
func autoJoinAfterReconnect() async throws {
    let provider = MockWebSocketProvider()
    let client = XanoRealtimeClient(
        configuration: try testConfiguration(),
        provider: provider,
        delay: ImmediateDelay()
    )
    let lobby = await client.channel("lobby")
    let events = await collect(await lobby.events)
    _ = try await events.wait(matching: { $0 == .connected })
    let baseline = await events.all.count

    let first = try #require(await provider.latestTask)
    await first.simulateClose(code: .abnormalClosure)
    _ = try await events.wait(after: baseline, matching: { $0 == .connected })

    let latest = try #require(await provider.latestTask)
    let sent = try await latest.sentEnvelopes
    #expect(sent.contains { $0.action == .join && $0.options?.channel == "lobby" })
}

@Test("enterForeground requests history when catchUpOnForeground is set")
func foregroundCatchUpRequestsHistory() async throws {
    let provider = MockWebSocketProvider()
    let client = XanoRealtimeClient(
        configuration: try testConfiguration(),
        provider: provider,
        delay: ImmediateDelay()
    )
    let lobby = await client.channel(
        "lobby",
        options: ChannelOptions(catchUpOnForeground: true)
    )
    let events = await collect(await lobby.events)
    _ = try await events.wait(matching: { $0 == .connected })
    let afterConnect = await events.all.count

    await client.enterBackground()
    _ = try await events.wait(after: afterConnect, matching: { $0 == .disconnected })
    let afterBackground = await events.all.count

    await client.enterForeground()
    _ = try await events.wait(after: afterBackground, matching: { $0 == .connected })

    let latest = try #require(await provider.latestTask)
    let sent = try await latest.sentEnvelopes
    #expect(sent.contains { $0.action == .history && $0.options?.channel == "lobby" })
}

@Test("leave sends a leave envelope")
func leaveSendsLeaveAction() async throws {
    let provider = MockWebSocketProvider()
    let client = XanoRealtimeClient(
        configuration: try testConfiguration(),
        provider: provider,
        delay: ImmediateDelay()
    )
    let lobby = await client.channel("lobby")
    let events = await collect(await lobby.events)
    _ = try await events.wait(matching: { $0 == .connected })

    let task = try #require(await provider.latestTask)
    await lobby.leave()

    let sent = try await task.sentEnvelopes
    #expect(sent.contains { $0.action == .leave && $0.options?.channel == "lobby" })
    #expect(await client.currentConnectionState == .disconnected)
}
