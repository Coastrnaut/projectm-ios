// SceneJSONWriter.swift — the canonical writer (SCN-001-R7; research SCN-001-D1; contract C2).
//
// No white space; object keys sorted by their UTF-8 bytes; strings escape only the quote, the
// backslash and U+0000…U+001F; numbers as their text. One byte sequence per value on every host.

enum SceneJSONWriter {
    static func write(_ value: SceneJSON) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(1_024)
        write(value, into: &out)
        return out
    }

    static func write(_ value: SceneJSON, into out: inout [UInt8]) {
        switch value {
        case .null: out.append(contentsOf: "null".utf8)
        case let .bool(b): out.append(contentsOf: (b ? "true" : "false").utf8)
        case let .number(n): out.append(contentsOf: n.text.utf8)
        case let .string(s): writeString(s, into: &out)
        case let .array(items):
            out.append(UInt8(ascii: "["))
            for (i, item) in items.enumerated() {
                if i > 0 { out.append(UInt8(ascii: ",")) }
                write(item, into: &out)
            }
            out.append(UInt8(ascii: "]"))
        case let .object(members):
            out.append(UInt8(ascii: "{"))
            let keys = members.keys.sorted(by: utf8Precedes)
            for (i, key) in keys.enumerated() {
                if i > 0 { out.append(UInt8(ascii: ",")) }
                writeString(key, into: &out)
                out.append(UInt8(ascii: ":"))
                // The key comes from the dictionary, so the value exists.
                if let member = members[key] { write(member, into: &out) }
            }
            out.append(UInt8(ascii: "}"))
        }
    }

    /// Byte order of the UTF-8 encodings (the canonical key order).
    static func utf8Precedes(_ a: String, _ b: String) -> Bool {
        a.utf8.lexicographicallyPrecedes(b.utf8)
    }

    private static let hex: [UInt8] = Array("0123456789abcdef".utf8)

    static func writeString(_ s: String, into out: inout [UInt8]) {
        out.append(UInt8(ascii: "\""))
        for b in s.utf8 {
            switch b {
            case UInt8(ascii: "\""): out.append(contentsOf: [UInt8(ascii: "\\"), UInt8(ascii: "\"")])
            case UInt8(ascii: "\\"): out.append(contentsOf: [UInt8(ascii: "\\"), UInt8(ascii: "\\")])
            case 0x08: out.append(contentsOf: [UInt8(ascii: "\\"), UInt8(ascii: "b")])
            case 0x0C: out.append(contentsOf: [UInt8(ascii: "\\"), UInt8(ascii: "f")])
            case 0x0A: out.append(contentsOf: [UInt8(ascii: "\\"), UInt8(ascii: "n")])
            case 0x0D: out.append(contentsOf: [UInt8(ascii: "\\"), UInt8(ascii: "r")])
            case 0x09: out.append(contentsOf: [UInt8(ascii: "\\"), UInt8(ascii: "t")])
            case 0x00..<0x20:
                out.append(contentsOf: [UInt8(ascii: "\\"), UInt8(ascii: "u"), UInt8(ascii: "0"), UInt8(ascii: "0"),
                                        hex[Int(b >> 4)], hex[Int(b & 0x0F)]])
            default: out.append(b)
            }
        }
        out.append(UInt8(ascii: "\""))
    }
}
