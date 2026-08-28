import Foundation
import Testing
@testable import XanoRealtime

@Test("encodes and decodes a nested realtime envelope including dbo_id and extras")
func envelopeRoundTripPreservesWireKeys() throws {
    let peer = samplePeer()
    let envelope = RealtimeEnvelope(
        action: .message,
        client: peer,
        options: RealtimeActionOptions(channel: "lobby", authenticated: true),
        payload: .object(["text": .string("hello"), "count": .int(3)])
    )

    let data = try RealtimeCoder.shared.encode(envelope)
    let decoded = try RealtimeCoder.shared.decode(from: data)

    #expect(decoded == envelope)

    let json = try #require(String(data: data, encoding: .utf8))
    #expect(json.contains("\"dbo_id\":12"))
    #expect(json.contains("\"row_id\":34"))
    #expect(json.contains("\"socketId\""))
}

@Test("encodes a nil payload as JSON null and still decodes an omitted payload key")
func envelopeEncodesNilPayloadAsJSONNull() throws {
    let envelope = RealtimeEnvelope(action: .leave)
    let data = try RealtimeCoder.shared.encode(envelope)
    let json = try #require(String(data: data, encoding: .utf8))
    #expect(json.contains("\"payload\":null"))

    let omitted = Data("{\"action\":\"leave\"}".utf8)
    let decoded = try RealtimeCoder.shared.decode(from: omitted)
    #expect(decoded.payload == nil)
}

@Test("decodes unknown action strings as RealtimeAction.unknown")
func unknownActionDecodesAsUnknown() throws {
    let json = """
    {"action":"future_action","payload":null}
    """
    let data = try #require(json.data(using: .utf8))
    let envelope = try RealtimeCoder.shared.decode(from: data)
    #expect(envelope.action == .unknown("future_action"))
    #expect(envelope.payload == .null)
}

@Test("JSONValue distinguishes integers from floats")
func jsonValueNumberKinds() throws {
    let json = """
    {"int":7,"float":1.5,"flag":true,"empty":null}
    """
    let data = try #require(json.data(using: .utf8))
    let value = try JSONDecoder().decode(JSONValue.self, from: data)
    #expect(value["int"] == .int(7))
    #expect(value["float"] == .double(1.5))
    #expect(value["flag"] == .bool(true))
    #expect(value["empty"] == .null)
}

@Test("join leave message and history builders match the JS SDK envelope")
func coderBuildsOutboundActions() throws {
    let coder = RealtimeCoder.shared
    let join = coder.join(channel: "room", history: true, presence: false)
    #expect(join.action == .join)
    #expect(join.options?.channel == "room")
    let joinPayload = try #require(join.payload)
    let decodedJoin = try joinPayload.decode(as: JoinPayload.self)
    #expect(decodedJoin.history)
    #expect(!decodedJoin.presence)

    let leave = coder.leave(channel: "room")
    #expect(leave.action == .leave)
    #expect(leave.payload == .null)

    let history = coder.history(channel: "room")
    #expect(history.action == .history)
    #expect(history.payload == .null)

    let message = coder.message(
        channel: "room",
        payload: .string("hi"),
        authenticated: true,
        socketId: "peer-9"
    )
    #expect(message.options?.authenticated == true)
    #expect(message.options?.socketId == "peer-9")
}

@Test("rejects an empty JSON object that has no action")
func decodeRejectsMissingAction() {
    let data = Data("{}".utf8)
    #expect(throws: XanoRealtimeError.self) {
        try RealtimeCoder.shared.decode(from: data)
    }
}
