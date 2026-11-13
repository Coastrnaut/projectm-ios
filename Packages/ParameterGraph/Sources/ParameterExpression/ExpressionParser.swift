// ExpressionParser.swift — tokens to a small tree (SHD-009-R1, R5, R6; contract E2).
//
// Recursive descent. Every descent that can recurse (a parenthesis group, a call's arguments, a
// unary operand) first raises the nesting level and checks it against the limit, so the parser's
// own recursion is bounded by construction; binary chains are loops. Node and binding counts are
// checked at the token that would exceed them.

enum UnaryOperator { case plus, minus }

enum BinaryOperator {
    case add, subtract, multiply, divide

    var opcode: ExpressionOpcode {
        switch self {
        case .add: .add
        case .subtract: .subtract
        case .multiply: .multiply
        case .divide: .divide
        }
    }
}

indirect enum ExpressionNode {
    case number(Double, SourcePosition)
    case name(String, SourcePosition)
    case call(String, [ExpressionNode], SourcePosition)
    case unary(UnaryOperator, ExpressionNode, SourcePosition)
    case binary(BinaryOperator, ExpressionNode, ExpressionNode, SourcePosition)

    var position: SourcePosition {
        switch self {
        case let .number(_, p), let .name(_, p), let .call(_, _, p), let .unary(_, _, p), let .binary(_, _, _, p): p
        }
    }
}

struct ParsedBinding {
    let name: String
    let namePosition: SourcePosition
    let body: ExpressionNode
}

struct ParsedProgram {
    let bindings: [ParsedBinding]
    let result: ExpressionNode
}

struct ExpressionParser {
    private let tokens: [Token]
    private let limits: ExpressionLimits
    private var index = 0
    private var nesting = 0
    private var nodes = 0

    static func parse(_ tokens: [Token], limits: ExpressionLimits) throws(ExpressionError) -> ParsedProgram {
        var parser = ExpressionParser(tokens: tokens, limits: limits)
        return try parser.program()
    }

    private init(tokens: [Token], limits: ExpressionLimits) {
        self.tokens = tokens
        self.limits = limits
    }

    private var current: Token { tokens[index] }

    private mutating func advance() {
        if index < tokens.count - 1 { index += 1 }
    }

    private func isPunctuation(_ character: Character) -> Bool {
        if case let .punctuation(b) = current.kind { return b == character.asciiValue }
        return false
    }

    private mutating func expect(_ character: Character) throws(ExpressionError) {
        guard isPunctuation(character) else {
            throw ExpressionError(.expected("'\(character)'", found: current.quoted), at: current.position)
        }
        advance()
    }

    private mutating func countNode(at position: SourcePosition) throws(ExpressionError) {
        nodes += 1
        if nodes > limits.maximumNodes { throw ExpressionError(.tooManyNodes(limit: limits.maximumNodes), at: position) }
    }

    private mutating func enterNesting(at position: SourcePosition) throws(ExpressionError) {
        nesting += 1
        if nesting > limits.maximumNesting { throw ExpressionError(.tooDeep(limit: limits.maximumNesting), at: position) }
    }

    // program = { "let" name "=" expr ";" } expr END
    private mutating func program() throws(ExpressionError) -> ParsedProgram {
        var bindings: [ParsedBinding] = []
        while case .letKeyword = current.kind {
            if bindings.count >= limits.maximumBindings {
                throw ExpressionError(.tooManyBindings(limit: limits.maximumBindings), at: current.position)
            }
            advance()
            guard case let .name(name) = current.kind else {
                throw ExpressionError(.expected("a binding name", found: current.quoted), at: current.position)
            }
            let namePosition = current.position
            advance()
            try expect("=")
            let body = try expression()
            try expect(";")
            bindings.append(ParsedBinding(name: name, namePosition: namePosition, body: body))
        }
        let result = try expression()
        guard case .end = current.kind else {
            throw ExpressionError(.expected("end of input", found: current.quoted), at: current.position)
        }
        return ParsedProgram(bindings: bindings, result: result)
    }

    // expr = term { ("+" | "-") term }
    private mutating func expression() throws(ExpressionError) -> ExpressionNode {
        var lhs = try term()
        while isPunctuation("+") || isPunctuation("-") {
            let op: BinaryOperator = isPunctuation("+") ? .add : .subtract
            let position = current.position
            try countNode(at: position)
            advance()
            let rhs = try term()
            lhs = .binary(op, lhs, rhs, position)
        }
        return lhs
    }

    // term = unary { ("*" | "/") unary }
    private mutating func term() throws(ExpressionError) -> ExpressionNode {
        var lhs = try unary()
        while isPunctuation("*") || isPunctuation("/") {
            let op: BinaryOperator = isPunctuation("*") ? .multiply : .divide
            let position = current.position
            try countNode(at: position)
            advance()
            let rhs = try unary()
            lhs = .binary(op, lhs, rhs, position)
        }
        return lhs
    }

    // unary = ("+" | "-") unary | primary
    private mutating func unary() throws(ExpressionError) -> ExpressionNode {
        guard isPunctuation("+") || isPunctuation("-") else { return try primary() }
        let op: UnaryOperator = isPunctuation("+") ? .plus : .minus
        let position = current.position
        try countNode(at: position)
        try enterNesting(at: position)
        advance()
        let operand = try unary()
        nesting -= 1
        return .unary(op, operand, position)
    }

    // primary = number | name | name "(" [ expr { "," expr } ] ")" | "(" expr ")"
    private mutating func primary() throws(ExpressionError) -> ExpressionNode {
        let token = current
        switch token.kind {
        case let .number(value):
            try countNode(at: token.position)
            advance()
            return .number(value, token.position)
        case let .name(name):
            try countNode(at: token.position)
            advance()
            guard isPunctuation("(") else { return .name(name, token.position) }
            try enterNesting(at: current.position)
            advance()
            var arguments: [ExpressionNode] = []
            if !isPunctuation(")") {
                arguments.append(try expression())
                while isPunctuation(",") {
                    advance()
                    arguments.append(try expression())
                }
            }
            guard isPunctuation(")") else {
                throw ExpressionError(.expected("',' or ')'", found: current.quoted), at: current.position)
            }
            advance()
            nesting -= 1
            return .call(name, arguments, token.position)
        case .punctuation(UInt8(ascii: "(")):
            try enterNesting(at: token.position)
            advance()
            let inner = try expression()
            try expect(")")
            nesting -= 1
            return inner
        default:
            throw ExpressionError(.expected("an expression", found: token.quoted), at: token.position)
        }
    }
}
