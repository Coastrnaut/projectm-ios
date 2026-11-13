// BoundedJSON.swift — a bounded, structural JSON validator for untrusted bytes (FILE-007-R1 to R4;
// specs/068-file-007-document-schema-validator, contract C1; research FILE-007-D2, D3).
//
// It answers one question before any decoder sees the bytes: is this one RFC 8259 JSON value in
// strictly valid UTF-8, within the declared limits (total bytes, nesting depth, string and number
// lengths, elements per container), with no key twice in one object? It builds no values: one
// forward pass with an explicit container stack (no recursion), each byte read at most once, and the
// first refusal wins with a typed reason and the byte offset where reading stopped. Total size is
// checked before the first byte. Plain Swift; `Data` only at the API edge. Builds and runs on Linux.
import Foundation

/// What a document may contain. Every limit is inclusive.
public struct JSONLimits: Sendable, Equatable {
    /// Total bytes; checked before any byte is read.
    public var maxBytes: Int
    /// Open arrays and objects at once; the top-level container counts as 1.
    public var maxDepth: Int
    /// Raw bytes between the quotes of one string, escapes counted as written.
    public var maxStringBytes: Int
    /// Characters of one number.
    public var maxNumberBytes: Int
    /// Elements of one array, or members of one object.
    public var maxElements: Int
    /// The same key (after escapes are decoded) twice in one object is refused.
    public var rejectsDuplicateKeys: Bool
    /// The top-level value must be an object.
    public var requiresObjectRoot: Bool

    public init(maxBytes: Int, maxDepth: Int, maxStringBytes: Int, maxNumberBytes: Int, maxElements: Int,
                rejectsDuplicateKeys: Bool = true, requiresObjectRoot: Bool = true) {
        self.maxBytes = maxBytes
        self.maxDepth = maxDepth
        self.maxStringBytes = maxStringBytes
        self.maxNumberBytes = maxNumberBytes
        self.maxElements = maxElements
        self.rejectsDuplicateKeys = rejectsDuplicateKeys
        self.requiresObjectRoot = requiresObjectRoot
    }
}

/// Why bytes were refused. `offset` is the byte index (from the start of the input) where reading stopped.
public enum JSONShapeError: Error, Equatable, Sendable {
    case tooLarge(bytes: Int, limit: Int)
    case empty
    case byteOrderMark
    case invalidUTF8(offset: Int)
    case nestingTooDeep(offset: Int, limit: Int)
    case stringTooLong(offset: Int, limit: Int)
    case numberTooLong(offset: Int, limit: Int)
    case tooManyElements(offset: Int, limit: Int)
    case duplicateKey(offset: Int)
    case invalidNumber(offset: Int)
    case invalidEscape(offset: Int)
    case controlCharacter(offset: Int)
    case unterminatedString(offset: Int)
    case unexpectedCharacter(offset: Int)
    case unexpectedEnd(offset: Int)
    case trailingData(offset: Int)
    case notAnObject(offset: Int)

    public enum Family: Sendable, Equatable {
        /// Not JSON, or not valid UTF-8.
        case grammar
        /// Valid so far, but over a declared limit.
        case limit
        case duplicateKey
    }

    public var offset: Int {
        switch self {
        case .tooLarge, .empty, .byteOrderMark: return 0
        case .invalidUTF8(let o), .duplicateKey(let o), .invalidNumber(let o), .invalidEscape(let o),
             .controlCharacter(let o), .unterminatedString(let o), .unexpectedCharacter(let o),
             .unexpectedEnd(let o), .trailingData(let o), .notAnObject(let o):
            return o
        case .nestingTooDeep(let o, _), .stringTooLong(let o, _), .numberTooLong(let o, _), .tooManyElements(let o, _):
            return o
        }
    }

    public var family: Family {
        switch self {
        case .tooLarge, .nestingTooDeep, .stringTooLong, .numberTooLong, .tooManyElements: return .limit
        case .duplicateKey: return .duplicateKey
        default: return .grammar
        }
    }
}

/// A successful check.
public struct JSONShapeSummary: Sendable, Equatable {
    /// Bytes read (the whole input on success).
    public let bytesExamined: Int
    /// Deepest nesting reached.
    public let deepest: Int
    /// Values seen, containers and scalars together.
    public let values: Int
}

/// A check with its work counter, for tests that bound the work done on refusal.
public struct JSONShapeOutcome: Sendable, Equatable {
    public let result: Result<JSONShapeSummary, JSONShapeError>
    /// One more than the highest byte index read; never more than a refusal's offset + 1.
    public let bytesExamined: Int
}

public enum BoundedJSON {
    /// Validates `data` against `limits`, or throws the first reason to refuse it.
    @discardableResult
    public static func validate(_ data: Data, limits: JSONLimits) throws(JSONShapeError) -> JSONShapeSummary {
        try check(data, limits: limits).result.get()
    }

    public static func check(_ data: Data, limits: JSONLimits) -> JSONShapeOutcome {
        if data.count > limits.maxBytes {
            return JSONShapeOutcome(result: .failure(.tooLarge(bytes: data.count, limit: limits.maxBytes)), bytesExamined: 0)
        }
        return data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> JSONShapeOutcome in
            var scanner = Scanner(bytes: raw, limits: limits)
            let result = scanner.run()
            return JSONShapeOutcome(result: result, bytesExamined: scanner.examined)
        }
    }

    public static func check(_ bytes: [UInt8], limits: JSONLimits) -> JSONShapeOutcome {
        if bytes.count > limits.maxBytes {
            return JSONShapeOutcome(result: .failure(.tooLarge(bytes: bytes.count, limit: limits.maxBytes)), bytesExamined: 0)
        }
        return bytes.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> JSONShapeOutcome in
            var scanner = Scanner(bytes: raw, limits: limits)
            let result = scanner.run()
            return JSONShapeOutcome(result: result, bytesExamined: scanner.examined)
        }
    }
}

// MARK: - Scanner

private struct Frame {
    var isObject: Bool
    var count: Int
    var keys: Set<[UInt8]>
}

private enum ScanState {
    case value
    case afterValue
    case key
}

private struct Scanner {
    let bytes: UnsafeRawBufferPointer
    let limits: JSONLimits
    var index = 0
    var examined = 0
    var stack: [Frame] = []
    var deepest = 0
    var values = 0
    var keyBuffer: [UInt8] = []

    init(bytes: UnsafeRawBufferPointer, limits: JSONLimits) {
        self.bytes = bytes
        self.limits = limits
    }

    var count: Int { bytes.count }

    /// The byte at `i`, recorded as examined.
    mutating func byte(_ i: Int) -> UInt8 {
        if i >= examined { examined = i + 1 }
        return bytes[i]
    }

    static func isWhitespace(_ b: UInt8) -> Bool { b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D }

    mutating func skipWhitespace() {
        while index < count, Self.isWhitespace(byte(index)) { index += 1 }
    }

    mutating func run() -> Result<JSONShapeSummary, JSONShapeError> {
        do throws(JSONShapeError) {
            try scan()
            return .success(JSONShapeSummary(bytesExamined: examined, deepest: deepest, values: values))
        } catch {
            return .failure(error)
        }
    }

    mutating func scan() throws(JSONShapeError) {
        if count == 0 { throw .empty }
        if count >= 3, byte(0) == 0xEF, byte(1) == 0xBB, byte(2) == 0xBF { throw .byteOrderMark }
        skipWhitespace()
        guard index < count else { throw .unexpectedEnd(offset: index) }
        if limits.requiresObjectRoot, byte(index) != UInt8(ascii: "{") { throw .notAnObject(offset: index) }

        var state = ScanState.value
        while true {
            switch state {
            case .value:
                skipWhitespace()
                guard index < count else { throw .unexpectedEnd(offset: index) }
                state = try scanValue()
            case .key:
                skipWhitespace()
                guard index < count else { throw .unexpectedEnd(offset: index) }
                guard byte(index) == UInt8(ascii: "\"") else { throw .unexpectedCharacter(offset: index) }
                try scanString(collectKey: limits.rejectsDuplicateKeys)
                if limits.rejectsDuplicateKeys {
                    // The offset is the duplicate key's closing quote, the last byte read.
                    guard stack[stack.count - 1].keys.insert(keyBuffer).inserted else { throw .duplicateKey(offset: index - 1) }
                }
                skipWhitespace()
                guard index < count else { throw .unexpectedEnd(offset: index) }
                guard byte(index) == UInt8(ascii: ":") else { throw .unexpectedCharacter(offset: index) }
                index += 1
                state = .value
            case .afterValue:
                skipWhitespace()
                guard !stack.isEmpty else {
                    guard index == count else { throw .trailingData(offset: index) }
                    return
                }
                guard index < count else { throw .unexpectedEnd(offset: index) }
                let b = byte(index)
                let top = stack.count - 1
                if b == UInt8(ascii: ",") {
                    index += 1
                    skipWhitespace()
                    try countElement(at: index)
                    state = stack[top].isObject ? .key : .value
                } else if b == (stack[top].isObject ? UInt8(ascii: "}") : UInt8(ascii: "]")) {
                    index += 1
                    stack.removeLast()
                    state = .afterValue
                } else {
                    throw .unexpectedCharacter(offset: index)
                }
            }
        }
    }

    /// Counts one more element or member in the innermost container.
    mutating func countElement(at offset: Int) throws(JSONShapeError) {
        let top = stack.count - 1
        stack[top].count += 1
        if stack[top].count > limits.maxElements { throw .tooManyElements(offset: offset, limit: limits.maxElements) }
    }

    /// Scans the value at `index` (not white space, not the end). Returns the next state.
    mutating func scanValue() throws(JSONShapeError) -> ScanState {
        values += 1
        let b = byte(index)
        switch b {
        case UInt8(ascii: "{"), UInt8(ascii: "["):
            let isObject = b == UInt8(ascii: "{")
            if stack.count + 1 > limits.maxDepth { throw .nestingTooDeep(offset: index, limit: limits.maxDepth) }
            stack.append(Frame(isObject: isObject, count: 0, keys: []))
            deepest = max(deepest, stack.count)
            index += 1
            skipWhitespace()
            guard index < count else { throw .unexpectedEnd(offset: index) }
            if byte(index) == (isObject ? UInt8(ascii: "}") : UInt8(ascii: "]")) {
                index += 1
                stack.removeLast()
                return .afterValue
            }
            try countElement(at: index)
            return isObject ? .key : .value
        case UInt8(ascii: "\""):
            try scanString(collectKey: false)
            return .afterValue
        case UInt8(ascii: "t"):
            try scanLiteral([0x74, 0x72, 0x75, 0x65])
            return .afterValue
        case UInt8(ascii: "f"):
            try scanLiteral([0x66, 0x61, 0x6C, 0x73, 0x65])
            return .afterValue
        case UInt8(ascii: "n"):
            try scanLiteral([0x6E, 0x75, 0x6C, 0x6C])
            return .afterValue
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"):
            try scanNumber()
            return .afterValue
        default:
            throw .unexpectedCharacter(offset: index)
        }
    }

    mutating func scanLiteral(_ literal: [UInt8]) throws(JSONShapeError) {
        for expected in literal {
            guard index < count else { throw .unexpectedEnd(offset: index) }
            guard byte(index) == expected else { throw .unexpectedCharacter(offset: index) }
            index += 1
        }
    }

    static func isNumberByte(_ b: UInt8) -> Bool {
        (b >= 0x30 && b <= 0x39) || b == 0x2D || b == 0x2B || b == 0x2E || b == 0x65 || b == 0x45
    }

    static func isDigit(_ b: UInt8) -> Bool { b >= 0x30 && b <= 0x39 }

    /// The byte at `index` of a number that started at `start`, or nil at the end; a number byte past
    /// the length limit is refused.
    mutating func peekNumber(_ start: Int) throws(JSONShapeError) -> UInt8? {
        guard index < count else { return nil }
        let b = byte(index)
        if Self.isNumberByte(b), index - start >= limits.maxNumberBytes {
            throw .numberTooLong(offset: index, limit: limits.maxNumberBytes)
        }
        return b
    }

    mutating func skipDigits(_ start: Int) throws(JSONShapeError) {
        while let b = try peekNumber(start), Self.isDigit(b) { index += 1 }
    }

    /// `-? (0 | [1-9][0-9]*) (. [0-9]+)? ([eE] [+-]? [0-9]+)?`, at most `maxNumberBytes` long, in one pass.
    mutating func scanNumber() throws(JSONShapeError) {
        let start = index
        var b = try peekNumber(start)
        if b == 0x2D {
            index += 1
            b = try peekNumber(start)
        }
        guard let first = b, Self.isDigit(first) else { throw .invalidNumber(offset: index) }
        index += 1
        if first != 0x30 { try skipDigits(start) }
        b = try peekNumber(start)
        if b == 0x2E {
            index += 1
            guard let d = try peekNumber(start), Self.isDigit(d) else { throw .invalidNumber(offset: index) }
            try skipDigits(start)
            b = try peekNumber(start)
        }
        if b == 0x65 || b == 0x45 {
            index += 1
            b = try peekNumber(start)
            if b == 0x2B || b == 0x2D { index += 1 }
            guard let d = try peekNumber(start), Self.isDigit(d) else { throw .invalidNumber(offset: index) }
            try skipDigits(start)
        }
        // "01", "1.2.3", "1-": a number byte that cannot continue the number.
        if let next = try peekNumber(start), Self.isNumberByte(next) { throw .invalidNumber(offset: index) }
    }

    static func hexValue(_ b: UInt8) -> UInt32? {
        switch b {
        case 0x30...0x39: return UInt32(b - 0x30)
        case 0x41...0x46: return UInt32(b - 0x41 + 10)
        case 0x61...0x66: return UInt32(b - 0x61 + 10)
        default: return nil
        }
    }

    /// Four hex digits at `index`.
    mutating func hex4() throws(JSONShapeError) -> UInt32 {
        var value: UInt32 = 0
        for _ in 0..<4 {
            guard index < count else { throw .unterminatedString(offset: count) }
            guard let digit = Self.hexValue(byte(index)) else { throw .invalidEscape(offset: index) }
            value = value * 16 + digit
            index += 1
        }
        return value
    }

    mutating func appendScalar(_ scalar: UInt32) {
        if scalar < 0x80 {
            keyBuffer.append(UInt8(scalar))
        } else if scalar < 0x800 {
            keyBuffer.append(UInt8(0xC0 | (scalar >> 6)))
            keyBuffer.append(UInt8(0x80 | (scalar & 0x3F)))
        } else if scalar < 0x10000 {
            keyBuffer.append(UInt8(0xE0 | (scalar >> 12)))
            keyBuffer.append(UInt8(0x80 | ((scalar >> 6) & 0x3F)))
            keyBuffer.append(UInt8(0x80 | (scalar & 0x3F)))
        } else {
            keyBuffer.append(UInt8(0xF0 | (scalar >> 18)))
            keyBuffer.append(UInt8(0x80 | ((scalar >> 12) & 0x3F)))
            keyBuffer.append(UInt8(0x80 | ((scalar >> 6) & 0x3F)))
            keyBuffer.append(UInt8(0x80 | (scalar & 0x3F)))
        }
    }

    /// The string whose opening quote is at `index`. With `collectKey`, its decoded bytes are left in `keyBuffer`.
    mutating func scanString(collectKey: Bool) throws(JSONShapeError) {
        index += 1
        let contentStart = index
        if collectKey { keyBuffer.removeAll(keepingCapacity: true) }
        while true {
            guard index < count else { throw .unterminatedString(offset: count) }
            let b = byte(index)
            if b == UInt8(ascii: "\"") {
                index += 1
                return
            }
            if index - contentStart >= limits.maxStringBytes {
                throw .stringTooLong(offset: index, limit: limits.maxStringBytes)
            }
            if b == UInt8(ascii: "\\") {
                index += 1
                guard index < count else { throw .unterminatedString(offset: count) }
                let e = byte(index)
                index += 1
                var decoded: UInt32
                switch e {
                case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"): decoded = UInt32(e)
                case UInt8(ascii: "b"): decoded = 0x08
                case UInt8(ascii: "f"): decoded = 0x0C
                case UInt8(ascii: "n"): decoded = 0x0A
                case UInt8(ascii: "r"): decoded = 0x0D
                case UInt8(ascii: "t"): decoded = 0x09
                case UInt8(ascii: "u"):
                    decoded = try hex4()
                    // A lone or misplaced surrogate is refused at the last byte read.
                    if decoded >= 0xDC00 && decoded <= 0xDFFF { throw .invalidEscape(offset: index - 1) }
                    if decoded >= 0xD800 && decoded <= 0xDBFF {
                        guard index < count else { throw .unterminatedString(offset: count) }
                        guard byte(index) == UInt8(ascii: "\\") else { throw .invalidEscape(offset: index) }
                        guard index + 1 < count else { throw .unterminatedString(offset: count) }
                        guard byte(index + 1) == UInt8(ascii: "u") else { throw .invalidEscape(offset: index + 1) }
                        index += 2
                        let low = try hex4()
                        guard low >= 0xDC00 && low <= 0xDFFF else { throw .invalidEscape(offset: index - 1) }
                        decoded = 0x10000 + ((decoded - 0xD800) << 10) + (low - 0xDC00)
                    }
                default:
                    throw .invalidEscape(offset: index - 1)
                }
                if collectKey { appendScalar(decoded) }
                continue
            }
            if b < 0x20 { throw .controlCharacter(offset: index) }
            if b < 0x80 {
                if collectKey { keyBuffer.append(b) }
                index += 1
                continue
            }
            let length = try utf8SequenceLength()
            if collectKey {
                for k in 0..<length { keyBuffer.append(bytes[index + k]) }
            }
            index += length
        }
    }

    /// Validates the multi-byte UTF-8 sequence at `index` (RFC 3629) and returns its length.
    mutating func utf8SequenceLength() throws(JSONShapeError) -> Int {
        let lead = byte(index)
        let length: Int
        var low: UInt8 = 0x80
        var high: UInt8 = 0xBF
        switch lead {
        case 0xC2...0xDF: length = 2
        case 0xE0: length = 3; low = 0xA0
        case 0xE1...0xEC, 0xEE...0xEF: length = 3
        case 0xED: length = 3; high = 0x9F
        case 0xF0: length = 4; low = 0x90
        case 0xF1...0xF3: length = 4
        case 0xF4: length = 4; high = 0x8F
        default: throw .invalidUTF8(offset: index)
        }
        for k in 1..<length {
            let at = index + k
            guard at < count else { throw .unterminatedString(offset: count) }
            let c = byte(at)
            let lo: UInt8 = k == 1 ? low : 0x80
            let hi: UInt8 = k == 1 ? high : 0xBF
            guard c >= lo && c <= hi else { throw .invalidUTF8(offset: at) }
        }
        return length
    }
}
