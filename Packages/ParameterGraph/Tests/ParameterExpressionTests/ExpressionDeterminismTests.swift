// ExpressionDeterminismTests.swift — SHD-009-T15: same source → identical compiled form; same
// inputs → bit-identical result (SHD-009-R8; S5; data-model.md byte form).
import ParameterExpression
import XCTest

final class ExpressionDeterminismTests: XCTestCase {
    func testCompilingTwiceGivesIdenticalForms() throws {
        for source in ExpressionFixtures.valid {
            let first = try CompiledExpression(source: source)
            let second = try CompiledExpression(source: source)
            XCTAssertEqual(first, second, source)
            XCTAssertEqual(first.instructions, second.instructions, source)
            XCTAssertEqual(first.bytes, second.bytes, source)
        }
    }

    func testPinnedByteForm() throws {
        let compiled = try CompiledExpression(source: "1 + time")
        let expected: [UInt8] = [
            0x50, 0x4D, 0x58, 0x01,   // "PMX", version 1
            0x00, 0x00, 0x02, 0x00, 0x03, 0x00,   // 0 slots, stack 2, 3 instructions
            0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xF0, 0x3F,   // constant 1.0
            0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,   // time
            0x0A, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,   // add
        ]
        XCTAssertEqual(compiled.bytes, expected)
        let bound = try CompiledExpression(source: "let b = a; let a = audio.band.5; b")
        XCTAssertEqual(bound.instructions, [
            ExpressionInstruction(opcode: .band, index: 5), ExpressionInstruction(opcode: .store, index: 1),
            ExpressionInstruction(opcode: .load, index: 1), ExpressionInstruction(opcode: .store, index: 0),
            ExpressionInstruction(opcode: .load, index: 0),
        ])
    }

    func testRepeatedEvaluationIsBitIdentical() throws {
        let inputs = ExpressionTestInputs()
        for source in ExpressionFixtures.valid {
            let compiled = try CompiledExpression(source: source)
            let first = inputs.evaluate(compiled).bitPattern
            for _ in 0..<1_000 where inputs.evaluate(compiled).bitPattern != first {
                XCTFail(source)
                break
            }
        }
    }
}
