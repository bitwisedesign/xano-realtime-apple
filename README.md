# XanoRealtime

A native Swift SDK for [Xano Realtime](https://docs.xano.com/) on Apple platforms. Xano does not ship an official Apple SDK; this package speaks the same WebSocket protocol as the [official JavaScript SDK](https://github.com/xano-inc/js-sdk).

**Platforms:** iOS 16+, macOS 13+  
**Transport:** `URLSessionWebSocketTask` (no Starscream or other socket libraries)  
**Concurrency:** Swift actors + `AsyncStream`

## Install

Add the package with Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/bitwisedesign/xano-realtime-apple.git", from: "0.1.0")
]
```

Then add the `XanoRealtime` product to your target.

## Quick start

```swift
import XanoRealtime

let configuration = XanoRealtimeConfiguration(
    instanceBaseUrl: URL(string: "https://x8ki-letl-twmt.n7.xano.io")!,
    connectionCanonical: "YOUR_CONNECTION_CANONICAL",
    realtimeAuthToken: jwt // optional; sent as the WebSocket subprotocol
)

let client = XanoRealtimeClient(configuration: configuration)
let lobby = await client.channel("lobby", options: ChannelOptions(presence: true))

for await event in await lobby.events {
    switch event {
    case .connected:
        try await lobby.send(["text": "hello"])
    case .message(let message):
        print(message.payload)
    case .presenceFull(let peers):
        print(peers)
    case .error(let error):
        print(error)
    default:
        break
    }
}
```

## Features

| Feature | Behavior |
| --- | --- |
| Protocol | Nested `{ action, options, payload }` envelopes on `wss://{host}/rt/{canonical}` |
| Auth | JWT as `Sec-WebSocket-Protocol` (not a join-payload field) |
| Channels | One socket, many channels, filtered by `options.channel` |
| Events | Per-channel `AsyncStream<RealtimeEvent>` |
| Reconnect | Exponential backoff (1s → 60s) on close codes `1006`, `1011`–`1014`, `4000` |
| Heartbeat | WebSocket ping/pong (not in the JS SDK; see [docs/Reconnection.md](docs/Reconnection.md)) |
| Lifecycle | Portable `enterBackground()` / `enterForeground()`; optional iOS UIKit bridge |

## Documentation

- [Getting started](docs/GettingStarted.md)
- [Architecture](docs/Architecture.md)
- [Protocol reference](docs/ProtocolReference.md)
- [Reconnection and heartbeats](docs/Reconnection.md)
- [Foreground / background](docs/Lifecycle.md)
- [Contributing](CONTRIBUTING.md)

## License

MIT. See [LICENSE](LICENSE).
