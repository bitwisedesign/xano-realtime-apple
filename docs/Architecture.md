# Architecture

This package uses a **Hexagonal (Ports & Adapters)** core, an **actor** concurrency model, and **unidirectional `AsyncStream`** event delivery. It is a headless SDK, not an app architecture (not MVVM, VIPER, TCA, or Clean Architecture).

## Hexagon

```text
Integrator app
    → XanoRealtimeClient (facade, actor)
        → XanoRealtimeChannel (actor)
            → Domain: models, state machine, backoff, fan-out
                → WebSocketProviding (port)
                    → URLSessionWebSocketProvider (production adapter)
                    → MockWebSocketProvider (tests)
```

### Dependency rule

Nothing under `Domain/`, `Models/`, `Channel/`, `Client/`, `Reliability/`, or `Configuration/` may use `URLSession` networking types. Only `Sources/XanoRealtime/Adapters/` may. The port types (`WebSocketProviding`, `WebSocketTasking`, `WebSocketMessage`, `WebSocketLifecycleSink`) are the boundary. Those ports, `URLSessionWebSocketProvider`, and the client's injected-transport initializer are module-internal; integrators use `XanoRealtimeClient(configuration:)`.

`.cursor/rules/architecture.mdc` restates this for agents working in the repo.

## Actors

| Type | Role |
| --- | --- |
| `WebSocketConnection` | Owns the active task, state machine, receive loop, heartbeat, reconnect, offline queue |
| `XanoRealtimeClient` | Facade, channel registry, envelope fan-out, auto-join |
| `XanoRealtimeChannel` | Per-channel `AsyncStream`, presence cache, send/leave |

Mutable socket state lives inside `WebSocketConnection`. There are no locks and no `@unchecked Sendable`.

## Event flow

1. The adapter delivers frames through `WebSocketTasking.receive()`.
2. `WebSocketConnection` decodes `RealtimeEnvelope` values and yields `ConnectionEvent`s.
3. `XanoRealtimeClient` fans envelopes out: global `connection_status` to every channel; otherwise by `options.channel`.
4. Each `XanoRealtimeChannel` maps the envelope to `RealtimeEvent` and yields on its `AsyncStream`.

On open, the connection synthesizes `connection_status: connected`. The client then re-sends `join` for every registered channel (JS SDK parity).

## Single socket, many channels

One WebSocket multiplexes all channels for a client. Join, leave, message, and history actions include `options.channel`. Inbound frames without a channel are treated as global.

`AsyncStream` uses `.bufferingNewest(n)` (default 64). A late subscriber can miss earlier events. Subscribe before you depend on `connected`.
