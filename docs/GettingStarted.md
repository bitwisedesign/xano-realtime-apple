# Getting started

## Configure

`XanoRealtimeConfiguration` needs a hostname and a connection identifier. The hostname is taken from `instanceBaseUrl` (preferred) or `apiGroupBaseUrl`. Any HTTP path is discarded, matching the JS SDK.

```swift
let configuration = XanoRealtimeConfiguration(
    instanceBaseUrl: URL(string: "https://YOUR_INSTANCE.xano.io")!,
    connectionCanonical: "YOUR_CONNECTION_CANONICAL",
    realtimeAuthToken: jwt,          // optional
    pingInterval: .seconds(20),      // nil disables the heartbeat
    queueOfflineActions: false,
    automaticLifecycleHandling: false
)
```

The socket URL becomes `wss://YOUR_INSTANCE.xano.io/rt/YOUR_CONNECTION_CANONICAL`.

## Connect and subscribe

Creating a channel opens the multiplexed socket if it is not already open:

```swift
let client = XanoRealtimeClient(configuration: configuration)
let lobby = await client.channel(
    "lobby",
    options: ChannelOptions(history: false, presence: true)
)

for await event in await lobby.events {
    // ...
}
```

Dropping the `events` iterator does **not** leave the channel. Call `await lobby.leave()`.

## Send

```swift
try await lobby.send(["text": "hello"])
try await lobby.send(["text": "members only"], authenticated: true)
try await lobby.message(["text": "private"], to: peerSocketId)
try await lobby.requestHistory()
```

## Presence

When `ChannelOptions.presence` is `true`, the server sends `presence_full` and `presence_update`. The channel updates an in-memory cache before emitting those events:

```swift
let peers = await lobby.presence
```

## Teardown

```swift
await lobby.leave()          // leave one channel; last leave closes the socket
await client.disconnect()    // close immediately, no reconnect
```

## Auth token rotation

`realtimeAuthToken` must be minted on Xano's **live** datasource. Tokens from any other data source leave the socket anonymous. See [KNOWN_LIMITATIONS.md](../KNOWN_LIMITATIONS.md).

```swift
await client.setAuthToken(newJWT) // close code 4000, then reconnect with the new subprotocol
```
