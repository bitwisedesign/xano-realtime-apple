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

## Pull requests

- Keep the change focused. Protocol or public-API changes should update `docs/` in the same PR.
- Include tests for new behavior, especially encode/decode, URL/subprotocol assembly, reconnect close codes, and channel fan-out.
- Describe *why* the change exists in the PR body.
- Do not commit secrets, instance tokens, or machine-specific paths.

## Reporting issues

Include the SDK version (or commit), Apple platform and OS version, and a minimal reproduction. Do not paste realtime auth tokens. If the report is about the wire protocol, attach a redacted envelope (action + options + payload shape) rather than a full session dump.

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
