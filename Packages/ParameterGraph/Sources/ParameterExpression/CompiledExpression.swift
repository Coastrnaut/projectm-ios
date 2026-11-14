// CompiledExpression.swift — the closed instruction set, the compiled form and its evaluation
// (SHD-009-R7 to R10, R13; data-model.md; contract E6; research SHD-009-D2, D6).
//
// A compiled formula is an immutable value: a list of stack-machine instructions with permanent
// opcodes, run by one `switch` loop. There are no jumps, so evaluation runs each instruction
// exactly once. Scratch values (binding slots, then the stack) live in a buffer sized at compile
// time and placed on the stack by `withUnsafeTemporaryAllocation`; evaluation touches no heap.
import ParameterGraph

/// The instruction set. Raw values are permanent (they appear in `CompiledExpression.bytes`).
public enum ExpressionOpcode: UInt8, Sendable, Hashable, CaseIterable {
    case constant = 1
    case time = 2
    case band = 3
    case bandMean = 4
    case onset = 5
    case beatConfidence = 6
    case load = 7
    case store = 8
    /// `audio.kick` (ANL-007).
    case kick = 9
    case add = 10
    case subtract = 11
    case multiply = 12
    case divide = 13
    case negate = 14
    /// `audio.centroid` (ANL-010).
    case centroid = 15
    /// `audio.loudness` (ANL-014).
    case loudness = 16
    /// `audio.midTransient` (ANL-008).
    case midTransient = 17
    /// `audio.highTransient` (ANL-009).
    case highTransient = 18
    case min = 20
    case max = 21
    case clamp = 22
    case abs = 23
    case sin = 24
    case cos = 25
    case floor = 26
    case fract = 27
    case mix = 28
    case smoothstep = 29
    case step = 30
    case sqrt = 31
    case pow = 32

    /// The change in stack depth.
    var stackEffect: Int {
        switch self {
        case .constant, .time, .band, .bandMean, .onset, .beatConfidence, .kick, .centroid, .loudness, .midTransient, .highTransient,
             .load: 1
        case .store: -1
        case .add, .subtract, .multiply, .divide, .min, .max, .step, .pow: -1
        case .negate, .abs, .sin, .cos, .floor, .fract, .sqrt: 0
        case .clamp, .mix, .smoothstep: -2
        }
    }
}

/// One instruction: an opcode, a band or slot index, a literal for constants. Equality compares
/// the literal's bits, so compiled forms compare exactly.
public struct ExpressionInstruction: Sendable, Hashable {
    public let opcode: ExpressionOpcode
    public let index: UInt16
    public let literal: Double

    public init(opcode: ExpressionOpcode, index: UInt16 = 0, literal: Double = 0) {
        self.opcode = opcode
        self.index = index
        self.literal = literal
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.opcode == rhs.opcode && lhs.index == rhs.index && lhs.literal.bitPattern == rhs.literal.bitPattern
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(opcode)
        hasher.combine(index)
        hasher.combine(literal.bitPattern)
    }
}

/// What a formula reads: one frame of MOD-002 audio features (borrowed for the call) and the time.
public struct ExpressionInputs {
    public var frame: AudioFeatureFrame
    /// Seconds; a non-finite time reads 0.
    public var timeSeconds: Double

    public init(frame: AudioFeatureFrame, timeSeconds: Double = 0) {
        self.frame = frame
        self.timeSeconds = timeSeconds
    }

    /// No audio at time 0.
    public static var silent: ExpressionInputs { ExpressionInputs(frame: .silent) }
}

public struct CompiledExpression: Sendable, Hashable {
    public let source: String
    public let limits: ExpressionLimits
    /// Bindings in dependency order (each followed by its `store`), then the result.
    public let instructions: [ExpressionInstruction]
    /// One slot per `let` binding (slot = the binding's place in the source).
    public let slotCount: Int
    public let maximumStackDepth: Int
    /// The static weighted instruction count (≤ `limits.maximumOperationCost`).
    public let operationCost: Int
    /// The MOD-002 features the formula reads, in first-use (source) order, without duplicates.
    public let audioSources: [AudioFeatureSource]
    public let readsTime: Bool

    /// Compiles `source` (contract E1-E7); throws the first problem with its position.
    public init(source: String, limits: ExpressionLimits = .standard) throws(ExpressionError) {
        var work = ExpressionCompileWork()
        try self.init(source: source, limits: limits, work: &work)
    }

    /// Compiles `source` and reports the counted work (SHD-010-R5, contract B4), whether it compiled
    /// or was refused. Compile off the frame loop; the frame loop only evaluates (contract B1).
    public static func measure(source: String, limits: ExpressionLimits = .standard)
        -> (result: Result<CompiledExpression, ExpressionError>, work: ExpressionCompileWork) {
        var work = ExpressionCompileWork()
        do {
            return (.success(try CompiledExpression(source: source, limits: limits, work: &work)), work)
        } catch {
            return (.failure(error), work)
        }
    }

    private init(source: String, limits: ExpressionLimits, work: inout ExpressionCompileWork) throws(ExpressionError) {
        let tokens = try ExpressionLexer.tokens(of: source, limits: limits, work: &work)
        let program = try ExpressionParser.parse(tokens, limits: limits, work: &work)
        let output = try ExpressionCompiler.compile(program, limits: limits, work: &work)
        self.source = source
        self.limits = limits
        self.instructions = output.instructions
        self.slotCount = output.slotCount
        self.maximumStackDepth = output.maximumStackDepth
        self.operationCost = output.operationCost
        self.audioSources = output.audioSources
        self.readsTime = output.readsTime
    }

    /// The byte form: `PMX`, version 1, slot count, maximum stack depth and instruction count
    /// (UInt16 little-endian each), then per instruction the opcode (1 byte), the index (UInt16 LE)
    /// and the literal's bit pattern (UInt64 LE).
    public var bytes: [UInt8] {
        var out: [UInt8] = [0x50, 0x4D, 0x58, 1]
        out.reserveCapacity(10 + instructions.count * 11)
        func put16(_ value: Int) {
            out.append(UInt8(truncatingIfNeeded: value))
            out.append(UInt8(truncatingIfNeeded: value >> 8))
        }
        put16(slotCount)
        put16(maximumStackDepth)
        put16(instructions.count)
        for instruction in instructions {
            out.append(instruction.opcode.rawValue)
            put16(Int(instruction.index))
            let bits = instruction.literal.bitPattern
            for shift in stride(from: 0, to: 64, by: 8) { out.append(UInt8(truncatingIfNeeded: bits >> UInt64(shift))) }
        }
        return out
    }

    /// The formula's value for `inputs`: always finite, deterministic, no heap allocation.
    public func evaluate(_ inputs: ExpressionInputs) -> Double {
        evaluate(inputs, bandMean: nil)
    }

    /// `bandMean`, when given, is `audio.bandMean` for `inputs.frame` computed once by the caller (the
    /// frame snapshot); otherwise the mean is computed at most once per evaluation, however often the
    /// formula reads it (SHD-010-D4: a read is then a load, not a sum over up to 128 bands).
    func evaluate(_ inputs: ExpressionInputs, bandMean: Double?) -> Double {
        var mean = bandMean
        let time = inputs.timeSeconds.isFinite ? inputs.timeSeconds : 0
        let frame = inputs.frame
        let capacity = Swift.max(1, slotCount + maximumStackDepth)
        return withUnsafeTemporaryAllocation(of: Double.self, capacity: capacity) { (memory: UnsafeMutableBufferPointer<Double>) -> Double in
            memory.initialize(repeating: 0)
            var top = slotCount   // next free stack position; slots occupy 0..<slotCount
            for instruction in instructions {
                switch instruction.opcode {
                case .constant:
                    memory[top] = instruction.literal
                    top += 1
                case .time:
                    memory[top] = time
                    top += 1
                case .band:
                    memory[top] = AudioFeatureSource.band(Int(instruction.index)).value(in: frame)
                    top += 1
                case .bandMean:
                    let value: Double
                    if let mean {
                        value = mean
                    } else {
                        value = AudioFeatureSource.bandMean.value(in: frame)
                        mean = value
                    }
                    memory[top] = value
                    top += 1
                case .onset:
                    memory[top] = AudioFeatureSource.onset.value(in: frame)
                    top += 1
                case .beatConfidence:
                    memory[top] = AudioFeatureSource.beatConfidence.value(in: frame)
                    top += 1
                case .kick:
                    memory[top] = AudioFeatureSource.kick.value(in: frame)
                    top += 1
                case .centroid:
                    memory[top] = AudioFeatureSource.centroid.value(in: frame)
                    top += 1
                case .loudness:
                    memory[top] = AudioFeatureSource.loudness.value(in: frame)
                    top += 1
                case .midTransient:
                    memory[top] = AudioFeatureSource.midTransient.value(in: frame)
                    top += 1
                case .highTransient:
                    memory[top] = AudioFeatureSource.highTransient.value(in: frame)
                    top += 1
                case .load:
                    memory[top] = memory[Int(instruction.index)]
                    top += 1
                case .store:
                    top -= 1
                    memory[Int(instruction.index)] = memory[top]
                case .negate:
                    memory[top - 1] = -memory[top - 1]
                case .abs:
                    memory[top - 1] = Swift.abs(memory[top - 1])
                case .sin:
                    memory[top - 1] = ExpressionMath.sine(memory[top - 1])
                case .cos:
                    memory[top - 1] = ExpressionMath.cosine(memory[top - 1])
                case .floor:
                    memory[top - 1] = ExpressionMath.floor(memory[top - 1])
                case .fract:
                    memory[top - 1] = ExpressionMath.fract(memory[top - 1])
                case .sqrt:
                    memory[top - 1] = ExpressionMath.squareRoot(memory[top - 1])
                case .add, .subtract, .multiply, .divide, .min, .max, .step, .pow:
                    top -= 1
                    let a = memory[top - 1]
                    let b = memory[top]
                    memory[top - 1] = switch instruction.opcode {
                    case .add: ExpressionMath.finite(a + b)
                    case .subtract: ExpressionMath.finite(a - b)
                    case .multiply: ExpressionMath.finite(a * b)
                    case .divide: ExpressionMath.divide(a, b)
                    case .min: Swift.min(a, b)
                    case .max: Swift.max(a, b)
                    case .step: ExpressionMath.step(a, b)
                    default: ExpressionMath.power(a, b)
                    }
                case .clamp, .mix, .smoothstep:
                    top -= 2
                    let a = memory[top - 1]
                    let b = memory[top]
                    let c = memory[top + 1]
                    memory[top - 1] = switch instruction.opcode {
                    case .clamp: ExpressionMath.clamp(a, b, c)
                    case .mix: ExpressionMath.mix(a, b, c)
                    default: ExpressionMath.smoothstep(a, b, c)
                    }
                }
            }
            return ExpressionMath.finite(memory[top - 1])
        }
    }
}
