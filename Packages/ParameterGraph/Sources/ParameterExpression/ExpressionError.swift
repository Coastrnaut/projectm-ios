// ExpressionError.swift — why a formula was refused, and where (SHD-009-R6; contract E7).
//
// The message is `line:column: reason`; only the first problem is reported, in the contract's
// phase order, so every source has exactly one documented error.

/// A 1-based line and column; columns count bytes (only ASCII is accepted, so a byte is a character).
public struct SourcePosition: Sendable, Hashable, CustomStringConvertible {
    public var line: Int
    public var column: Int

    public init(line: Int, column: Int) {
        self.line = line
        self.column = column
    }

    public var description: String { "\(line):\(column)" }
}

public struct ExpressionError: Error, Sendable, Hashable, CustomStringConvertible {
    public enum Reason: Sendable, Hashable, CustomStringConvertible {
        case sourceTooLong(bytes: Int, limit: Int)
        case unexpectedCharacter(Character)
        case unexpectedByte(UInt8)
        case malformedNumber(String)
        case numberOutOfRange(String)
        case tooManyTokens(limit: Int)
        /// `expected` describes what the grammar needed; `found` is a quoted token or "end of input".
        case expected(String, found: String)
        case tooDeep(limit: Int)
        case tooManyNodes(limit: Int)
        case tooManyBindings(limit: Int)
        case unknownIdentifier(String)
        case unknownFunction(String)
        case notAFunction(String)
        case functionWithoutCall(String)
        case wrongArgumentCount(function: String, expected: Int, found: Int)
        case invalidBindingName(String)
        case reservedBindingName(String)
        case duplicateBinding(String)
        /// The loop of bindings, first name repeated at the end: `a → b → a`.
        case recursiveBinding(path: String)
        case operationCostOverLimit(limit: Int)

        public var description: String {
            switch self {
            case let .sourceTooLong(bytes, limit):
                "the source is \(bytes) bytes; at most \(limit) are allowed"
            case let .unexpectedCharacter(character):
                "unexpected character '\(character)'"
            case let .unexpectedByte(byte):
                "unexpected byte 0x\(Self.hex(byte))"
            case let .malformedNumber(text):
                "malformed number '\(text)'"
            case let .numberOutOfRange(text):
                "number '\(text)' is out of range"
            case let .tooManyTokens(limit):
                "more than \(limit) tokens"
            case let .expected(what, found):
                "expected \(what), found \(found)"
            case let .tooDeep(limit):
                "nesting deeper than \(limit) levels"
            case let .tooManyNodes(limit):
                "more than \(limit) expression nodes"
            case let .tooManyBindings(limit):
                "more than \(limit) bindings"
            case let .unknownIdentifier(name):
                "unknown identifier '\(name)'"
            case let .unknownFunction(name):
                "unknown function '\(name)'"
            case let .notAFunction(name):
                "'\(name)' is not a function"
            case let .functionWithoutCall(name):
                "function '\(name)' needs arguments, as in \(name)(x)"
            case let .wrongArgumentCount(function, expected, found):
                "'\(function)' takes \(expected) argument\(expected == 1 ? "" : "s"), found \(found)"
            case let .invalidBindingName(name):
                "binding name '\(name)' must not contain '.'"
            case let .reservedBindingName(name):
                "'\(name)' is a reserved name"
            case let .duplicateBinding(name):
                "'\(name)' is already defined"
            case let .recursiveBinding(path):
                "recursive binding: \(path)"
            case let .operationCostOverLimit(limit):
                "operation cost over \(limit)"
            }
        }

        private static func hex(_ byte: UInt8) -> String {
            let digits: [Character] = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "B", "C", "D", "E", "F"]
            return String([digits[Int(byte >> 4)], digits[Int(byte & 0x0F)]])
        }
    }

    public var position: SourcePosition
    public var reason: Reason

    public init(_ reason: Reason, at position: SourcePosition) {
        self.reason = reason
        self.position = position
    }

    public var description: String { "\(position): \(reason)" }
}
