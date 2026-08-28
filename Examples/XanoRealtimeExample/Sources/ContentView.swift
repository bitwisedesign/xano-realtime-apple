import SwiftUI

/// Root content: setup instructions or the single-channel transcript.
struct ContentView: View {
    // MARK: - Properties

    /// Result of reading xcconfig-backed Info.plist keys.
    private let configurationState: AppConfigurationState
    /// Raw substituted values for the configuration sheet.
    private let snapshot: ConfigurationSnapshot

    // MARK: - Initialization

    /// Creates the root view, loading configuration from the main bundle.
    init() {
        configurationState = AppConfigLoader.load()
        snapshot = AppConfigLoader.snapshot()
    }

    // MARK: - Public API

    var body: some View {
        switch configurationState {
        case .ready(let config):
            ChannelSessionView(config: config, snapshot: snapshot)
        case .missingConfiguration(let missingKeys):
            MissingConfigurationView(missingKeys: missingKeys, snapshot: snapshot)
        }
    }
}

/// Transcript and compose UI for one joined channel.
struct ChannelSessionView: View {
    // MARK: - Properties

    /// Session bound to the configured channel.
    @StateObject private var viewModel: ChannelViewModel
    /// Raw substituted xcconfig values.
    private let snapshot: ConfigurationSnapshot
    /// Whether the configuration sheet is visible.
    @State private var isShowingConfiguration = false

    // MARK: - Initialization

    /// Creates the session view and starts the client.
    ///
    /// - Parameters:
    ///   - config: Validated host, canonical, and channel name.
    ///   - snapshot: Raw Info.plist values for inspection.
    init(config: AppConfig, snapshot: ConfigurationSnapshot) {
        _viewModel = StateObject(wrappedValue: ChannelViewModel(config: config))
        self.snapshot = snapshot
    }

    // MARK: - Public API

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(viewModel.connectionLabel)
                        .font(.headline)
                    Spacer()
                    Text("\(viewModel.channelName) · \(viewModel.presenceCount) peer(s)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                List(viewModel.messages) { message in
                    Text(message.text)
                        .foregroundStyle(color(for: message.kind))
                        .textSelection(.enabled)
                }

                HStack {
                    TextField("Message", text: $viewModel.draft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            Task {
                                await viewModel.sendDraft()
                            }
                        }
                    Button("Send") {
                        Task {
                            await viewModel.sendDraft()
                        }
                    }
                    .disabled(!viewModel.canSend)
                }
                .padding()
            }
            .navigationTitle("Xano Realtime")
            .inlineNavigationBarTitle()
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Config") {
                        isShowingConfiguration = true
                    }
                }
            }
            .sheet(isPresented: $isShowingConfiguration) {
                ConfigurationValuesView(snapshot: snapshot)
            }
        }
    }

    // MARK: - Private Helpers

    /// Color for a transcript row.
    ///
    /// - Parameter kind: Visual role.
    /// - Returns: A platform color.
    private func color(for kind: DisplayedMessage.Kind) -> Color {
        switch kind {
        case .inbound:
            return .primary
        case .system:
            return .secondary
        case .error:
            return .red
        }
    }
}

/// Shown when required xcconfig values were not substituted into Info.plist.
struct MissingConfigurationView: View {
    // MARK: - Properties

    /// Info.plist keys that were empty after substitution.
    let missingKeys: [String]
    /// Raw substituted xcconfig values.
    let snapshot: ConfigurationSnapshot
    /// Whether the configuration sheet is visible.
    @State private var isShowingConfiguration = false

    // MARK: - Public API

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Missing configuration")
                    .font(.title2)
                Text(
                    "Copy Config/Secrets.example.xcconfig to Config/Secrets.xcconfig, fill in the required values, then run xcodegen generate and build again."
                )
                Text("Missing keys:")
                    .font(.headline)
                ForEach(missingKeys, id: \.self) { key in
                    Text(key)
                        .font(.body.monospaced())
                }
            }
            .padding()
            .frame(maxWidth: 560, alignment: .leading)
            .navigationTitle("Xano Realtime")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button("Config") {
                        isShowingConfiguration = true
                    }
                }
            }
            .sheet(isPresented: $isShowingConfiguration) {
                ConfigurationValuesView(snapshot: snapshot)
            }
        }
    }
}

/// Modal listing the substituted xcconfig values the process actually loaded.
struct ConfigurationValuesView: View {
    // MARK: - Properties

    /// Raw Info.plist values.
    let snapshot: ConfigurationSnapshot
    /// Dismisses the sheet.
    @Environment(\.dismiss) private var dismiss

    // MARK: - Public API

    var body: some View {
        NavigationStack {
            List {
                configurationRow(title: "XANO_INSTANCE_HOST", value: snapshot.instanceHost)
                configurationRow(title: "XANO_CONNECTION_CANONICAL", value: snapshot.connectionCanonical)
                configurationRow(
                    title: "XANO_REALTIME_AUTH_TOKEN",
                    value: snapshot.realtimeAuthToken,
                    showLength: true
                )
            }
            .navigationTitle("Configuration")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Private Helpers

    /// One labeled, selectable value row.
    ///
    /// - Parameters:
    ///   - title: xcconfig key name.
    ///   - value: Substituted string.
    ///   - showLength: When `true`, appends the character count.
    /// - Returns: A list row.
    @ViewBuilder
    private func configurationRow(title: String, value: String, showLength: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            if value.isEmpty {
                Text("(empty)")
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                Text(value)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                if showLength {
                    Text("\(value.count) characters")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Extensions

/// Platform-specific navigation chrome for the example app.
extension View {
    /// Uses an inline navigation-bar title on iOS. A no-op on macOS, where that API does not exist.
    @ViewBuilder
    func inlineNavigationBarTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}
