// ExpressionCompiler.swift — names, recursion, order and code (SHD-009-R2 to R5, R8, R10;
// contract E3 to E7; research SHD-009-D3, D5).
//
// Phases after parsing, each reporting its first problem in source order:
// 1. names: each binding's name, then its body, in source order, then the result;
// 2. recursion: depth-first over bindings in source order, references in source order; a loop is
//    reported from its first binding in source order, at the reference that closes it;
// 3. code: bindings in dependency order (depth-first post-order), each stored once in its slot
//    (its source index), then the result; the running cost is checked at every instruction.
//
// SHD-010 (contract B4): every node resolved, binding named, dependency visit, reference followed,
// loop-report step and instruction emitted counts one step (`ExpressionCompileWork.compilerSteps`).
import ParameterGraph

/// A name resolved to what it reads.
private indirect enum ResolvedNode {
    case constant(Double, SourcePosition)
    case time(SourcePosition)
    case audio(AudioFeatureSource, SourcePosition)
    case binding(Int, SourcePosition)
    case negate(ResolvedNode, SourcePosition)
    case binary(ExpressionOpcode, ResolvedNode, ResolvedNode, SourcePosition)
    case call(ExpressionOpcode, [ResolvedNode], SourcePosition)
}

struct ExpressionCompiler {
    struct Output {
        let instructions: [ExpressionInstruction]
        let slotCount: Int
        let maximumStackDepth: Int
        let operationCost: Int
        let audioSources: [AudioFeatureSource]
        let readsTime: Bool
    }

    private let program: ParsedProgram
    private let limits: ExpressionLimits
    private var bindingIndex: [String: Int] = [:]
    /// Per binding, the bindings its body reads with the reading position, in source order.
    private var references: [[(target: Int, position: SourcePosition)]] = []
    private var audioSources: [AudioFeatureSource] = []
    private var audioSourceSet: Set<AudioFeatureSource> = []
    private var readsTime = false

    private var instructions: [ExpressionInstruction] = []
    private var cost = 0
    private var depth = 0
    private var maximumDepth = 0
    private var steps = 0

    static func compile(_ program: ParsedProgram, limits: ExpressionLimits,
                        work: inout ExpressionCompileWork) throws(ExpressionError) -> Output {
        var compiler = ExpressionCompiler(program: program, limits: limits)
        defer { work.compilerSteps += compiler.steps }
        return try compiler.run()
    }

    private init(program: ParsedProgram, limits: ExpressionLimits) {
        self.program = program
        self.limits = limits
    }

    private mutating func run() throws(ExpressionError) -> Output {
        // Bindings are declarative: every name is known before any body is resolved.
        for (i, binding) in program.bindings.enumerated() where bindingIndex[binding.name] == nil {
            bindingIndex[binding.name] = i
        }
        references = Array(repeating: [], count: program.bindings.count)

        // Phase: names.
        var bodies: [ResolvedNode] = []
        var seen: Set<String> = []
        for (i, binding) in program.bindings.enumerated() {
            steps += 1
            if binding.name.contains(".") {
                throw ExpressionError(.invalidBindingName(binding.name), at: binding.namePosition)
            }
            if ExpressionCatalog.isReserved(binding.name) {
                throw ExpressionError(.reservedBindingName(binding.name), at: binding.namePosition)
            }
            if !seen.insert(binding.name).inserted {
                throw ExpressionError(.duplicateBinding(binding.name), at: binding.namePosition)
            }
            bodies.append(try resolve(binding.body, inBinding: i))
        }
        let result = try resolve(program.result, inBinding: nil)

        // Phase: recursion.
        let order = try dependencyOrder()

        // Phase: code.
        for i in order {
            try emit(bodies[i])
            try append(ExpressionInstruction(opcode: .store, index: UInt16(i)), at: program.bindings[i].namePosition)
        }
        try emit(result)
        return Output(instructions: instructions, slotCount: program.bindings.count, maximumStackDepth: maximumDepth,
                      operationCost: cost, audioSources: audioSources, readsTime: readsTime)
    }

    // MARK: Names

    private mutating func resolve(_ node: ExpressionNode, inBinding owner: Int?) throws(ExpressionError) -> ResolvedNode {
        steps += 1
        switch node {
        case let .number(value, position):
            return .constant(value, position)
        case let .name(name, position):
            if let target = bindingIndex[name] {
                if let owner { references[owner].append((target, position)) }
                return .binding(target, position)
            }
            switch ExpressionCatalog.value(named: name) {
            case .time:
                readsTime = true
                return .time(position)
            case let .constant(value):
                return .constant(value, position)
            case let .audio(source):
                if audioSourceSet.insert(source).inserted { audioSources.append(source) }
                return .audio(source, position)
            case nil:
                if ExpressionCatalog.function(named: name) != nil {
                    throw ExpressionError(.functionWithoutCall(name), at: position)
                }
                throw ExpressionError(.unknownIdentifier(name), at: position)
            }
        case let .call(name, arguments, position):
            guard let function = ExpressionCatalog.function(named: name) else {
                if bindingIndex[name] != nil || ExpressionCatalog.value(named: name) != nil {
                    throw ExpressionError(.notAFunction(name), at: position)
                }
                throw ExpressionError(.unknownFunction(name), at: position)
            }
            guard arguments.count == function.arity else {
                throw ExpressionError(.wrongArgumentCount(function: name, expected: function.arity, found: arguments.count),
                                      at: position)
            }
            var resolved: [ResolvedNode] = []
            for argument in arguments { resolved.append(try resolve(argument, inBinding: owner)) }
            return .call(function.opcode, resolved, position)
        case let .unary(op, operand, position):
            let inner = try resolve(operand, inBinding: owner)
            return op == .plus ? inner : .negate(inner, position)
        case let .binary(op, lhs, rhs, position):
            let left = try resolve(lhs, inBinding: owner)
            let right = try resolve(rhs, inBinding: owner)
            return .binary(op.opcode, left, right, position)
        }
    }

    // MARK: Recursion

    /// Depth-first post-order of all bindings (dependencies first); throws on the first loop.
    private mutating func dependencyOrder() throws(ExpressionError) -> [Int] {
        let count = program.bindings.count
        var state = Array(repeating: 0, count: count)   // 0 new, 1 on the path, 2 done
        var path: [Int] = []
        var order: [Int] = []
        order.reserveCapacity(count)
        var visits = 0
        defer { steps += visits }

        func visit(_ i: Int) throws(ExpressionError) {
            visits += 1
            state[i] = 1
            path.append(i)
            for reference in references[i] {
                visits += 1
                let j = reference.target
                if state[j] == 1 {
                    let members = Array(path[path.lastIndex(of: j)!...])
                    visits += 3 * members.count + references[members[members.count - 1]].count
                    throw loopError(members)
                }
                if state[j] == 0 { try visit(j) }
            }
            path.removeLast()
            state[i] = 2
            order.append(i)
        }

        for i in 0..<count where state[i] == 0 { try visit(i) }
        return order
    }

    /// The loop `members` (each reads the next, the last reads the first), rotated to start at its
    /// first binding in source order and reported at the reference that closes it.
    private func loopError(_ members: [Int]) -> ExpressionError {
        let start = members.firstIndex(of: members.min()!)!
        let rotated = Array(members[start...] + members[..<start])
        let names = rotated.map { (i: Int) -> String in program.bindings[i].name } + [program.bindings[rotated[0]].name]
        let last = rotated[rotated.count - 1]
        let closing = references[last].first(where: { (reference: (target: Int, position: SourcePosition)) -> Bool in
            reference.target == rotated[0]
        })!.position
        return ExpressionError(.recursiveBinding(path: names.joined(separator: " → ")), at: closing)
    }

    // MARK: Code

    private mutating func emit(_ node: ResolvedNode) throws(ExpressionError) {
        switch node {
        case let .constant(value, position):
            try append(ExpressionInstruction(opcode: .constant, literal: value), at: position)
        case let .time(position):
            try append(ExpressionInstruction(opcode: .time), at: position)
        case let .audio(source, position):
            let instruction: ExpressionInstruction = switch source {
            case let .band(index): ExpressionInstruction(opcode: .band, index: UInt16(index))
            case .bandMean: ExpressionInstruction(opcode: .bandMean)
            case .onset: ExpressionInstruction(opcode: .onset)
            case .beatConfidence: ExpressionInstruction(opcode: .beatConfidence)
            case .kick: ExpressionInstruction(opcode: .kick)
            }
            try append(instruction, at: position)
        case let .binding(slot, position):
            try append(ExpressionInstruction(opcode: .load, index: UInt16(slot)), at: position)
        case let .negate(operand, position):
            try emit(operand)
            try append(ExpressionInstruction(opcode: .negate), at: position)
        case let .binary(opcode, lhs, rhs, position):
            try emit(lhs)
            try emit(rhs)
            try append(ExpressionInstruction(opcode: opcode), at: position)
        case let .call(opcode, arguments, position):
            for argument in arguments { try emit(argument) }
            try append(ExpressionInstruction(opcode: opcode), at: position)
        }
    }

    private mutating func append(_ instruction: ExpressionInstruction, at position: SourcePosition) throws(ExpressionError) {
        steps += 1
        cost += ExpressionLimits.cost(of: instruction.opcode)
        if cost > limits.maximumOperationCost {
            throw ExpressionError(.operationCostOverLimit(limit: limits.maximumOperationCost), at: position)
        }
        depth += instruction.opcode.stackEffect
        maximumDepth = Swift.max(maximumDepth, depth)
        instructions.append(instruction)
    }
}
