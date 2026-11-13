// CompiledGeneratorGraph.swift — the compiled plan: fixed-size instructions for the interpreter, the
// per-frame time terms, the derived speed and music limits and the plan's bytes (SHD-002-R6, R12;
// data-model.md "CompiledGeneratorGraph"; contracts/generator-graph.md "Plan bytes").
//
// The instruction layout matches `GraphInstr` in GeneratorGraphShaders.swift (80 bytes). Operand
// sources: a register 0…15, `literalSource` (use the instruction's literal) or `coordinatesSource`
// (the picture coordinates). Bit i of `flags` asks the interpreter to clamp operand i to the
// input's range, stored in that operand's literal (x = lower, y = upper) when it is connected.
// Plain Swift; builds on Linux.

public struct GraphInstruction: Sendable, Equatable {
    public static let byteCount = 80
    public static let literalSource: UInt32 = 0xFF
    public static let coordinatesSource: UInt32 = 0xFE

    public var op: UInt32
    public var dst: UInt32
    /// Operand sources a | b << 8 | c << 16.
    public var sources: UInt32
    public var flags: UInt32
    public var a: SIMD4<Float>
    public var b: SIMD4<Float>
    public var c: SIMD4<Float>
    public var settings: SIMD4<Float>

    public func source(_ slot: Int) -> UInt32 { (sources >> (8 * UInt32(slot))) & 0xFF }
}

/// What the CPU computes for an instruction each frame, in double precision (research SHD-002-D6).
public enum GraphTimeTerm: Sendable, Equatable {
    case none
    /// fract(rate · phase + offset): oscillate, spin, palette shift.
    case cycle(rate: Double, offset: Double)
    /// velocity · phase, each component wrapped to ±`driftWrap`.
    case drift(x: Double, y: Double)

    public static let driftWrap = 1024.0

    public func value(phase: Double) -> SIMD4<Float> {
        switch self {
        case .none:
            return .zero
        case let .cycle(rate, offset):
            let v = rate * phase + offset
            return SIMD4(Float(v - v.rounded(.down)), 0, 0, 0)
        case let .drift(x, y):
            return SIMD4(Float(Self.wrap(x * phase)), Float(Self.wrap(y * phase)), 0, 0)
        }
    }

    static func wrap(_ v: Double) -> Double {
        guard v.isFinite else { return 0 }
        let period = 2 * driftWrap
        return v - period * ((v + driftWrap) / period).rounded(.down)
    }

    var code: UInt32 {
        switch self {
        case .none: return 0
        case .cycle: return 1
        case .drift: return 2
        }
    }

    var constants: (Double, Double) {
        switch self {
        case .none: return (0, 0)
        case let .cycle(r, o): return (r, o)
        case let .drift(x, y): return (x, y)
        }
    }
}

public struct CompiledGeneratorGraph: Sendable, Equatable {
    public static let planVersion: UInt32 = 1

    public let name: String
    /// Phase cycles per second allowed: min(1, π / timeRateBound).
    public let speedCap: Double
    /// The music follower's largest change per second: min(1, π / musicRateBound).
    public let musicRate: Double
    /// The document's speed, clamped to ±speedCap.
    public let defaultSpeed: Double
    /// Bound on the output's change per unit of phase and of music level (per channel).
    public let timeRateBound: Double
    public let musicRateBound: Double
    /// Every node that feeds the output, in execution order (output last).
    public let order: [String]
    public let instructions: [GraphInstruction]
    public let timeTerms: [GraphTimeTerm]
    public let registerCount: Int

    /// The plan as bytes: identical for the same graph in any node order.
    public var planBytes: [UInt8] {
        var w = ByteWriter()
        w.raw(Array("SHD2".utf8))
        w.u32(Self.planVersion)
        w.u32(UInt32(instructions.count))
        w.u32(UInt32(registerCount))
        w.u64(speedCap.bitPattern)
        w.u64(musicRate.bitPattern)
        w.raw(instructionBytes)
        for term in timeTerms {
            w.u32(term.code)
            let (k0, k1) = term.constants
            w.u64(k0.bitPattern)
            w.u64(k1.bitPattern)
            w.u64(0)
        }
        return w.bytes
    }

    /// The instructions alone, as the interpreter reads them.
    public var instructionBytes: [UInt8] {
        var w = ByteWriter()
        for i in instructions {
            w.u32(i.op); w.u32(i.dst); w.u32(i.sources); w.u32(i.flags)
            for v in [i.a, i.b, i.c, i.settings] {
                w.u32(v.x.bitPattern); w.u32(v.y.bitPattern); w.u32(v.z.bitPattern); w.u32(v.w.bitPattern)
            }
        }
        return w.bytes
    }

    /// Writes this frame's time terms into `terms` (at least `instructions.count` long).
    public func writeTimeTerms(phase: Double, into terms: inout [SIMD4<Float>]) {
        for (i, term) in timeTerms.enumerated() where i < terms.count { terms[i] = term.value(phase: phase) }
    }

    /// `speed` clamped to ±speedCap (non-finite reads 0).
    public func clampSpeed(_ speed: Double) -> Double {
        speed.isFinite ? min(max(speed, -speedCap), speedCap) : 0
    }
}

struct ByteWriter {
    var bytes: [UInt8] = []
    mutating func raw(_ b: [UInt8]) { bytes += b }
    mutating func u32(_ v: UInt32) { for k in 0..<4 { bytes.append(UInt8((v >> (8 * UInt32(k))) & 0xFF)) } }
    mutating func u64(_ v: UInt64) { for k in 0..<8 { bytes.append(UInt8((v >> (8 * UInt64(k))) & 0xFF)) } }
}
