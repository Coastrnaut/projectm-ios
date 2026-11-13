// ExpressionFuzzTests.swift — SHD-009-T16: fixed-seed random and mutated sources never crash; each
// is rejected with a position inside the source or compiles and evaluates finite (SHD-009-R7, R8;
// S4).
import ParameterExpression
import XCTest

/// SplitMix64: a small deterministic generator.
private struct SplitMix64 {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func below(_ bound: Int) -> Int { Int(next() % UInt64(bound)) }
}

final class ExpressionFuzzTests: XCTestCase {
    private static let alphabet: [UInt8] = Array("0123456789.eE+-*/(),;= \n\tabcdefghijklmnopqrstuvwxyz_".utf8)
    private static let words: [String] = ["let ", "audio.band.", "audio.onset", "audio.bandMean", "time", "sin(", "clamp(",
                                          "pow(", "smoothstep(", "mix(", "1e308", "x", " = ", ";", ")", "("]

    private var accepted = 0
    private var rejected = 0

    func testRandomAndMutatedSources() {
        var random = SplitMix64(state: 0x5D09)
        for _ in 0..<1_000 {
            var bytes: [UInt8] = []
            let length = random.below(601)
            while bytes.count < length {
                switch random.below(10) {
                case 0: bytes.append(UInt8(truncatingIfNeeded: random.next()))
                case 1, 2: bytes += Array(Self.words[random.below(Self.words.count)].utf8)
                default: bytes.append(Self.alphabet[random.below(Self.alphabet.count)])
                }
            }
            check(String(decoding: bytes, as: UTF8.self))
        }
        for _ in 0..<1_000 {
            var bytes = Array(ExpressionFixtures.valid[random.below(ExpressionFixtures.valid.count)].utf8)
            for _ in 0..<(1 + random.below(4)) {
                let at = random.below(bytes.count + 1)
                switch random.below(4) {
                case 0: bytes.insert(Self.alphabet[random.below(Self.alphabet.count)], at: at)
                case 1 where at < bytes.count: bytes.removeSubrange(at..<Swift.min(bytes.count, at + 1 + random.below(4)))
                case 2 where at < bytes.count: bytes[at] = Self.alphabet[random.below(Self.alphabet.count)]
                default:
                    let end = Swift.min(bytes.count, at + random.below(12))
                    bytes.insert(contentsOf: bytes[at..<end], at: at)
                }
            }
            check(String(decoding: bytes, as: UTF8.self))
        }
        XCTAssertEqual(accepted + rejected, 2_000)
        XCTAssertGreaterThan(accepted, 50, "the mutations keep a useful share of valid formulas")
        XCTAssertGreaterThan(rejected, 1_000)
    }

    private func check(_ source: String) {
        do {
            let compiled = try CompiledExpression(source: source)
            accepted += 1
            XCTAssertLessThanOrEqual(compiled.operationCost, 256, source)
            XCTAssertEqual(try CompiledExpression(source: source).bytes, compiled.bytes, source)
            for inputs in Self.extremeInputs {
                XCTAssertTrue(inputs.evaluate(compiled).isFinite, source)
            }
        } catch {
            rejected += 1
            let lines = source.utf8.split(separator: 0x0A, omittingEmptySubsequences: false)
            let position = error.position
            XCTAssertTrue(position.line >= 1 && position.line <= lines.count, "\(source.debugDescription): \(error)")
            if position.line >= 1, position.line <= lines.count {
                XCTAssertTrue(position.column >= 1 && position.column <= lines[position.line - 1].count + 1,
                              "\(source.debugDescription): \(error)")
            }
        }
    }

    private static let extremeInputs: [ExpressionTestInputs] = [
        ExpressionTestInputs(),
        ExpressionTestInputs(bands: [Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, .nan, .infinity],
                             onset: .nan, beatConfidence: 1e300, time: 1e12),
        ExpressionTestInputs(bands: Array(repeating: -Float.greatestFiniteMagnitude, count: 128), onset: -1e30,
                             beatConfidence: -.infinity, time: -1e300),
        ExpressionTestInputs(bands: [], onset: nil, beatConfidence: nil, time: 0),
    ]
}
