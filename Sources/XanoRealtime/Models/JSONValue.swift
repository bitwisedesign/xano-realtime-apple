import Foundation

/// Typed JSON value used for opaque envelope payloads and peer extras.
///
/// Prefer ``decode(as:)`` when the payload has a known `Decodable` shape.
public enum JSONValue: Sendable, Hashable {
    /// JSON object.
    case object([String: JSONValue])
    /// JSON array.
    case array([JSONValue])
    /// JSON string.
    case string(String)
    /// JSON integer number.
    case int(Int)
    /// JSON floating-point number.
    case double(Double)
    /// JSON boolean.
    case bool(Bool)
    /// JSON null.
    case null

    /// Object value for `key`, or `nil` when this value is not an object or the key is missing.
    public subscript(key: String) -> JSONValue? {
        guard case .object(let object) = self else {
            return nil
        }
        return object[key]
    }

    /// Array element at `index`, or `nil` when this value is not an array or the index is out of range.
    public subscript(index: Int) -> JSONValue? {
        guard case .array(let array) = self, array.indices.contains(index) else {
            return nil
        }
        return array[index]
    }

    /// Encodes an `Encodable` value into a ``JSONValue`` tree.
    ///
    /// - Parameter value: Value to encode as JSON.
    /// - Throws: ``XanoRealtimeError/encodingFailed(_:)`` when encoding fails.
    public init(encoding value: some Encodable) throws {
        let encoder = JSONEncoder()
        let data: Data
        do {
            data = try encoder.encode(value)
        } catch {
            throw XanoRealtimeError.encodingFailed(String(describing: error))
        }
        do {
            self = try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw XanoRealtimeError.encodingFailed(String(describing: error))
        }
    }

    /// Decodes this JSON tree as `type`.
    ///
    /// - Parameter type: Destination `Decodable` type.
    /// - Returns: The decoded value.
    /// - Throws: ``XanoRealtimeError/decodingFailed(_:)`` when decoding fails.
    public func decode<Value: Decodable>(as type: Value.Type) throws -> Value {
        let data: Data
        do {
            data = try JSONEncoder().encode(self)
        } catch {
            throw XanoRealtimeError.decodingFailed(String(describing: error))
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw XanoRealtimeError.decodingFailed(String(describing: error))
        }
    }
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let boolValue = try? container.decode(Bool.self) {
            // Best-effort type probe: JSONDecoder throws on a type mismatch; try the next JSON case.
            self = .bool(boolValue)
        } else if let intValue = try? container.decode(Int.self) {
            // Best-effort type probe: JSONDecoder throws on a type mismatch; try the next JSON case.
            self = .int(intValue)
        } else if let doubleValue = try? container.decode(Double.self) {
            // Best-effort type probe: JSONDecoder throws on a type mismatch; try the next JSON case.
            self = .double(doubleValue)
        } else if let stringValue = try? container.decode(String.self) {
            // Best-effort type probe: JSONDecoder throws on a type mismatch; try the next JSON case.
            self = .string(stringValue)
        } else if let arrayValue = try? container.decode([JSONValue].self) {
            // Best-effort type probe: JSONDecoder throws on a type mismatch; try the next JSON case.
            self = .array(arrayValue)
        } else if let objectValue = try? container.decode([String: JSONValue].self) {
            // Best-effort type probe: JSONDecoder throws on a type mismatch; try the next JSON case.
            self = .object(objectValue)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let object):
            try container.encode(object)
        case .array(let array):
            try container.encode(array)
        case .string(let string):
            try container.encode(string)
        case .int(let intValue):
            try container.encode(intValue)
        case .double(let doubleValue):
            try container.encode(doubleValue)
        case .bool(let boolValue):
            try container.encode(boolValue)
        case .null:
            try container.encodeNil()
        }
    }
}
