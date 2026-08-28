# Foreground and background

The connection actor does not import UIKit or AppKit. Lifecycle is a portable API plus an opt-in iOS bridge.

## Portable API

Call these from your app's own lifecycle observers (or from a wrapper):

```swift
await client.enterBackground()
await client.enterForeground()
```

`enterBackground()` closes the socket with code `1000` and **suppresses** auto-reconnect so the SDK does not fight process suspension.

`enterForeground()` reconnects, re-joins registered channels, and — when `ChannelOptions.catchUpOnForeground` is `true` — sends a `history` request to backfill messages missed while suspended.

## Opt-in UIKit bridge

Set `automaticLifecycleHandling` to `true` on iOS to observe:

- `UIApplication.didEnterBackgroundNotification`
- `UIApplication.willEnterForegroundNotification`

The observer lives in `Lifecycle/LifecycleBridge.swift` behind `#if canImport(UIKit) && os(iOS)`. macOS builds compile a no-op placeholder. Default is `false` so library-only hosts are not surprised by notification observers.

## Background tasks

iOS gives a short window after backgrounding. This SDK does **not** call `beginBackgroundTask(withName:expirationHandler:)`. If you need to finish an in-flight send before suspend, start a background task in the **app** around `enterBackground()`. Keeping the socket alive in the background is usually the wrong tradeoff: the OS will suspend the process, and the heartbeat cannot run.

When the app is backgrounded, stop expecting realtime events until `enterForeground()` completes.
