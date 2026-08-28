# XanoRealtime example app

A SwiftUI app that joins a single Xano Realtime channel using this repository's SDK. It builds for iOS 16+ and macOS 13+. Connection settings come from a git-ignored xcconfig — you do not edit source to try the app.

## Prerequisites

- Xcode 16 or newer (Swift 6)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Configure

From this directory:

```bash
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
```

Edit `Config/Secrets.xcconfig` (do not commit it):

| Key | Required | Notes |
| --- | --- | --- |
| `XANO_INSTANCE_HOST` | Yes | Hostname only. Do not write `https://` — `//` starts a comment in xcconfig. |
| `XANO_CONNECTION_CANONICAL` | Yes | Realtime connection identifier from Xano. |
| `XANO_REALTIME_AUTH_TOKEN` | No | JWT sent as the WebSocket subprotocol. Leave empty for an unauthenticated join. |
| `XANO_CHANNEL_NAME` | Yes | Channel to join. Defaults to `lobby` in the template. |
| `DEVELOPMENT_TEAM_ID` | No | 10-character Apple team ID. Needed only to run on a physical iOS device. |

## Generate and run

```bash
xcodegen generate
open XanoRealtimeExample.xcodeproj
```

Pick an iOS Simulator or My Mac and run. If required keys are empty, the app shows which Info.plist keys are missing instead of connecting.
