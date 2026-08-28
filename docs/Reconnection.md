# Reconnection and heartbeats

## Close codes

Matching the JS SDK (`realtime-state.ts`):

| Code | Meaning | Auto-reconnect |
| --- | --- | --- |
| `1000` | Normal closure (`disconnect()`, last channel left, background) | No |
| `1006` | Abnormal closure | Yes |
| `1011` | Internal error | Yes |
| `1012` | Service restart | Yes |
| `1013` | Try again later | Yes |
| `1014` | Bad gateway | Yes |
| `4000` | SDK-internal reconnect (`setAuthToken`) | Yes |

Reconnect attempts are unlimited. After a successful open, backoff resets.

## Backoff

Same sequence as the JS SDK:

1. First wait: **1 second**
2. Each attempt doubles the delay
3. Cap: **60 seconds**

`ImmediateDelay` is injected in unit tests so this path does not sleep on the wall clock.

On reconnect the client re-sends `join` for every registered channel. If `queueOfflineActions` is `true`, queued outbound envelopes flush in order after `connected`.

## Heartbeat (deliberate divergence from the JS SDK)

The JS SDK has **no** ping/pong loop. Browsers keep WebSockets alive through the desktop network stack. Mobile is different.

Cellular connections are NATed. Carrier middleboxes drop idle TCP mappings (often after 5–30 minutes) **without** a FIN or RST. The `URLSessionWebSocketTask` still looks open. The app stops receiving events until a later write times out.

This SDK sends WebSocket **control** pings via `URLSessionWebSocketTask.sendPing` on `pingInterval` (default 20 seconds):

- Small control frames do not appear as channel `message` events.
- A missed pong is treated as transport failure and uses the same reconnect path as close code `1006`.
- Set `pingInterval` to `nil` to disable.

The heartbeat runs only while the socket is connected. `enterBackground()` stops it; `enterForeground()` reconnects and starts it again.

Do not remove the heartbeat solely to match the JS SDK. It exists for mobile carrier idle-kill mitigation.
