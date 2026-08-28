import Foundation
import XanoRealtime

/// Runtime settings loaded from Info.plist keys that Xcode substitutes from `Secrets.xcconfig`.
struct AppConfig: Equatable, Sendable {
    /// SDK configuration built from the xcconfig host, canonical, and optional token.
    let configuration: XanoRealtimeConfiguration
    /// Single channel name to join.
    let channelName: String
}

/// Raw Info.plist values after xcconfig substitution, for on-device inspection.
struct ConfigurationSnapshot: Equatable, Sendable {
    /// `XANO_INSTANCE_HOST` as substituted into Info.plist.
    let instanceHost: String
    /// `XANO_CONNECTION_CANONICAL` as substituted into Info.plist.
    let connectionCanonical: String
    /// `XANO_REALTIME_AUTH_TOKEN` as substituted into Info.plist.
    let realtimeAuthToken: String
}

/// Outcome of reading example-app settings from the main bundle.
enum AppConfigurationState: Equatable, Sendable {
    /// Required keys were present and a configuration could be built.
    case ready(AppConfig)
    /// One or more required Info.plist keys were missing or empty.
    case missingConfiguration(missingKeys: [String])
}

enum AppConfigLoader {
    // MARK: - Public API

    /// Reads the three inspectable xcconfig keys from `bundle` without validating them.
    ///
    /// - Parameter bundle: Bundle whose Info.plist contains the substituted values.
    /// - Returns: Raw host, canonical, and token strings (empty when absent).
    static func snapshot(from bundle: Bundle = .main) -> ConfigurationSnapshot {
        ConfigurationSnapshot(
            instanceHost: trimmedValue(for: "XanoInstanceHost", in: bundle),
            connectionCanonical: trimmedValue(for: "XanoConnectionCanonical", in: bundle),
            realtimeAuthToken: trimmedValue(for: "XanoRealtimeAuthToken", in: bundle)
        )
    }

    /// Reads Xano keys from `bundle` and returns a ready config or a missing-key list.
    ///
    /// - Parameter bundle: Bundle whose Info.plist contains the substituted xcconfig values.
    /// - Returns: `.ready` when host, canonical, and channel name are non-empty.
    static func load(from bundle: Bundle = .main) -> AppConfigurationState {
        var missingKeys: [String] = []

        let host = trimmedValue(for: "XanoInstanceHost", in: bundle)
        if host.isEmpty {
            missingKeys.append("XanoInstanceHost")
        }

        let connectionCanonical = trimmedValue(for: "XanoConnectionCanonical", in: bundle)
        if connectionCanonical.isEmpty {
            missingKeys.append("XanoConnectionCanonical")
        }

        let channelName = trimmedValue(for: "XanoChannelName", in: bundle)
        if channelName.isEmpty {
            missingKeys.append("XanoChannelName")
        }

        let authToken = trimmedValue(for: "XanoRealtimeAuthToken", in: bundle)

        guard missingKeys.isEmpty else {
            return .missingConfiguration(missingKeys: missingKeys)
        }

        guard let instanceBaseUrl = URL(string: "https://\(host)"), instanceBaseUrl.host != nil else {
            return .missingConfiguration(missingKeys: ["XanoInstanceHost"])
        }

        let configuration = XanoRealtimeConfiguration(
            instanceBaseUrl: instanceBaseUrl,
            connectionCanonical: connectionCanonical,
            realtimeAuthToken: authToken.isEmpty ? nil : authToken
        )
        return .ready(AppConfig(configuration: configuration, channelName: channelName))
    }

    // MARK: - Private Helpers

    /// Returns a trimmed string for `key`, or an empty string when the key is absent.
    ///
    /// - Parameters:
    ///   - key: Info.plist key.
    ///   - bundle: Bundle to read.
    /// - Returns: Trimmed value, or `""`.
    private static func trimmedValue(for key: String, in bundle: Bundle) -> String {
        guard let rawValue = bundle.object(forInfoDictionaryKey: key) as? String else {
            return ""
        }
        return rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
