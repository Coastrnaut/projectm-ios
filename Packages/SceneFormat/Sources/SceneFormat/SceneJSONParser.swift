// SceneJSONParser.swift — a bounded JSON reader for untrusted scene bytes (SCN-001-R8; research
// SCN-001-D1, D8; contract C4).
//
// RFC 8259 grammar over UTF-8 bytes. Refuses invalid UTF-8, nesting deeper than the limit (checked
// while reading, so a deep document never recurses past it) and a key that appears twice in one
// object. Numbers keep their written text. Iterative over values within a container level; the
// recursion depth is at most the nesting limit. Plain Swift, no Foundation.

struct SceneJSONParser {
    private let bytes: [UInt8]
    private let maximumDepth: Int
    private var index = 0

    /// Parses exactly one JSON value surrounded by optional white space.
    static func parse(_ bytes: [UInt8], maximumDepth: Int) throws(SceneDecodeError) -> SceneJSON {
        var parser = SceneJSONParser(bytes: bytes, maximumDepth: maximumDepth)
        parser.skipWhitespace()
        let value = try parser.parseValue(depth: 1, path: "$")
        parser.skipWhitespace()
        guard parser.index == bytes.count else { throw parser.failure("unexpected data after the document") }
        return value
    }

    private init(bytes: [UInt8], maximumDepth: Int) {
        self.bytes = bytes
        self.maximumDepth = maximumDepth
    }

    private func failure(_ reason: String) -> SceneDecodeError {
        .notJSON(offset: index, reason: reason)
    }

    private mutating func skipWhitespace() {
        while index < bytes.count {
            switch bytes[index] {
            case 0x20, 0x09, 0x0A, 0x0D: index += 1
            default: return
            }
        }
    }

    private mutating func parseValue(depth: Int, path: String) throws(SceneDecodeError) -> SceneJSON {
        guard index < bytes.count else { throw failure("unexpected end of data") }
        switch bytes[index] {
        case UInt8(ascii: "{"):
            guard depth <= maximumDepth else { throw .nestingTooDeep(limit: maximumDepth) }
            return try parseObject(depth: depth, path: path)
        case UInt8(ascii: "["):
            guard depth <= maximumDepth else { throw .nestingTooDeep(limit: maximumDepth) }
            return try parseArray(depth: depth, path: path)
        case UInt8(ascii: "\""):
            return .string(try parseString())
        case UInt8(ascii: "t"):
            try expectLiteral("true")
            return .bool(true)
        case UInt8(ascii: "f"):
            try expectLiteral("false")
            return .bool(false)
        case UInt8(ascii: "n"):
            try expectLiteral("null")
            return .null
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"):
            return .number(try parseNumber())
        default:
            throw failure("unexpected character")
        }
    }

    private mutating func expectLiteral(_ literal: StaticString) throws(SceneDecodeError) {
        let count = literal.utf8CodeUnitCount
        guard index + count <= bytes.count else { throw failure("unexpected end of data") }
        let start = literal.utf8Start
        for i in 0..<count where bytes[index + i] != start[i] {
            throw failure("unexpected character")
        }
        index += count
    }

    private mutating func parseObject(depth: Int, path: String) throws(SceneDecodeError) -> SceneJSON {
        index += 1 // {
        var result: [String: SceneJSON] = [:]
        skipWhitespace()
        if index < bytes.count, bytes[index] == UInt8(ascii: "}") {
            index += 1
            return .object(result)
        }
        while true {
            skipWhitespace()
            guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else { throw failure("expected a key") }
            let key = try parseString()
            guard result[key] == nil else { throw .duplicateKey(path: path, key: key) }
            skipWhitespace()
            guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { throw failure("expected \":\"") }
            index += 1
            skipWhitespace()
            result[key] = try parseValue(depth: depth + 1, path: ScenePath.key(path, key))
            skipWhitespace()
            guard index < bytes.count else { throw failure("unexpected end of data") }
            if bytes[index] == UInt8(ascii: ",") {
                index += 1
                continue
            }
            guard bytes[index] == UInt8(ascii: "}") else { throw failure("expected \",\" or \"}\"") }
            index += 1
            return .object(result)
        }
    }

    private mutating func parseArray(depth: Int, path: String) throws(SceneDecodeError) -> SceneJSON {
        index += 1 // [
        var result: [SceneJSON] = []
        skipWhitespace()
        if index < bytes.count, bytes[index] == UInt8(ascii: "]") {
            index += 1
            return .array(result)
        }
        while true {
            skipWhitespace()
            result.append(try parseValue(depth: depth + 1, path: ScenePath.index(path, result.count)))
            skipWhitespace()
            guard index < bytes.count else { throw failure("unexpected end of data") }
            if bytes[index] == UInt8(ascii: ",") {
                index += 1
                continue
            }
            guard bytes[index] == UInt8(ascii: "]") else { throw failure("expected \",\" or \"]\"") }
            index += 1
            return .array(result)
        }
    }

    private mutating func parseNumber() throws(SceneDecodeError) -> SceneNumber {
        let start = index
        func isDigit(_ b: UInt8) -> Bool { b >= 0x30 && b <= 0x39 }
        if bytes[index] == UInt8(ascii: "-") { index += 1 }
        guard index < bytes.count, isDigit(bytes[index]) else { throw failure("invalid number") }
        if bytes[index] == UInt8(ascii: "0") {
            index += 1
        } else {
            while index < bytes.count, isDigit(bytes[index]) { index += 1 }
        }
        if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
            index += 1
            guard index < bytes.count, isDigit(bytes[index]) else { throw failure("invalid number") }
            while index < bytes.count, isDigit(bytes[index]) { index += 1 }
        }
        if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
            index += 1
            if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") { index += 1 }
            guard index < bytes.count, isDigit(bytes[index]) else { throw failure("invalid number") }
            while index < bytes.count, isDigit(bytes[index]) { index += 1 }
        }
        // ASCII only, so this conversion is exact.
        return SceneNumber(validatedText: String(decoding: bytes[start..<index], as: UTF8.self))
    }

    private mutating func parseString() throws(SceneDecodeError) -> String {
        index += 1 // opening quote
        var scalars = String.UnicodeScalarView()
        while true {
            guard index < bytes.count else { throw failure("unterminated string") }
            let b = bytes[index]
            switch b {
            case UInt8(ascii: "\""):
                index += 1
                return String(scalars)
            case UInt8(ascii: "\\"):
                index += 1
                guard index < bytes.count else { throw failure("unterminated string") }
                let e = bytes[index]
                index += 1
                switch e {
                case UInt8(ascii: "\""): scalars.append("\"")
                case UInt8(ascii: "\\"): scalars.append("\\")
                case UInt8(ascii: "/"): scalars.append("/")
                case UInt8(ascii: "b"): scalars.append("\u{08}")
                case UInt8(ascii: "f"): scalars.append("\u{0C}")
                case UInt8(ascii: "n"): scalars.append("\n")
                case UInt8(ascii: "r"): scalars.append("\r")
                case UInt8(ascii: "t"): scalars.append("\t")
                case UInt8(ascii: "u"):
                    let unit = try parseHex4()
                    if unit >= 0xD800 && unit <= 0xDBFF {
                        guard index + 1 < bytes.count, bytes[index] == UInt8(ascii: "\\"), bytes[index + 1] == UInt8(ascii: "u") else {
                            throw failure("unpaired surrogate escape")
                        }
                        index += 2
                        let low = try parseHex4()
                        guard low >= 0xDC00 && low <= 0xDFFF else { throw failure("unpaired surrogate escape") }
                        let value = 0x10000 + ((unit - 0xD800) << 10) + (low - 0xDC00)
                        guard let scalar = Unicode.Scalar(value) else { throw failure("invalid escape") }
                        scalars.append(scalar)
                    } else {
                        guard let scalar = Unicode.Scalar(unit) else { throw failure("unpaired surrogate escape") }
                        scalars.append(scalar)
                    }
                default:
                    throw failure("invalid escape")
                }
            case 0x00..<0x20:
                throw failure("control character in a string")
            case 0x00..<0x80:
                scalars.append(Unicode.Scalar(b))
                index += 1
            default:
                scalars.append(try decodeUTF8Scalar())
            }
        }
    }

    private mutating func parseHex4() throws(SceneDecodeError) -> UInt32 {
        guard index + 4 <= bytes.count else { throw failure("invalid escape") }
        var value: UInt32 = 0
        for _ in 0..<4 {
            let b = bytes[index]
            let digit: UInt32
            switch b {
            case 0x30...0x39: digit = UInt32(b - 0x30)
            case 0x41...0x46: digit = UInt32(b - 0x41 + 10)
            case 0x61...0x66: digit = UInt32(b - 0x61 + 10)
            default: throw failure("invalid escape")
            }
            value = value << 4 | digit
            index += 1
        }
        return value
    }

    /// One multi-byte UTF-8 scalar; overlong forms, surrogates and values above U+10FFFF are refused.
    private mutating func decodeUTF8Scalar() throws(SceneDecodeError) -> Unicode.Scalar {
        let lead = bytes[index]
        let count: Int
        var value: UInt32
        let minimum: UInt32
        switch lead {
        case 0xC2...0xDF: count = 2; value = UInt32(lead & 0x1F); minimum = 0x80
        case 0xE0...0xEF: count = 3; value = UInt32(lead & 0x0F); minimum = 0x800
        case 0xF0...0xF4: count = 4; value = UInt32(lead & 0x07); minimum = 0x10000
        default: throw failure("invalid UTF-8")
        }
        guard index + count <= bytes.count else { throw failure("invalid UTF-8") }
        for i in 1..<count {
            let c = bytes[index + i]
            guard c & 0xC0 == 0x80 else { throw failure("invalid UTF-8") }
            value = value << 6 | UInt32(c & 0x3F)
        }
        guard value >= minimum, let scalar = Unicode.Scalar(value) else { throw failure("invalid UTF-8") }
        index += count
        return scalar
    }
}

/// Readable locations: `$`, `$.layers[2].composite`, `$.parameters["visual.circularSpectrum.gap"]`.
enum ScenePath {
    static func key(_ base: String, _ key: String) -> String {
        if isPlain(key) { return base + "." + key }
        var escaped = ""
        for c in key.unicodeScalars {
            switch c {
            case "\"": escaped += "\\\""
            case "\\": escaped += "\\\\"
            default: escaped.unicodeScalars.append(c)
            }
        }
        return base + "[\"" + escaped + "\"]"
    }

    static func index(_ base: String, _ i: Int) -> String { base + "[\(i)]" }

    private static func isPlain(_ key: String) -> Bool {
        guard let first = key.utf8.first, (first >= 0x61 && first <= 0x7A) || (first >= 0x41 && first <= 0x5A) else { return false }
        return key.utf8.allSatisfy { (b: UInt8) -> Bool in
            (b >= 0x61 && b <= 0x7A) || (b >= 0x41 && b <= 0x5A) || (b >= 0x30 && b <= 0x39)
        }
    }
}
