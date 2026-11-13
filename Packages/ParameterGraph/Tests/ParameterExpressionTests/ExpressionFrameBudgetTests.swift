// ExpressionFrameBudgetTests.swift — SHD-010-T10: the per-frame budget is checked at admission, with
// exact messages, and the snapshot evaluates exactly the admitted formulas (SHD-010-R2 to R4, R8; S2;
// contract B1, B2).
import ParameterExpression
import ParameterGraph
import XCTest

final class ExpressionFrameBudgetTests: XCTestCase {
    /// Cost 256: 41 × sin(1) (245) + sqrt(audio.bandMean) (9) + 1 (2).
    private static let maximal = Array(repeating: "sin(1)", count: 41).joined(separator: "+") + "+sqrt(audio.bandMean)+1"

    func testDefaults() {
        let budget = ExpressionFrameBudget.standard
        XCTAssertEqual([budget.maximumExpressions, budget.maximumOperationCost], [32, 2048])
        XCTAssertEqual(budget.expressionLimits, .standard)
    }

    func testCostBudget() throws {
        let maximal = try CompiledExpression(source: Self.maximal)
        XCTAssertEqual(maximal.operationCost, 256)
        var frameSet = ExpressionFrameSet()
        var handles: [ExpressionFrameSet.Handle] = []
        for _ in 0..<8 { handles.append(try frameSet.admit(maximal)) }
        XCTAssertEqual(frameSet.usedCost, 2048)
        XCTAssertThrowsError(try frameSet.admit(try CompiledExpression(source: "1"))) { (error: Error) in
            XCTAssertEqual("\(error)", "a formula of cost 1 would bring the frame to 2049; at most 2048 is allowed (2048 used)")
        }
        XCTAssertEqual(frameSet.count, 8, "unchanged by the refusal")
        XCTAssertEqual(frameSet.usedCost, 2048)

        // Removing one frees exactly its cost; a formula of that cost fits again, one more does not.
        XCTAssertTrue(frameSet.remove(handles[3]))
        XCTAssertEqual(frameSet.usedCost, 1792)
        let cheap = try CompiledExpression(source: "audio.onset * 2")   // cost 3
        XCTAssertNoThrow(try frameSet.admit(cheap))
        XCTAssertThrowsError(try frameSet.admit(maximal)) { (error: Error) in
            XCTAssertEqual("\(error)", "a formula of cost 256 would bring the frame to 2051; at most 2048 is allowed (1795 used)")
        }
        // The budget is inclusive.
        let rest = try CompiledExpression(source: Array(repeating: "sin(1)", count: 42).joined(separator: "+") + "+1")   // 253
        XCTAssertEqual(rest.operationCost, 253)
        XCTAssertNoThrow(try frameSet.admit(rest))
        XCTAssertEqual(frameSet.usedCost, 2048)
    }

    func testCountBudget() throws {
        let one = try CompiledExpression(source: "audio.onset")
        var frameSet = ExpressionFrameSet()
        var handles: [ExpressionFrameSet.Handle] = []
        for _ in 0..<32 { handles.append(try frameSet.admit(one)) }
        XCTAssertThrowsError(try frameSet.admit(one)) { (error: Error) in
            XCTAssertEqual("\(error)", "the frame already evaluates 32 formulas; at most 32 are allowed")
        }
        XCTAssertEqual(frameSet.count, 32)
        XCTAssertTrue(frameSet.remove(handles[0]))
        let again = try frameSet.admit(one)
        XCTAssertEqual(again.rawValue, 33, "handles are never reused")
        XCTAssertFalse(frameSet.remove(handles[0]), "a removed handle removes nothing")
        // Handles are numbers, unique within one set (contract B1); 40 was never issued by this set.
        var other = ExpressionFrameSet(budget: ExpressionFrameBudget(maximumExpressions: 40))
        for _ in 0..<40 { _ = try other.admit(one) }
        XCTAssertFalse(frameSet.remove(other.handles[39]), "a number this set never issued removes nothing")
        XCTAssertEqual(frameSet.count, 32)
    }

    func testLooserLimitsAreRefused() throws {
        let loose = try CompiledExpression(source: Array(repeating: "sin(1)", count: 43).joined(separator: "+"),
                                           limits: ExpressionLimits(maximumOperationCost: 100_000))
        XCTAssertEqual(loose.operationCost, 257)
        var frameSet = ExpressionFrameSet()
        XCTAssertThrowsError(try frameSet.admit(loose)) { (error: Error) in
            XCTAssertEqual("\(error)", "the formula was compiled with an operation cost limit of 100000; the standard limit is 256")
        }
        // Several fields loosened: the first in the documented order is named.
        let twoLoose = try CompiledExpression(source: "1", limits: ExpressionLimits(maximumTokens: 300, maximumNesting: 20))
        XCTAssertThrowsError(try frameSet.admit(twoLoose)) { (error: Error) in
            XCTAssertEqual("\(error)", "the formula was compiled with a token limit of 300; the standard limit is 256")
        }
        // Loosened limits are checked before the count and cost.
        let full = ExpressionFrameBudget(maximumExpressions: 0)
        var empty = ExpressionFrameSet(budget: full)
        XCTAssertThrowsError(try empty.admit(loose)) { (error: Error) in
            XCTAssertTrue("\(error)".hasPrefix("the formula was compiled with"))
        }
        XCTAssertEqual(frameSet.count, 0)
        // Tighter limits are always admitted.
        XCTAssertNoThrow(try frameSet.admit(try CompiledExpression(source: "1+1", limits: ExpressionLimits(maximumTokens: 3))))
    }

    func testSnapshotEvaluatesInAdmissionOrder() throws {
        let sources = ["audio.onset", "1 + 2", "audio.band.2 * 4", "let a = time; a * a", "audio.bandMean + audio.bandMean"]
        var frameSet = ExpressionFrameSet()
        var compiled: [CompiledExpression] = []
        for source in sources {
            let expression = try CompiledExpression(source: source)
            compiled.append(expression)
            _ = try frameSet.admit(expression)
        }
        let snapshot = frameSet.snapshot
        XCTAssertEqual(snapshot.operationCost, compiled.reduce(0) { (sum: Int, e: CompiledExpression) -> Int in sum + e.operationCost })
        XCTAssertEqual(snapshot.handles, frameSet.handles)

        let inputs = ExpressionTestInputs()
        var results = [Double](repeating: -1, count: 7)
        let written = inputs.bands.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) -> Int in
            let frame = AudioFeatureFrame(bands: buffer, onset: inputs.onset, beatConfidence: inputs.beatConfidence)
            return results.withUnsafeMutableBufferPointer { (out: inout UnsafeMutableBufferPointer<Double>) -> Int in
                snapshot.evaluate(ExpressionInputs(frame: frame, timeSeconds: inputs.time), into: out)
            }
        }
        XCTAssertEqual(written, 5)
        // Bit-identical to evaluating each formula alone (the band mean is summed once per frame).
        XCTAssertEqual(Array(results[0..<5]).map { (v: Double) -> UInt64 in v.bitPattern },
                       compiled.map { (e: CompiledExpression) -> UInt64 in inputs.evaluate(e).bitPattern })
        XCTAssertEqual(Array(results[0..<5]), [0.75, 3, 4, 4, 0.9375])
        XCTAssertEqual(Array(results[5...]), [-1, -1], "nothing written past the formulas")

        // A short buffer evaluates only what fits.
        var two = [Double](repeating: 0, count: 2)
        let short = two.withUnsafeMutableBufferPointer { (out: inout UnsafeMutableBufferPointer<Double>) -> Int in
            snapshot.evaluate(.silent, into: out)
        }
        XCTAssertEqual(short, 2)
        XCTAssertEqual(two, [0, 3])

        // The snapshot is a value: later admissions and removals do not change it.
        _ = try frameSet.admit(try CompiledExpression(source: "9"))
        XCTAssertTrue(frameSet.remove(frameSet.handles[0]))
        XCTAssertEqual(snapshot.expressions.count, 5)
        XCTAssertEqual(frameSet.snapshot.expressions.count, 5)
    }

    func testEmptySnapshot() {
        let snapshot = ExpressionFrameSet().snapshot
        XCTAssertEqual(snapshot.operationCost, 0)
        var out = [Double](repeating: 7, count: 1)
        let written = out.withUnsafeMutableBufferPointer { (buffer: inout UnsafeMutableBufferPointer<Double>) -> Int in
            snapshot.evaluate(.silent, into: buffer)
        }
        XCTAssertEqual(written, 0)
        XCTAssertEqual(out, [7])
    }
}
