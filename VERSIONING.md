# Versioning

This package classifies public API changes using SemVer intent, but **release tags stay in `0.MINOR.PATCH`** until a 1.0 precondition is met. The leading `0` will not advance.

## Why 0.x

XanoRealtime is an unofficial, community Swift SDK. Xano does not ship an official Apple SDK; this package speaks the same WebSocket protocol as the [official JavaScript SDK](https://github.com/xano-inc/js-sdk). Declaring `1.0.0` would imply a stability and ownership guarantee this project cannot make on Xano's behalf.

The public API harness in `Tests/XanoRealtimeAPIValidator/` still detects additions, removals, and signature changes so contributors can treat breaking work as a deliberate, documented event. Classification does not by itself authorize a `1.x` tag.

## Preconditions for 1.0.0

The major component stays `0` until **at least one** of the following is true:

- A contributor from Xano becomes involved in this repository, or
- Xano forks this repository and inherits the work.

Until then, every release is `0.x.y`.

## How changes map to tags at 0.x

The harness in [`CONTRIBUTING.md`](CONTRIBUTING.md#public-api-harness) still classifies an approved inventory/lock diff as it does today:

| Harness classification | SemVer intent | Tag while major is `0` |
| --- | --- | --- |
| Inventory/lock **only gained** symbols (no removals or signature edits) | minor | Patch or minor bump of `0.x` |
| Symbol **removed** or **re-signed**, or a **new enum case** (exhaustive-switch churn) | major | **Minor** bump of `0.x`. Call the change out as breaking in the release notes. |

A "major"-classified change is allowed. It does **not** increment the leading `0`. Consumers who resolve with `from: "0.1.0"` should treat `0.x` minor bumps as potentially breaking.

That matches how Swift Package Manager already treats `0.x`: `from: "0.1.0"` does not promise a stable public surface across `0.y` releases. Pinning the major at `0` is honest about that.

## Consumer guidance

If you need a stable surface while the package is at `0.x`, pin an exact tag or use `.upToNextMinor(from:)` rather than `from:`:

```swift
.package(url: "https://github.com/bitwisedesign/xano-realtime-apple.git", .upToNextMinor(from: "0.1.0"))
```

`from:` will accept later `0.y` releases, including ones that ship breaking API changes.

## When a precondition is met

The first `1.0.0` will be a deliberate, announced release. This document will be revised at that time so tags follow the harness classification as ordinary SemVer (`MAJOR.MINOR.PATCH`).
