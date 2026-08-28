import Foundation

#if canImport(UIKit) && os(iOS)
import UIKit

/// Observes iOS app foreground/background and forwards them to ``XanoRealtimeClient``.
///
/// Enabled only when ``XanoRealtimeConfiguration/automaticLifecycleHandling`` is `true`.
/// The core connection actor never imports UIKit.
@MainActor
final class LifecycleBridge {
    // MARK: - Properties

    /// Client that receives lifecycle calls.
    private let client: XanoRealtimeClient

    // MARK: - Initialization

    /// Starts observing `UIApplication` lifecycle notifications.
    ///
    /// - Parameter client: Realtime client to suspend and resume.
    init(client: XanoRealtimeClient) {
        self.client = client
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(didEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(willEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Private Helpers

    /// Forwards backgrounding to the client.
    @objc
    private func didEnterBackground() {
        Task {
            await client.enterBackground()
        }
    }

    /// Forwards foregrounding to the client.
    @objc
    private func willEnterForeground() {
        Task {
            await client.enterForeground()
        }
    }
}
#else

/// Placeholder used on platforms without UIKit so the client can keep a stored property.
final class LifecycleBridge: Sendable {
    /// Creates an inactive bridge.
    ///
    /// - Parameter client: Unused; accepted so call sites compile on every platform.
    init(client _: XanoRealtimeClient) {}
}
#endif
