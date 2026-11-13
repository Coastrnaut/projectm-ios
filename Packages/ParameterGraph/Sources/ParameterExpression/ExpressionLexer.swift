// ExpressionLexer.swift — source bytes to tokens (SHD-009-R1, R5, R6; contract E1).
//
// Byte-oriented and ASCII-only: positions count bytes, so a byte is a character. The length limit
// is checked before anything else; the token limit at the first token over it.

enum TokenKind: Equatable {
    case number(Double)
    case name(String)
    case letKeyword
    /// One of `( ) , ; = + - * /`.
    case punctuation(UInt8)
    case end
}

struct Token {
    let kind: TokenKind
    /// The token as written (empty for the end).
    let text: String
    let position: SourcePosition

    /// How messages show the token: quoted text, or "end of input".
    var quoted: String {
        if case .end = kind { return "end of input" }
        return "'\(text)'"
    }
}

enum ExpressionLexer {
    private static let punctuation: [UInt8] = Array("(),;=+-*/".utf8)

    static func tokens(of source: String, limits: ExpressionLimits) throws(ExpressionError) -> [Token] {
        let bytes = Array(source.utf8)
        if bytes.count > limits.maximumSourceBytes {
            throw ExpressionError(.sourceTooLong(bytes: bytes.count, limit: limits.maximumSourceBytes),
                                  at: position(ofOffset: limits.maximumSourceBytes, in: bytes))
        }
        var tokens: [Token] = []
        var i = 0
        var line = 1
        var lineStart = 0

        func append(_ kind: TokenKind, from start: Int, to end: Int) throws(ExpressionError) {
            let position = SourcePosition(line: line, column: start - lineStart + 1)
            if tokens.count >= limits.maximumTokens {
                throw ExpressionError(.tooManyTokens(limit: limits.maximumTokens), at: position)
            }
            tokens.append(Token(kind: kind, text: text(bytes, start, end), position: position))
        }

        while i < bytes.count {
            let b = bytes[i]
            let here = SourcePosition(line: line, column: i - lineStart + 1)
            switch b {
            case 0x0A:
                i += 1
                line += 1
                lineStart = i
            case 0x20, 0x09, 0x0D:
                i += 1
            case _ where isDigit(b):
                let start = i
                guard let end = numberEnd(bytes, from: start) else {
                    throw ExpressionError(.malformedNumber(text(bytes, start, malformedEnd(bytes, from: start))), at: here)
                }
                let literal = text(bytes, start, end)
                guard let value = Double(literal), value.isFinite else {
                    throw ExpressionError(.numberOutOfRange(literal), at: here)
                }
                try append(.number(value), from: start, to: end)
                i = end
            case _ where isNameStart(b):
                let start = i
                i += 1
                while i < bytes.count, isNameCharacter(bytes[i]) { i += 1 }
                while i + 1 < bytes.count, bytes[i] == UInt8(ascii: "."), isNameCharacter(bytes[i + 1]) {
                    i += 1
                    while i < bytes.count, isNameCharacter(bytes[i]) { i += 1 }
                }
                let name = text(bytes, start, i)
                try append(name == "let" ? .letKeyword : .name(name), from: start, to: i)
            case _ where punctuation.contains(b):
                try append(.punctuation(b), from: i, to: i + 1)
                i += 1
            case 0x21...0x7E:
                throw ExpressionError(.unexpectedCharacter(Character(Unicode.Scalar(b))), at: here)
            default:
                throw ExpressionError(.unexpectedByte(b), at: here)
            }
        }
        tokens.append(Token(kind: .end, text: "", position: SourcePosition(line: line, column: i - lineStart + 1)))
        return tokens
    }

    // MARK: Numbers

    /// The end of a well-formed number starting at `start`, or nil when it is malformed (contract E1).
    private static func numberEnd(_ bytes: [UInt8], from start: Int) -> Int? {
        var i = start
        while i < bytes.count, isDigit(bytes[i]) { i += 1 }
        if i < bytes.count, bytes[i] == UInt8(ascii: ".") {
            guard i + 1 < bytes.count, isDigit(bytes[i + 1]) else { return nil }
            i += 1
            while i < bytes.count, isDigit(bytes[i]) { i += 1 }
        }
        if i < bytes.count, bytes[i] == UInt8(ascii: "e") || bytes[i] == UInt8(ascii: "E") {
            var j = i + 1
            if j < bytes.count, bytes[j] == UInt8(ascii: "+") || bytes[j] == UInt8(ascii: "-") { j += 1 }
            guard j < bytes.count, isDigit(bytes[j]) else { return nil }
            i = j
            while i < bytes.count, isDigit(bytes[i]) { i += 1 }
        }
        if i < bytes.count, isNameCharacter(bytes[i]) || bytes[i] == UInt8(ascii: ".") { return nil }
        return i
    }

    /// The end of a malformed number's text: the run of letters, digits, `_` and `.`, plus a sign
    /// directly after an exponent letter.
    private static func malformedEnd(_ bytes: [UInt8], from start: Int) -> Int {
        var i = start
        while i < bytes.count {
            let b = bytes[i]
            let afterExponent = i > start && (bytes[i - 1] == UInt8(ascii: "e") || bytes[i - 1] == UInt8(ascii: "E"))
            if isNameCharacter(b) || b == UInt8(ascii: ".")
                || (afterExponent && (b == UInt8(ascii: "+") || b == UInt8(ascii: "-"))) {
                i += 1
            } else {
                break
            }
        }
        return i
    }

    // MARK: Helpers

    static func position(ofOffset offset: Int, in bytes: [UInt8]) -> SourcePosition {
        var line = 1
        var lineStart = 0
        for i in 0..<Swift.min(offset, bytes.count) where bytes[i] == 0x0A {
            line += 1
            lineStart = i + 1
        }
        return SourcePosition(line: line, column: offset - lineStart + 1)
    }

    private static func text(_ bytes: [UInt8], _ start: Int, _ end: Int) -> String {
        String(decoding: bytes[start..<end], as: UTF8.self)
    }

    private static func isDigit(_ b: UInt8) -> Bool { b >= 0x30 && b <= 0x39 }

    private static func isNameStart(_ b: UInt8) -> Bool {
        (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) || b == 0x5F
    }

    private static func isNameCharacter(_ b: UInt8) -> Bool { isNameStart(b) || isDigit(b) }
}
