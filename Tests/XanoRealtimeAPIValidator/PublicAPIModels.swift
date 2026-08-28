import Foundation
import Testing
import XanoRealtime

@Test("public configuration API exists")
func publicConfigurationAPIExists() throws {
    let instanceURL = try #require(URL(string: "https://example.invalid"))
    var configuration = XanoRealtimeConfiguration(
        instanceBaseUrl: instanceURL,
        apiGroupBaseUrl: instanceURL,
        connectionCanonical: "canonical",
        connectionHash: "hash",
        realtimeAuthToken: "token",
        pingInterval: .seconds(20),
        pingTimeout: .seconds(10),
        queueOfflineActions: false,
        automaticLifecycleHandling: false,
        eventBufferSize: 64
    )
    configuration.instanceBaseUrl = instanceURL
    configuration.apiGroupBaseUrl = instanceURL
    configuration.connectionCanonical = "canonical"
    configuration.connectionHash = "hash"
    configuration.realtimeAuthToken = "token"
    configuration.pingInterval = .seconds(20)
    configuration.pingTimeout = .seconds(10)
    configuration.queueOfflineActions = false
    configuration.automaticLifecycleHandling = false
    configuration.eventBufferSize = 64
    requireSendable(configuration)
    requireEquatable(configuration)

    var options = ChannelOptions(
        history: false,
        presence: false,
        catchUpOnForeground: false
    )
    options.history = false
    options.presence = false
    options.catchUpOnForeground = false
    requireSendable(options)
    requireEquatable(options)
}

@Test("public model value types exist")
func publicModelValueTypesExist() throws {
    let lockPermissions: (RealtimePermissions) -> Void = { permissions in
        _ = permissions.dboID
        _ = permissions.rowID
    }
    _ = lockPermissions
    requireCodableType(RealtimePermissions.self)
    requireSendableType(RealtimePermissions.self)
    requireEquatableType(RealtimePermissions.self)

    let lockPeer: (RealtimePeer) -> Void = { peer in
        _ = peer.socketId
        _ = peer.extras
        _ = peer.permissions
    }
    _ = lockPeer
    requireCodableType(RealtimePeer.self)
    requireSendableType(RealtimePeer.self)
    requireEquatableType(RealtimePeer.self)

    let lockMessage: (RealtimeMessage) -> Void = { message in
        _ = message.payload
        _ = message.sender
        _ = message.channel
        _ = message.socketId
        _ = message.authenticated
    }
    _ = lockMessage
    requireSendableType(RealtimeMessage.self)
    requireEquatableType(RealtimeMessage.self)

    var closeCode = WebSocketCloseCode(rawValue: 1000)
    _ = closeCode.rawValue
    closeCode = .normalClosure
    closeCode = .abnormalClosure
    closeCode = .internalError
    closeCode = .serviceRestart
    closeCode = .tryAgainLater
    closeCode = .badGateway
    closeCode = .reconnectRequested
    closeCode = .unknown
    _ = closeCode.shouldReconnect
    requireSendable(closeCode)
    requireEquatable(closeCode)
    requireHashable(closeCode)
}

@Test("public JSONValue API exists")
func publicJSONValueAPIExists() throws {
    lockJSONValue(.object(["key": .string("value")]))
    let encoded = try JSONValue(encoding: ["text": "hello"])
    _ = encoded["text"]
    _ = encoded[0]
    let decoded = try encoded.decode(as: [String: String].self)
    #expect(decoded["text"] == "hello")
    requireCodable(encoded)
    requireSendable(encoded)
    requireHashable(encoded)
}

@Test("public enum cases exist")
func publicEnumCasesExist() {
    lockConnectionState(.disconnected)
    lockRealtimeEvent(.connected)
    lockJSONValue(.null)
    lockXanoRealtimeError(.notConnected)
    lockPresenceChange(.join)

    let localized: any LocalizedError = XanoRealtimeError.notConnected
    _ = localized.errorDescription
    requireSendable(ConnectionState.connected)
    requireEquatable(ConnectionState.connected)
    requireSendable(PresenceChange.join)
}

// MARK: - Private Helpers

/// Type-checks that `value` conforms to `Sendable`.
private func requireSendable<Value: Sendable>(_ value: Value) {
    _ = value
}

/// Type-checks that `value` conforms to `Equatable`.
private func requireEquatable<Value: Equatable>(_ value: Value) {
    _ = value == value
}

/// Type-checks that `value` conforms to `Hashable`.
private func requireHashable<Value: Hashable>(_ value: Value) {
    var hasher = Hasher()
    value.hash(into: &hasher)
    _ = hasher.finalize()
}

/// Type-checks that `value` conforms to `Codable`.
private func requireCodable<Value: Codable>(_ value: Value) {
    _ = value
}

/// Type-checks that `Value` conforms to `Sendable`.
private func requireSendableType<Value: Sendable>(_: Value.Type) {}

/// Type-checks that `Value` conforms to `Equatable`.
private func requireEquatableType<Value: Equatable>(_: Value.Type) {}

/// Type-checks that `Value` conforms to `Codable`.
private func requireCodableType<Value: Codable>(_: Value.Type) {}

/// Exhaustive lock of ``ConnectionState`` cases.
private func lockConnectionState(_ state: ConnectionState) {
    switch state {
    case .disconnected:
        break
    case .connecting:
        break
    case .connected:
        break
    case .reconnecting(let attempt):
        _ = attempt
    }
}

/// Exhaustive lock of ``RealtimeEvent`` cases.
private func lockRealtimeEvent(_ event: RealtimeEvent) {
    switch event {
    case .connected:
        break
    case .disconnected:
        break
    case .message(let message):
        _ = message
    case .presenceFull(let peers):
        _ = peers
    case .presenceUpdate(let action, let peer):
        _ = action
        _ = peer
    case .history(let payload):
        _ = payload
    case .error(let error):
        _ = error
    case .unhandled(let action, let payload):
        _ = action
        _ = payload
    }
}

/// Exhaustive lock of ``JSONValue`` cases.
private func lockJSONValue(_ value: JSONValue) {
    switch value {
    case .object(let object):
        _ = object
    case .array(let array):
        _ = array
    case .string(let string):
        _ = string
    case .int(let intValue):
        _ = intValue
    case .double(let doubleValue):
        _ = doubleValue
    case .bool(let boolValue):
        _ = boolValue
    case .null:
        break
    }
}

/// Exhaustive lock of ``XanoRealtimeError`` cases.
private func lockXanoRealtimeError(_ error: XanoRealtimeError) {
    switch error {
    case .invalidConfiguration(let message):
        _ = message
    case .notConnected:
        break
    case .connectionClosed(let code):
        _ = code
    case .decodingFailed(let message):
        _ = message
    case .encodingFailed(let message):
        _ = message
    case .server(let payload):
        _ = payload
    case .pingTimedOut:
        break
    }
}

/// Exhaustive lock of ``PresenceChange`` cases.
private func lockPresenceChange(_ change: PresenceChange) {
    switch change {
    case .join:
        break
    case .leave:
        break
    }
}
