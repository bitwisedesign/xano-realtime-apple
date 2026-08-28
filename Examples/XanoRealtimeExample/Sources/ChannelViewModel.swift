import Foundation
import XanoRealtime

/// One row shown in the example channel transcript.
struct DisplayedMessage: Identifiable, Equatable, Sendable {
    /// Stable identity for `ForEach`.
    let id: UUID
    /// Text shown in the list.
    let text: String
    /// Visual role of the row.
    let kind: Kind

    /// Visual role of a transcript row.
    enum Kind: String, Equatable, Sendable {
        /// Application payload received on the channel.
        case inbound
        /// Local lifecycle or presence note.
        case system
        /// Transport, send, or server failure.
        case error
    }

    /// Creates a transcript row with a new identity.
    ///
    /// - Parameters:
    ///   - text: Display text.
    ///   - kind: Visual role.
    init(text: String, kind: Kind) {
        self.id = UUID()
        self.text = text
        self.kind = kind
    }
}

/// Binds one `XanoRealtimeClient` and one channel to SwiftUI.
@MainActor
final class ChannelViewModel: ObservableObject {
    // MARK: - Properties

    /// Multiplexed socket lifecycle.
    @Published private(set) var connectionState: ConnectionState = .disconnected
    /// Transcript of inbound messages and local notes.
    @Published private(set) var messages: [DisplayedMessage] = []
    /// Count of peers from the last presence snapshot or update.
    @Published private(set) var presenceCount = 0
    /// Draft text bound to the compose field.
    @Published var draft = ""
    /// Channel name taken from xcconfig.
    let channelName: String
    /// Session facade.
    private let client: XanoRealtimeClient
    /// Joined channel handle, set after `channel(_:options:)` returns.
    private var channel: XanoRealtimeChannel?
    /// Consumes `channel.events`.
    private var eventsTask: Task<Void, Never>?
    /// Consumes `client.connectionState`.
    private var stateTask: Task<Void, Never>?

    // MARK: - Initialization

    /// Creates a view model and starts observing the configured channel.
    ///
    /// - Parameter config: Host, canonical, token, and channel name from Info.plist.
    init(config: AppConfig) {
        self.channelName = config.channelName
        self.client = XanoRealtimeClient(configuration: config.configuration)
        start()
    }

    deinit {
        eventsTask?.cancel()
        stateTask?.cancel()
    }

    // MARK: - Public API

    /// Sends the current draft as `{ "text": draft }` on the channel.
    func sendDraft() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let channel else {
            return
        }
        do {
            try await channel.send(["text": text])
            draft = ""
        } catch {
            append(text: Self.displayError(error), kind: .error)
        }
    }

    /// Whether Send is enabled.
    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && channel != nil
    }

    /// Human-readable connection badge.
    var connectionLabel: String {
        switch connectionState {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        case .reconnecting(let attempt):
            return "Reconnecting (\(attempt))"
        }
    }

    // MARK: - Private Helpers

    /// Joins the configured channel and mirrors events onto published state.
    private func start() {
        let client = client
        let channelName = channelName
        eventsTask = Task { [weak self] in
            let handle = await client.channel(
                channelName,
                options: ChannelOptions(history: true, presence: true)
            )
            guard let self else {
                return
            }
            self.channel = handle
            for await event in await handle.events {
                self.apply(event)
            }
        }
        stateTask = Task { [weak self] in
            for await state in await client.connectionState {
                self?.connectionState = state
            }
        }
    }

    /// Maps one `RealtimeEvent` onto published fields.
    ///
    /// - Parameter event: Channel event.
    private func apply(_ event: RealtimeEvent) {
        switch event {
        case .connected:
            append(text: "Connected to \(channelName)", kind: .system)
        case .disconnected:
            append(text: "Disconnected", kind: .system)
        case .message(let message):
            append(text: Self.displayText(from: message.payload), kind: .inbound)
        case .presenceFull(let peers):
            presenceCount = peers.count
            append(text: "Presence: \(peers.count) peer(s)", kind: .system)
        case .presenceUpdate(let action, let peer):
            switch action {
            case .join:
                presenceCount += 1
                append(text: "Peer joined \(peer.socketId)", kind: .system)
            case .leave:
                presenceCount = max(presenceCount - 1, 0)
                append(text: "Peer left \(peer.socketId)", kind: .system)
            }
        case .history:
            append(text: "History batch received", kind: .system)
        case .error(let error):
            append(text: Self.displayError(error), kind: .error)
        case .unhandled(let action, let payload):
            if let payload {
                append(text: "Unhandled action \(action): \(Self.jsonText(payload))", kind: .system)
            } else {
                append(text: "Unhandled action: \(action)", kind: .system)
            }
        }
    }

    /// Appends a transcript row.
    ///
    /// - Parameters:
    ///   - text: Display text.
    ///   - kind: Visual role.
    private func append(text: String, kind: DisplayedMessage.Kind) {
        messages.append(DisplayedMessage(text: text, kind: kind))
    }

    /// Prefers `payload.text` when it is a string; otherwise describes the JSON tree.
    ///
    /// - Parameter payload: Inbound message body.
    /// - Returns: Display text.
    private static func displayText(from payload: JSONValue) -> String {
        if case .string(let text) = payload["text"] {
            return text
        }
        return jsonText(payload)
    }

    /// Formats a thrown or streamed error, including the server payload when present.
    ///
    /// - Parameter error: Failure from send or `RealtimeEvent.error`.
    /// - Returns: Display text.
    private static func displayError(_ error: Error) -> String {
        guard let domain = error as? XanoRealtimeError else {
            return error.localizedDescription
        }
        switch domain {
        case .server(let payload):
            return "Server error: \(jsonText(payload))"
        default:
            return domain.localizedDescription
        }
    }

    /// Pretty-printed JSON for a payload, falling back to a debug description.
    ///
    /// - Parameter value: JSON tree.
    /// - Returns: Display text.
    private static func jsonText(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        // Best-effort: the transcript must still show something if re-encoding fails.
        guard let data = try? encoder.encode(value),
              let text = String(data: data, encoding: .utf8) else {
            return String(describing: value)
        }
        return text
    }
}
