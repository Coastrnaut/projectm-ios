// ShaderMetadataDocument.swift — the strict JSON reader of shader parameter metadata (SHD-003-R1, R2;
// research SHD-003-D1; data-model.md).
//
// The text is decoded by `JSONDecoder` into `ShaderMetadataJSON` (a plain JSON value: booleans and numbers
// stay apart on Darwin and Linux), then read by hand through `ShaderMetadataObject`, which refuses unknown
// keys, missing keys and values of the wrong type with the value's path. Nothing in a document is ever
// evaluated, compiled, loaded or used as a path (SHD-003-R9): it is data. Foundation only; builds on Linux.
import Foundation

/// A JSON value.
public enum ShaderMetadataJSON: Sendable, Hashable, Decodable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([ShaderMetadataJSON])
    case object([String: ShaderMetadataJSON])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([ShaderMetadataJSON].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: ShaderMetadataJSON].self))
        }
    }

    /// The type name used in `wrongType` messages.
    var typeName: String {
        switch self {
        case .null: "null"
        case .bool: "a boolean"
        case .number: "a number"
        case .string: "text"
        case .array: "an array"
        case .object: "an object"
        }
    }

    /// Decodes `text`; throws `malformedJSON` naming `document`.
    static func parse(_ text: String, document: String) throws(ShaderMetadataError) -> ShaderMetadataJSON {
        let data: Data = Data(text.utf8)
        do {
            return try JSONDecoder().decode(ShaderMetadataJSON.self, from: data)
        } catch {
            throw .malformedJSON(document: document)
        }
    }
}

/// One JSON object read key by key; every read names the object's path in its errors.
struct ShaderMetadataObject {
    let document: String
    let path: String
    let fields: [String: ShaderMetadataJSON]

    init(_ value: ShaderMetadataJSON, document: String, path: String) throws(ShaderMetadataError) {
        guard case let .object(fields) = value else { throw .notAnObject(document: document, path: path) }
        self.document = document
        self.path = path
        self.fields = fields
    }

    /// Refuses any key outside `known` (sorted, so the first reported key is stable).
    func requireOnly(_ known: Set<String>) throws(ShaderMetadataError) {
        for key in fields.keys.sorted() where !known.contains(key) {
            throw .unknownKey(document: document, path: path, key: key)
        }
    }

    /// Refuses a present key that does not apply to `kind`.
    func refuse(_ keys: [String], kind: String) throws(ShaderMetadataError) {
        for key in keys where fields[key] != nil {
            throw .keyNotAllowed(document: document, path: path, key: key, kind: kind)
        }
    }

    func has(_ key: String) -> Bool { fields[key] != nil }

    func value(_ key: String) throws(ShaderMetadataError) -> ShaderMetadataJSON {
        guard let value = fields[key] else { throw .missingKey(document: document, path: path, key: key) }
        return value
    }

    func string(_ key: String) throws(ShaderMetadataError) -> String {
        guard case let .string(text) = try value(key) else {
            throw .wrongType(document: document, path: path, key: key, expected: "text")
        }
        return text
    }

    func number(_ key: String) throws(ShaderMetadataError) -> Double {
        guard case let .number(number) = try value(key) else {
            throw .wrongType(document: document, path: path, key: key, expected: "a number")
        }
        guard number.isFinite else { throw .nonFinite(document: document, path: path, key: key) }
        return number
    }

    /// A number that must be whole (within ±1,000,000,000).
    func whole(_ key: String) throws(ShaderMetadataError) -> Int {
        let number: Double = try self.number(key)
        guard number.rounded() == number, abs(number) <= 1_000_000_000 else {
            throw .notWhole(document: document, path: path, key: key)
        }
        return Int(number)
    }

    func bool(_ key: String) throws(ShaderMetadataError) -> Bool {
        guard case let .bool(flag) = try value(key) else {
            throw .wrongType(document: document, path: path, key: key, expected: "a boolean")
        }
        return flag
    }

    func array(_ key: String) throws(ShaderMetadataError) -> [ShaderMetadataJSON] {
        guard case let .array(items) = try value(key) else {
            throw .wrongType(document: document, path: path, key: key, expected: "an array")
        }
        return items
    }
}
