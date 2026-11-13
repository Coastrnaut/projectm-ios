// SHD-002-T14 (US2; SHD-002-R6, R12; S2): deterministic plans, ordering, registers, time terms and
// the derived limits. CPU only; runs on Linux.
import Foundation
import GeneratorGraph
import XCTest

/// A small seeded generator (SplitMix64) so shuffles and random graphs are reproducible.
struct GraphTestRandom {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func int(_ n: Int) -> Int { Int(next() % UInt64(max(n, 1))) }
    mutating func shuffled<T>(_ a: [T]) -> [T] {
        var a = a
        if a.count < 2 { return a }
        for i in stride(from: a.count - 1, to: 0, by: -1) { a.swapAt(i, int(i + 1)) }
        return a
    }
}

final class GraphCompilerTests: XCTestCase {
    func testCompilingTwiceAndInAnyNodeOrderGivesIdenticalBytes() throws {
        var random = GraphTestRandom(seed: 42)
        for document in GeneratorGraphExamples.all {
            let bytes = try GeneratorGraphCompiler.compile(document).planBytes
            XCTAssertEqual(try GeneratorGraphCompiler.compile(document).planBytes, bytes, document.name)
            var reversed = document
            reversed.nodes.reverse()
            XCTAssertEqual(try GeneratorGraphCompiler.compile(reversed).planBytes, bytes, "\(document.name) reversed")
            for _ in 0..<5 {
                var shuffled = document
                shuffled.nodes = random.shuffled(document.nodes)
                XCTAssertEqual(try GeneratorGraphCompiler.compile(shuffled), try GeneratorGraphCompiler.compile(document))
                XCTAssertEqual(try GeneratorGraphCompiler.compile(shuffled).planBytes, bytes, "\(document.name) shuffled")
            }
        }
    }

    func testOrderIsByDependencyWithIDTieBreakAndUnreachableNodesAreOmitted() throws {
        let d = graphDoc([GraphNode("z", .output, inputs: ["color": "g"]), GraphNode("g", .gradient, inputs: ["t": "m"]),
                          GraphNode("m", .add, inputs: ["a": "b", "b": "a"]), GraphNode("b", .musicLevel), GraphNode("a", .musicLevel),
                          GraphNode("unused", .noise)])
        let c = try GeneratorGraphCompiler.compile(d)
        XCTAssertEqual(c.order, ["a", "b", "m", "g", "z"])
        XCTAssertEqual(c.instructions.map { $0.op }, [3, 3, 15, 21, 26])
        XCTAssertEqual(c.instructions.map { $0.dst }, [0, 1, 0, 0, 0], "lowest free register, reused after last use")
        XCTAssertEqual(c.registerCount, 2)
    }

    func testTimeAndCoordinatesNodesAreOperandsNotInstructions() throws {
        let c = try GeneratorGraphCompiler.compile(GeneratorGraphExamples.emberDrift)
        XCTAssertEqual(c.order, ["t", "flow", "n", "c", "out"])
        XCTAssertEqual(c.instructions.map { $0.op }, [6, 14, 21, 26])
        XCTAssertEqual(c.instructions[0].source(0), GraphInstruction.coordinatesSource, "unconnected point reads coordinates")
        XCTAssertEqual(c.instructions[1].source(0), 0, "noise reads the drift's register")
        XCTAssertEqual(c.instructions[2].flags & 1, 1, "connected scalar is clamped")
        XCTAssertEqual(c.instructions[2].a, SIMD4<Float>(0, 1, 0, 0), "…to the input's range")
        XCTAssertEqual(c.instructions[2].source(1), GraphInstruction.literalSource)
        XCTAssertEqual(c.instructions[2].b, SIMD4<Float>(0.05, 0, 0.02, 0))
        XCTAssertEqual(c.instructions[1].settings, SIMD4<Float>(3, 4, 0, 0))
        XCTAssertEqual(c.timeTerms, [.drift(x: 0.3, y: 0.1), .none, .none, .none])
    }

    func testLongChainReusesRegisters() throws {
        var nodes: [GraphNode] = [GraphNode("a00", .musicLevel)]
        for i in 1..<10 { nodes.append(GraphNode("a\(i < 10 ? "0" : "")\(i)", .add, inputs: ["a": "a0\(i - 1)"])) }
        let c = try GeneratorGraphCompiler.compile(minimalGraph(nodes, gradient: GraphNode("c", .gradient, inputs: ["t": "a09"])))
        XCTAssertEqual(c.instructions.count, 12)
        XCTAssertLessThanOrEqual(c.registerCount, 2)
    }

    func testDerivedLimitsOfTheExamples() throws {
        let pi = Double.pi, sqrt2 = 2.0.squareRoot()
        let ember = try GeneratorGraphCompiler.compile(GeneratorGraphExamples.emberDrift)
        let noise = 3 * 3 * (1 + 1.015 + 1.015 * 1.015 + 1.015 * 1.015 * 1.015) / 1.875
        XCTAssertEqual(ember.timeRateBound, 0.3 * noise, accuracy: 1e-9)
        XCTAssertEqual(ember.speedCap, pi / (0.3 * noise), accuracy: 1e-9)
        XCTAssertEqual(ember.musicRate, 1)
        XCTAssertEqual(ember.defaultSpeed, 0.2)

        let rings = try GeneratorGraphCompiler.compile(GeneratorGraphExamples.hueRings)
        XCTAssertEqual(rings.timeRateBound, pi * 0.5, accuracy: 1e-12)
        XCTAssertEqual(rings.speedCap, 1)
        XCTAssertEqual(rings.timeTerms.last(where: { $0 != .none }), .cycle(rate: -0.5, offset: 0))

        let orbs = try GeneratorGraphCompiler.compile(GeneratorGraphExamples.softOrbs)
        let spin = 2 * pi * 0.2 * sqrt2 * 2
        let circle = 1.5 / (2 * 0.25) * sqrt2
        XCTAssertEqual(orbs.timeRateBound, spin * circle, accuracy: 1e-9)
        XCTAssertEqual(orbs.speedCap, pi / (spin * circle), accuracy: 1e-9)
        XCTAssertEqual(orbs.musicRateBound, 0.3, accuracy: 1e-12)
        XCTAssertEqual(orbs.musicRate, 1)
        XCTAssertEqual(orbs.clampSpeed(1), orbs.speedCap)
        XCTAssertEqual(orbs.clampSpeed(-1), -orbs.speedCap)
        XCTAssertEqual(orbs.clampSpeed(.nan), 0)
    }

    func testStrobeAttemptIsSlowedToTheBound() throws {
        // oscillate (π per phase) → wave 2 (2π per unit): 2π² per phase → cap π / 2π² = 1 / 2π.
        let d = minimalGraph([GraphNode("t", .time), GraphNode("o", .oscillate, inputs: ["phase": "t"], values: ["rate": 1]),
                              GraphNode("w", .wave, inputs: ["x": "o"], values: ["frequency": 2])],
                             gradient: GraphNode("c", .gradient, inputs: ["t": "w"]))
        var fast = d
        fast.speed = 1
        let c = try GeneratorGraphCompiler.compile(fast)
        XCTAssertEqual(c.speedCap, 1 / (2 * Double.pi), accuracy: 1e-12)
        XCTAssertEqual(c.defaultSpeed, c.speedCap, "the document's speed 1 is limited")
    }

    func testPlanBytesLayout() throws {
        let c = try GeneratorGraphCompiler.compile(GeneratorGraphExamples.hueRings)
        let bytes = c.planBytes
        XCTAssertEqual(Array(bytes[0..<4]), Array("SHD2".utf8))
        XCTAssertEqual(bytes[4], 1)
        XCTAssertEqual(Int(bytes[8]), c.instructions.count)
        XCTAssertEqual(bytes.count, 32 + c.instructions.count * (GraphInstruction.byteCount + 28))
        XCTAssertEqual(c.instructionBytes.count, c.instructions.count * GraphInstruction.byteCount)
        XCTAssertNil(String(decoding: bytes, as: UTF8.self).range(of: "Hue Rings"), "the name is not part of the plan")
    }

    func testTimeTermsStayInRangeAfterLongSessions() {
        for phase in [0.0, 0.25, 1e3, 1e6, 123_456.789, -5e5] {
            let v = GraphTimeTerm.cycle(rate: 0.37, offset: 0.1).value(phase: phase)
            XCTAssertTrue(v.x >= 0 && v.x <= 1, "\(phase): \(v.x)")
            let d = GraphTimeTerm.drift(x: 1, y: -0.5).value(phase: phase)
            XCTAssertTrue(abs(d.x) <= 1024 && abs(d.y) <= 1024, "\(phase): \(d)")
        }
        XCTAssertEqual(GraphTimeTerm.cycle(rate: -0.5, offset: 0).value(phase: 1).x, 0.5)
        XCTAssertEqual(GraphTimeTerm.drift(x: 0.5, y: 0).value(phase: 3).x, 1.5)
    }
}
