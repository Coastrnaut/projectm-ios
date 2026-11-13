// ModulationGraphOrderTests.swift — MOD-014-T05, T07, T11: evaluation order, the incremental cycle
// check and the audio binding integration (MOD-014-R7 to R9; contract G7 to G9).
// Deterministic: fixed fixtures and a fixed-seed generator, no clock.
import ParameterGraph
import XCTest

/// SplitMix64: a small, fixed-seed generator so the property test is the same on every host.
struct SplitMix64 {
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

final class ModulationGraphOrderTests: XCTestCase {
    typealias F = ModulationFixtures

    // MARK: Evaluation order (T05)

    static let orderGraph = ModulationGraph(generators: [F.macro, F.lfo], edges: [
        ModulationEdge(source: F.gen("lfo.one"), target: F.param(F.width)),
        ModulationEdge(source: F.gen("macro.a"), target: F.gen("lfo.one"), input: "rate"),
        ModulationEdge(source: .audio(.onset), target: F.param(F.gap)),
        ModulationEdge(source: F.gen("macro.a"), target: F.param(F.gap)),
    ])

    func testEvaluationOrderRespectsEdgesAndBreaksTiesByID() throws {
        let validated = try ValidatedModulationGraph(Self.orderGraph, registry: try F.registry())
        let order = validated.evaluationOrder
        XCTAssertEqual(order, [.audio(.onset), F.gen("macro.a"), F.gen("lfo.one"), F.param(F.gap), F.param(F.width)])
        let position = Dictionary(uniqueKeysWithValues: order.enumerated().map { (pair: (offset: Int, element: ModulationNode)) -> (ModulationNode, Int) in
            (pair.element, pair.offset)
        })
        for edge in Self.orderGraph.edges {
            XCTAssertLessThan(position[edge.source] ?? .max, position[edge.target] ?? .min, "\(edge)")
        }
        var shuffled = Self.orderGraph
        shuffled.edges.reverse()
        shuffled.generators.reverse()
        XCTAssertEqual(try ValidatedModulationGraph(shuffled, registry: try F.registry()).evaluationOrder, order)
        XCTAssertEqual(try ValidatedModulationGraph(ModulationGraph(), registry: try F.registry()).evaluationOrder, [])
    }

    func testUnconnectedGeneratorsAppearInIDOrder() throws {
        let graph = ModulationGraph(generators: F.generators(["z.one", "a.one", "m.one"]))
        XCTAssertEqual(try ValidatedModulationGraph(graph, registry: try F.registry()).evaluationOrder,
                       [F.gen("a.one"), F.gen("m.one"), F.gen("z.one")])
    }

    // MARK: Incremental check (T07)

    func testIncrementalCheckReturnsTheLoopFromTheNewEdge() throws {
        var open = F.acceptance
        open.edges.removeLast()
        let validated = try ValidatedModulationGraph(open, registry: try F.registry())
        let cycle = try XCTUnwrap(validated.wouldCreateCycle(adding: F.closingEdge))
        XCTAssertEqual(cycle.path, F.incrementalPath)
        XCTAssertEqual(cycle.displayPath, "Macro A → Ring gap → LFO One (rate) → Macro A")
        XCTAssertEqual(cycle.edges.last, F.closingEdge)

        let selfEdge = ModulationEdge(source: F.gen("lfo.one"), target: F.gen("lfo.one"), input: "amplitude")
        XCTAssertEqual(validated.wouldCreateCycle(adding: selfEdge)?.path, "lfo.one.amplitude → lfo.one.amplitude")
        XCTAssertNil(validated.wouldCreateCycle(adding: ModulationEdge(source: F.param(F.gap), target: F.param(F.width))),
                     "a node not yet in the graph cannot close a loop")
        XCTAssertNil(validated.wouldCreateCycle(adding: ModulationEdge(source: F.param("visual.ring.nope"), target: F.param("visual.ring.nope"))),
                     "a connection with a structural problem returns nil (full validation reports the problem)")
        XCTAssertNil(validated.wouldCreateCycle(adding: open.edges[0]), "a repeat of an existing connection closes no loop")
    }

    func testIncrementalCheckMatchesFullValidation() throws {
        let registry = try F.registry()
        var random = SplitMix64(state: 0x4D4F_442D_3031_34)   // "MOD-014"
        var loops = 0
        for _ in 0..<200 {
            let count = 8 + random.below(5)
            let ids = (0..<count).map { (i: Int) -> String in "g.n" + String(i) }
            // A random rank makes every edge go "downhill", so the base graph is acyclic.
            var rank = Array(0..<count)
            for i in stride(from: count - 1, to: 0, by: -1) { rank.swapAt(i, random.below(i + 1)) }
            var edges: [ModulationEdge] = []
            for _ in 0..<(count + random.below(count)) {
                let a = random.below(count), b = random.below(count)
                guard rank[a] < rank[b] else { continue }
                let edge = F.edge(ids[a], ids[b])
                if !edges.contains(edge) { edges.append(edge) }
            }
            let graph = ModulationGraph(generators: F.generators(ids), edges: edges)
            let validated = try ValidatedModulationGraph(graph, registry: registry)
            let candidate = F.edge(ids[random.below(count)], ids[random.below(count)])

            let incremental = validated.wouldCreateCycle(adding: candidate)
            let full = ModulationGraph(generators: graph.generators, edges: edges + [candidate]).validate(in: registry)
            let fullHasLoop = full.contains { (issue: ModulationGraphIssue) -> Bool in issue.problem == .cycle || issue.problem == .selfLoop }
            XCTAssertEqual(incremental != nil, fullHasLoop, "\(edges) + \(candidate)")
            if let incremental {
                loops += 1
                XCTAssertEqual(incremental.edges.last, candidate)
                XCTAssertEqual(incremental.edges.first?.source, candidate.target)
                for (a, b) in zip(incremental.edges, incremental.edges.dropFirst()) { XCTAssertEqual(a.target, b.source) }
            }
        }
        XCTAssertGreaterThan(loops, 10, "the fixture exercises loops")
        XCTAssertLessThan(loops, 190, "and loop-free additions")
    }

    // MARK: Audio bindings (T11, contract G9)

    func testAudioBindingsExpressAsGraphAndModulateIdentically() throws {
        let registry = try F.registry()
        let modulator = AudioFeatureModulator(registry: registry)
        let gapBinding = AudioFeatureBinding(source: .band(0), target: F.gap, outputStart: 0.1, outputEnd: 0.9)
        let widthBinding = AudioFeatureBinding(source: .bandMean, target: F.width, outputStart: -0.2, outputEnd: 0.2, mixMode: .add)
        let modeBinding = AudioFeatureBinding(source: .onset, target: F.mode, inputMaximum: 0.5, outputStart: 0, outputEnd: 4)
        for binding in [gapBinding, widthBinding, modeBinding] { try modulator.bind(binding) }
        try modulator.bind(gapBinding)   // rebinding keeps the binding's place

        let graph = modulator.modulationGraph
        XCTAssertEqual(graph.generators, [])
        XCTAssertEqual(graph.edges, [
            ModulationEdge(source: .audio(.band(0)), target: F.param(F.gap)),
            ModulationEdge(source: .audio(.bandMean), target: F.param(F.width)),
            ModulationEdge(source: .audio(.onset), target: F.param(F.mode)),
        ])
        XCTAssertEqual(graph.validate(in: registry), [])
        XCTAssertEqual(try ValidatedModulationGraph(graph, registry: registry).evaluationOrder.count, 6)

        // Values equal the MOD-002/MOD-003 formula bit for bit (no envelope: the signal is the position).
        let frames: [(bands: [Float], onset: Float)] = [([0, 0.2], 0), ([0.37, 0.9], 0.13), ([1, 1], 0.5), ([0.61, 0.05], 0.31)]
        for (i, frame) in frames.enumerated() {
            frame.bands.withUnsafeBufferPointer { (bands: UnsafeBufferPointer<Float>) -> Void in
                modulator.advance(frame: AudioFeatureFrame(bands: bands, onset: frame.onset), timeNanoseconds: UInt64(i) * 16_666_667)
            }
            let mean = (Double(frame.bands[0]) + Double(frame.bands[1])) / 2
            let gap = gapBinding.mapping.interpolate(gapBinding.mapping.position(of: Double(frame.bands[0])))
            XCTAssertEqual(modulator.value(for: F.gap, manual: 0.5), gap, "frame \(i)")
            let width = min(max(0.5 + widthBinding.mapping.interpolate(widthBinding.mapping.position(of: mean)), 0), 1)
            XCTAssertEqual(modulator.value(for: F.width, manual: 0.5), width, "frame \(i)")
            let mode = modeBinding.mapping.interpolate(modeBinding.mapping.position(of: Double(frame.onset)))
            XCTAssertEqual(modulator.value(for: F.mode, manual: 1), Double(Int(mode.rounded(.toNearestOrAwayFromZero))), "frame \(i)")
        }
    }

    func testFeedbackCycleBindingErrorIsReadable() {
        let error = AudioFeatureBindingError.feedbackCycle(F.gap, path: F.acceptancePath)
        XCTAssertTrue(error.description.contains("visual.ring.gap"), error.description)
        XCTAssertTrue(error.description.contains(F.acceptancePath), error.description)
    }
}
