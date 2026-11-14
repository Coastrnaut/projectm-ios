// ExpressionEvaluationTests.swift — SHD-009-T11: valid formulas evaluate to their exact values,
// bindings, audio sources and the mapping adapter (SHD-009-R1 to R3, R10; S1; contract E2-E5, E8).
import Foundation
import ParameterExpression
import ParameterGraph
import XCTest

final class ExpressionEvaluationTests: XCTestCase {
    func testValidTableEvaluatesExactly() throws {
        let inputs = ExpressionTestInputs()
        let expectations: [(String, Double)] = [
            ("1 + 2 * 3", 7), ("(1 + 2) * 3", 9), ("10 - 4 - 3", 3), ("16 / 4 / 2", 2), ("-2 * 3", -6),
            ("--2", 2), ("+3", 3), ("2 - -1", 3), ("1.5e2", 150), ("2.5E-1", 0.25),
            ("audio.band.0", 0.5), ("audio.band.3", 0.125), ("audio.band.10", 0), ("audio.bandMean", 0.46875),
            ("audio.onset", 0.75), ("audio.beatConfidence", 0.5), ("time", 2),
            ("pi", Double.pi), ("tau", 2 * Double.pi), ("e", 2.718281828459045),
            ("min(3, 4)", 3), ("max(3, 4)", 4), ("clamp(5, 0, 1)", 1), ("clamp(-1, 0, 1)", 0), ("abs(-2.5)", 2.5),
            ("sin(0)", 0), ("cos(0)", 1), ("floor(-1.5)", -2), ("fract(2.75)", 0.75), ("fract(-0.25)", 0.75),
            ("mix(2, 4, 0.25)", 2.5), ("smoothstep(0, 1, 0.5)", 0.5), ("smoothstep(0, 2, 4)", 1),
            ("step(0.5, 0.75)", 1), ("step(0.5, 0.25)", 0), ("sqrt(16)", 4), ("pow(2, 10)", 1024),
            ("clamp(audio.onset * 2 - 0.5, 0, 1)", 1),
            ("mix(audio.band.0, audio.band.2, 0.5 + 0.5 * sin(time))", 0.5 + (1 - 0.5) * (0.5 + 0.5 * Foundation.sin(2.0))),
            ("let a = 2; let b = a * 3; b + a", 8), ("let b = a * 3; let a = 2; b + a", 8), ("let unused = 5; 1", 1),
            ("1 +\n\t2", 3),
            ("let k = audio.onset * 2;\nlet s = smoothstep(0.2, 0.8, k);\nmix(0.1, 0.9, s) * (1 + 0.25 * cos(time * tau))",
             (0.1 + (0.9 - 0.1) * 1) * (1 + 0.25 * Foundation.cos(2 * (2 * Double.pi)))),
        ]
        XCTAssertEqual(expectations.map { (pair: (String, Double)) -> String in pair.0 }, ExpressionFixtures.valid,
                       "the fixture list and this table stay in step")
        for (source, expected) in expectations {
            let compiled = try CompiledExpression(source: source)
            XCTAssertEqual(inputs.evaluate(compiled).bitPattern, expected.bitPattern, "\(source) = \(inputs.evaluate(compiled))")
        }
    }

    func testBindingsEqualTheInlineForm() throws {
        let inputs = ExpressionTestInputs()
        let bound = try CompiledExpression(source: "let w = 0.5 + 0.5 * sin(time); let lo = audio.band.0; mix(lo, audio.band.2, w)")
        let inline = try CompiledExpression(source: "mix(audio.band.0, audio.band.2, 0.5 + 0.5 * sin(time))")
        XCTAssertEqual(inputs.evaluate(bound).bitPattern, inputs.evaluate(inline).bitPattern)
        XCTAssertEqual(bound.slotCount, 2)
        // Each binding is stored once, in dependency order, before the result.
        let stores = bound.instructions.filter { (instruction: ExpressionInstruction) -> Bool in instruction.opcode == .store }
        XCTAssertEqual(stores.map { (instruction: ExpressionInstruction) -> UInt16 in instruction.index }, [0, 1])
    }

    func testAudioSourcesAndTime() throws {
        let compiled = try CompiledExpression(source: "let x = audio.onset; x + audio.band.3 + audio.onset + time")
        XCTAssertEqual(compiled.audioSources, [.onset, .band(3)])
        XCTAssertTrue(compiled.readsTime)
        let constant = try CompiledExpression(source: "pi * 2")
        XCTAssertEqual(constant.audioSources, [])
        XCTAssertFalse(constant.readsTime)
    }

    /// ANL-007-T09: `audio.kick` compiles to opcode 9 and reads the frame's kick envelope.
    func testKickSourceInAFormula() throws {
        let compiled = try CompiledExpression(source: "audio.kick * 2 + audio.onset")
        XCTAssertEqual(compiled.audioSources, [.kick, .onset])
        XCTAssertTrue(compiled.instructions.contains { (instruction: ExpressionInstruction) -> Bool in
            instruction.opcode == .kick && instruction.opcode.rawValue == 9
        })
        let bands: [Float] = [0.5]
        let value = bands.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Double in
            let frame = AudioFeatureFrame(bands: buffer, onset: 0.25, kick: 0.125)
            return compiled.evaluate(ExpressionInputs(frame: frame, timeSeconds: 0))
        }
        XCTAssertEqual(value, 0.5)
        XCTAssertEqual(compiled.evaluate(.silent), 0)
    }

    /// ANL-010-T09: `audio.centroid` compiles to opcode 15 and reads the frame's normalized centroid.
    func testCentroidSourceInAFormula() throws {
        let compiled = try CompiledExpression(source: "1 - audio.centroid + audio.kick")
        XCTAssertEqual(compiled.audioSources, [.centroid, .kick])
        XCTAssertTrue(compiled.instructions.contains { (instruction: ExpressionInstruction) -> Bool in
            instruction.opcode == .centroid && instruction.opcode.rawValue == 15
        })
        let bands: [Float] = [0.5]
        let value = bands.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Double in
            let frame = AudioFeatureFrame(bands: buffer, kick: 0.125, centroid: 0.75)
            return compiled.evaluate(ExpressionInputs(frame: frame, timeSeconds: 0))
        }
        XCTAssertEqual(value, 0.375)
        XCTAssertEqual(compiled.evaluate(.silent), 1)
    }

    /// ANL-014-T08: `audio.loudness` compiles to opcode 16 and reads the frame's loudness envelope.
    func testLoudnessSourceInAFormula() throws {
        let compiled = try CompiledExpression(source: "audio.loudness * 2 - audio.centroid")
        XCTAssertEqual(compiled.audioSources, [.loudness, .centroid])
        XCTAssertTrue(compiled.instructions.contains { (instruction: ExpressionInstruction) -> Bool in
            instruction.opcode == .loudness && instruction.opcode.rawValue == 16
        })
        let bands: [Float] = [0.5]
        let value = bands.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Double in
            let frame = AudioFeatureFrame(bands: buffer, centroid: 0.25, loudness: 0.375)
            return compiled.evaluate(ExpressionInputs(frame: frame, timeSeconds: 0))
        }
        XCTAssertEqual(value, 0.5)
        XCTAssertEqual(compiled.evaluate(.silent), 0)
    }

    func testSilentInputsReadZero() throws {
        let compiled = try CompiledExpression(source: "audio.band.0 + audio.bandMean + audio.onset + audio.beatConfidence + time")
        XCTAssertEqual(compiled.evaluate(.silent), 0)
    }

    func testMappingAdapterUsesTheLinearOutputRange() throws {
        var inputs = ExpressionTestInputs()
        let doubled = try CompiledExpression(source: "audio.onset * 2")
        let mapping = ExpressionMapping(expression: doubled, outputStart: 0.2, outputEnd: 0.9)
        XCTAssertTrue(mapping.isValid)
        XCTAssertEqual(inputs.map(mapping), 0.9, "1.5 is limited to position 1: exactly the end")
        inputs.onset = 0.25
        XCTAssertEqual(inputs.map(mapping), LinearMapping.interpolate(from: 0.2, to: 0.9, at: 0.5))
        let inverted = ExpressionMapping(expression: doubled, outputStart: 0.9, outputEnd: 0.2)
        XCTAssertEqual(inputs.map(inverted), LinearMapping.interpolate(from: 0.9, to: 0.2, at: 0.5))
        let negative = ExpressionMapping(expression: try CompiledExpression(source: "-5"), outputStart: 0.3, outputEnd: 0.7)
        XCTAssertEqual(inputs.map(negative), 0.3, "below 0 is position 0: exactly the start")
        XCTAssertFalse(ExpressionMapping(expression: doubled, outputStart: .nan, outputEnd: 1).isValid)
    }
}
