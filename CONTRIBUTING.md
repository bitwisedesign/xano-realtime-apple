# Contributing

Thanks for helping with XanoRealtime. This is an open-source Swift package (iOS 16+, macOS 13+) that wraps Xano Realtime over `URLSessionWebSocketTask`.

## Before you start

- Read [docs/Architecture.md](docs/Architecture.md) and [docs/ProtocolReference.md](docs/ProtocolReference.md).
- The wire protocol matches the official [Xano JS SDK](https://github.com/xano-inc/js-sdk). Prefer that repository (and this package's protocol docs) over unofficial payload sketches.
- This is a headless SDK: do not add UIKit, SwiftUI, AppKit, or app-lifecycle APIs to the domain core. The optional iOS lifecycle observer already lives behind `#if canImport(UIKit)` in `Lifecycle/`.

## Development setup

1. Install a recent Xcode that includes Swift 6.
2. Clone this repository and open `Package.swift` in Xcode, or work from the command line.
3. Install [SwiftLint](https://github.com/realm/SwiftLint) and keep it on your `PATH`.

No other package dependencies are required. Do not add Starscream or other WebSocket libraries.

## Build and test

Run these from the repository root. They need an unsandboxed shell (Xcode SDK paths fail under sandbox restrictions).

macOS:

```bash
swift build
```

iOS simulator — derive the SDK version; do not hardcode it:

```bash
IOS_SIM_VERSION=$(xcrun --sdk iphonesimulator --show-sdk-version | sed -E 's/^([0-9]+\.[0-9]+).*/\1/')
swift build \
  --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  --triple "arm64-apple-ios${IOS_SIM_VERSION}-simulator"
```

Tests run on the Mac host:

```bash
swift test
```

Do not use `xcodebuild` unless a maintainer asks for it.

After you change Swift files, run SwiftLint from this repository's checkout root (so it finds `.swiftlint.yml`):

```bash
swiftlint --fix --no-cache /absolute/path/to/edited.swift
swiftlint --quiet --no-cache /absolute/path/to/edited.swift
```

Run `--fix` and `--quiet` as separate commands.

## Architecture rules

The package is **Hexagonal (Ports & Adapters)** with **actors** and unidirectional **`AsyncStream`** delivery.

- Domain code (`Domain/`, `Models/`, `Channel/`, `Client/`, `Reliability/`, `Configuration/`) depends on ports only.
- Only files under `Sources/XanoRealtime/Adapters/` may use `URLSession` networking types.
- Tests inject `MockWebSocketProvider`. Unit tests must not hit the network.
- `WebSocketConnection`, `XanoRealtimeClient`, and `XanoRealtimeChannel` are actors. Do not add `@unchecked Sendable` or `nonisolated(unsafe)`.

See [docs/Architecture.md](docs/Architecture.md).

## Code conventions

- Swift 6 language mode, `Sendable` throughout.
- Triple-slash DocC (`///`) on every public and internal type, initializer, function, and property. Usage examples belong on public API only.
- Prefer `try` over `try?`. If you swallow an error on purpose (best-effort teardown), put an inline comment on that line explaining why.
- Do not force-unwrap (`!`) in tests — use `try #require(...)`.
- Tests use Swift Testing (`@Test`, `#expect`, `#require`), not XCTest.
- Do not use `Task.sleep` to wait for state changes. Inject `ImmediateDelay` / the mock socket and assert on streams or completed `async` results. Wait helpers must be bounded (≥ 2 seconds on CI).
- New `.swift` files are discovered automatically; you do not need to edit an Xcode project file.

## Public API harness

`Tests/XanoRealtimeAPIValidator/` is the approved public surface. `swift test` fails if a public type, member, or enum case is added or removed without updating that target, if a function/init/subscript argument list changes (inventory keys use Swift selector form, e.g. `enterBackground()` vs `enterBackground(force:)`), or if a compile-lock signature no longer type-checks.

- Update the harness in the same PR as the API change, and only when that change is expected and approved. Do not edit it just to make tests green.
- Do not hand-edit `PublicAPIInventory.swift`. After an approved API change, regenerate it and review the diff:

```bash
REGENERATE_PUBLIC_API_INVENTORY=1 swift test --filter scannedPublicAPIMatchesApprovedInventory
```
- Use `import XanoRealtime` only. `@testable import` would lock internals and defeat the check.
- Semver from an approved harness diff: inventory/lock **only gained** symbols, with no removals or signature edits → **minor**. Anything removed or re-signed, or a new enum case (exhaustive-switch churn) → **major**.

### Deprecating a public API

A deprecated symbol is still public API. Keep it in the compile-lock and `PublicAPIInventory` until it is actually removed (that removal is a **major** bump). The compile-lock will then emit deprecation warnings; with `-warnings-as-errors` those fail the `XanoRealtimeAPIValidator` target.

Do **not** drop the lock or the inventory entry to silence that. On the first deprecation, exempt that diagnostic group on the validator target only (leave `XanoRealtimeTests` unchanged). Warning-group flags need Swift 6.1 (SE-0443). If the package is still `swift-tools-version:6.0`, bump the tools version (and the README Swift floor) in the same PR.

In `Package.swift`, on `XanoRealtimeAPIValidator` only, keep `-warnings-as-errors` first, then downgrade deprecations. Order matters: if `-Wwarning` comes first, `-warnings-as-errors` upgrades deprecation again.

```swift
.testTarget(
    name: "XanoRealtimeAPIValidator",
    dependencies: ["XanoRealtime"],
    swiftSettings: [
        .unsafeFlags([
            "-warnings-as-errors",
            "-Wwarning", "DeprecatedDeclaration"
        ])
    ]
)
```

Unused bindings, isolation, and other harness mistakes stay fatal. Deprecation stays a warning until the symbol is removed and the harness is updated for the major bump.

## Pull requests

- Keep the change focused. Protocol or public-API changes should update `docs/` and `Tests/XanoRealtimeAPIValidator/` in the same PR.
- Include tests for new behavior, especially encode/decode, URL/subprotocol assembly, reconnect close codes, and channel fan-out.
- Describe *why* the change exists in the PR body.
- Do not commit secrets, instance tokens, or machine-specific paths.

## Reporting issues

Include the SDK version (or commit), Apple platform and OS version, and a minimal reproduction. Do not paste realtime auth tokens. If the report is about the wire protocol, attach a redacted envelope (action + options + payload shape) rather than a full session dump.

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
