import Foundation
import Testing
@testable import XanoRealtime

@Test("builds wss://host/rt/canonical and discards the HTTP path")
func configurationBuildsRealtimeURL() throws {
    let base = try #require(URL(string: "https://x8ki-letl-twmt.n7.xano.io/api:group"))
    let configuration = XanoRealtimeConfiguration(
        instanceBaseUrl: base,
        connectionCanonical: "1lK90n16tnnylJpJ0Xa7Km6_KxA",
        realtimeAuthToken: "jwt-token"
    )

    let url = try configuration.makeConnectionURL()
    #expect(url.absoluteString == "wss://x8ki-letl-twmt.n7.xano.io/rt/1lK90n16tnnylJpJ0Xa7Km6_KxA")
    #expect(configuration.webSocketProtocols == ["jwt-token"])
}

@Test("falls back to apiGroupBaseUrl and connectionHash")
func configurationFallsBackToDeprecatedFields() throws {
    let base = try #require(URL(string: "https://fallback.xano.io"))
    let configuration = XanoRealtimeConfiguration(
        apiGroupBaseUrl: base,
        connectionCanonical: "",
        connectionHash: "legacyHash"
    )

    let url = try configuration.makeConnectionURL()
    #expect(url.absoluteString == "wss://fallback.xano.io/rt/legacyHash")
    #expect(configuration.webSocketProtocols.isEmpty)
}

@Test("rejects a configuration with no host")
func configurationRejectsMissingHost() {
    let configuration = XanoRealtimeConfiguration(
        connectionCanonical: "abc"
    )
    #expect(throws: XanoRealtimeError.self) {
        try configuration.makeConnectionURL()
    }
}

@Test("rejects a configuration with no connection identifier")
func configurationRejectsMissingCanonical() throws {
    let base = try #require(URL(string: "https://example.xano.io"))
    let configuration = XanoRealtimeConfiguration(
        instanceBaseUrl: base,
        connectionCanonical: ""
    )
    #expect(throws: XanoRealtimeError.self) {
        try configuration.makeConnectionURL()
    }
}
