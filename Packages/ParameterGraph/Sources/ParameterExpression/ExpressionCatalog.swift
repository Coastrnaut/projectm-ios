// ExpressionCatalog.swift — the closed sets of names a formula may use (SHD-009-R2, R3, R4;
// contract E3, E4, E5).
//
// Audio names are parsed only by MOD-002's `AudioFeatureSource(id:)`, so the language accepts
// exactly the features a binding can follow and nothing else.
import ParameterGraph

/// What a non-binding name stands for.
enum ExpressionValueName: Equatable {
    case time
    case constant(Double)
    case audio(AudioFeatureSource)
}

/// One whitelisted function.
struct ExpressionFunction {
    let arity: Int
    let opcode: ExpressionOpcode
}

enum ExpressionCatalog {
    /// `time`, the constants `pi`, `tau`, `e`, and the MOD-002 audio features; nil for anything else.
    static func value(named name: String) -> ExpressionValueName? {
        switch name {
        case "time": return .time
        case "pi": return .constant(Double.pi)
        case "tau": return .constant(2 * Double.pi)
        case "e": return .constant(2.718281828459045)
        default:
            guard let source = AudioFeatureSource(id: name) else { return nil }
            if case .lfo = source { return nil }   // MOD-007-D4: oscillators are binding sources, not formula names
            return .audio(source)
        }
    }

    /// The whitelist with fixed argument counts (contract E4).
    static func function(named name: String) -> ExpressionFunction? {
        switch name {
        case "min": ExpressionFunction(arity: 2, opcode: .min)
        case "max": ExpressionFunction(arity: 2, opcode: .max)
        case "clamp": ExpressionFunction(arity: 3, opcode: .clamp)
        case "abs": ExpressionFunction(arity: 1, opcode: .abs)
        case "sin": ExpressionFunction(arity: 1, opcode: .sin)
        case "cos": ExpressionFunction(arity: 1, opcode: .cos)
        case "floor": ExpressionFunction(arity: 1, opcode: .floor)
        case "fract": ExpressionFunction(arity: 1, opcode: .fract)
        case "mix": ExpressionFunction(arity: 3, opcode: .mix)
        case "smoothstep": ExpressionFunction(arity: 3, opcode: .smoothstep)
        case "step": ExpressionFunction(arity: 2, opcode: .step)
        case "sqrt": ExpressionFunction(arity: 1, opcode: .sqrt)
        case "pow": ExpressionFunction(arity: 2, opcode: .pow)
        default: nil
        }
    }

    /// Names a binding may not take: the keyword, `time`, the constants, the `audio` namespace and
    /// every function.
    static func isReserved(_ name: String) -> Bool {
        switch name {
        case "let", "time", "pi", "tau", "e", "audio": true
        default: function(named: name) != nil
        }
    }
}
