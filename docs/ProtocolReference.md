# Protocol reference

Wire format matches the official Xano JS SDK (`xano-inc/js-sdk`). This is **not** the flat `{ action, channel, data }` sketch sometimes shown in unofficial notes.

## Connection URL

```text
wss://{hostname}/rt/{realtimeConnectionCanonical}
```

- Hostname comes from `instanceBaseUrl` or `apiGroupBaseUrl`. The HTTP path is discarded.
- Scheme is always `wss`.
- Auth JWT is the WebSocket **subprotocol** (`Sec-WebSocket-Protocol`), never a query parameter or join-payload field.

## Envelope

Both directions use:

```json
{
  "action": "message",
  "client": {
    "socketId": "…",
    "extras": {},
    "permissions": { "dbo_id": 1, "row_id": 2 }
  },
  "options": {
    "channel": "lobby",
    "socketId": "optional-target",
    "authenticated": true
  },
  "payload": {}
}
```

`client` is present on inbound frames when the server includes a sender. `payload` is `null` for `leave` and `history` requests.

## Client → server

| Action | `options` | `payload` |
| --- | --- | --- |
| `join` | `{ channel }` | `{ history, presence }` |
| `leave` | `{ channel }` | `null` |
| `message` | `{ channel, authenticated?, socketId? }` | application JSON |
| `history` | `{ channel }` | `null` |

## Server → client

| Action | Typical `payload` |
| --- | --- |
| `connection_status` | `{ "status": "connected" \| "disconnected" }` |
| `message` | application JSON |
| `presence_full` | `{ "presence": [Peer] }` |
| `presence_update` | `{ "action": "join" \| "leave", "presence": Peer }` |
| `history` | opaque JSON |
| `error` | opaque JSON |
| `event` | opaque JSON |
| `join` / `leave` | opaque JSON |

The SDK also **synthesizes** `connection_status` locally on transport open and close, matching the JS SDK.

## Peer

```json
{
  "socketId": "…",
  "extras": {},
  "permissions": { "dbo_id": 12, "row_id": 34 }
}
```

Swift maps `dbo_id` / `row_id` to `RealtimePermissions.dboID` / `rowID`.

## Channel options

| Option | Default | Effect |
| --- | --- | --- |
| `history` | `false` | Sent in join payload |
| `presence` | `false` | Sent in join payload |
| `queueOfflineActions` | `false` | JS parity: default off. Not consulted at send time; `XanoRealtimeConfiguration.queueOfflineActions` is the flag that queues. |
| `catchUpOnForeground` | `false` | After `enterForeground()`, send `history` |
