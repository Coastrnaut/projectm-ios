// ModulationGraphCycleTests.swift — MOD-014-T03, T05: a cycle fixture fails validation with a
// readable path (roadmap acceptance; MOD-014-R2, R3, R5, R6; contract G3, G5, G6).
// Deterministic: fixed fixtures, no clock.
import ParameterGraph
import XCTest

/// Shared fixtures for the MOD-014 tests.
enum ModulationFixtures {
    static let gap: ParameterID = "visual.ring.gap"
    static let width: ParameterID = "visual.ring.width"
    static let mode: ParameterID = "visual.ring.mode"
    static let retired: ParameterID = "visual.ring.old"
    static let group = ParameterGroup(id: "visual.ring", displayName: "Ring")

    static func registry() throws -> ParameterRegistry {
        try ParameterRegistry(descriptors: [
            ParameterDescriptor(id: gap, displayName: "Ring gap", group: group, unit: .normalized,
                                kind: .continuous(minimum: 0, maximum: 1, defaultValue: 0.2), modulation: .continuousDefault),
            ParameterDescriptor(id: width, displayName: "Ring width", group: group, unit: .normalized,
                                kind: .continuous(minimum: 0, maximum: 1, defaultValue: 0.5), modulation: .continuousDefault),
            ParameterDescriptor(id: mode, displayName: "Ring mode", group: group, unit: .count,
                                kind: .integer(minimum: 0, maximum: 4, defaultValue: 0, step: 1), modulation: .continuousDefault),
        ], retiredIDs: [retired])
    }

    static let macro = ModulationGenerator(id: "macro.a", displayName: "Macro A", inputs: ["value"])
    static let lfo = ModulationGenerator(id: "lfo.one", displayName: "LFO One", inputs: ["rate", "amplitude"])

    static func gen(_ id: String) -> ModulationNode { .generator(id) }
    static func param(_ id: ParameterID) -> ModulationNode { .parameter(id) }

    /// macro.a → visual.ring.gap → lfo.one (rate) → macro.a
    static let closingEdge = ModulationEdge(source: gen("lfo.one"), target: gen("macro.a"))
    static let acceptance = ModulationGraph(generators: [macro, lfo], edges: [
        ModulationEdge(source: gen("macro.a"), target: param(gap)),
        ModulationEdge(source: param(gap), target: gen("lfo.one"), input: "rate"),
        closingEdge,
    ])
    static let acceptancePath = "lfo.one.rate → macro.a → visual.ring.gap → lfo.one.rate"
    static let acceptanceDisplayPath = "LFO One (rate) → Macro A → Ring gap → LFO One (rate)"
    static let incrementalPath = "macro.a → visual.ring.gap → lfo.one.rate → macro.a"

    /// Generators with one `value` input each.
    static func generators(_ ids: [String]) -> [ModulationGenerator] {
        ids.map { (id: String) -> ModulationGenerator in ModulationGenerator(id: id, displayName: id, inputs: ["value"]) }
    }

    static func edge(_ source: String, _ target: String) -> ModulationEdge {
        ModulationEdge(source: gen(source), target: gen(target))
    }
}

final class ModulationGraphCycleTests: XCTestCase {
    typealias F = ModulationFixtures

    // (a) The roadmap acceptance.
    func testAcceptanceCycleFixtureFailsWithReadablePath() throws {
        let issues = F.acceptance.validate(in: try F.registry())
        XCTAssertEqual(issues.count, 1, "\(issues)")
        let issue = try XCTUnwrap(issues.first)
        XCTAssertEqual(issue.problem, .cycle)
        XCTAssertEqual(issue.cycle?.path, F.acceptancePath)
        XCTAssertEqual(issue.cycle?.displayPath, F.acceptanceDisplayPath)
        XCTAssertEqual(issue.cycle?.edges.count, 3)
        XCTAssertTrue(issue.message.contains(F.acceptancePath), issue.message)
        XCTAssertThrowsError(try ValidatedModulationGraph(F.acceptance, registry: try F.registry())) { error in
            let graphError = error as? ModulationGraphError
            XCTAssertEqual(graphError?.issues, issues)
            XCTAssertTrue(String(describing: error).contains(F.acceptancePath))
        }
    }

    // (b) A self-loop.
    func testSelfLoopIsReported() throws {
        let graph = ModulationGraph(generators: [F.lfo], edges: [
            ModulationEdge(source: F.gen("lfo.one"), target: F.gen("lfo.one"), input: "rate"),
        ])
        let issues = graph.validate(in: try F.registry())
        XCTAssertEqual(issues.map(\.problem), [.selfLoop])
        XCTAssertEqual(issues.first?.cycle?.path, "lfo.one.rate → lfo.one.rate")
        XCTAssertEqual(issues.first?.cycle?.displayPath, "LFO One (rate) → LFO One (rate)")
        XCTAssertTrue(issues.first?.message.contains("lfo.one") ?? false)
    }

    // (c) Two disjoint loops, in stable order whatever the connection order.
    func testTwoDisjointCyclesAreReportedInStableOrder() throws {
        let registry = try F.registry()
        let edges = [F.edge("q.one", "q.two"), F.edge("q.two", "q.one"), F.edge("p.two", "p.one"),
                     F.edge("p.one", "p.two"), F.edge("p.one", "q.one")]
        let graph = ModulationGraph(generators: F.generators(["q.one", "q.two", "p.one", "p.two"]), edges: edges)
        let issues = graph.validate(in: registry)
        XCTAssertEqual(issues.map(\.problem), [.cycle, .cycle])
        XCTAssertEqual(issues.map { $0.cycle?.path ?? "" }, ["p.one → p.two → p.one", "q.one → q.two → q.one"])
        XCTAssertEqual(graph.validate(in: registry), issues, "the same on a second run")
        let reversed = ModulationGraph(generators: graph.generators.reversed(), edges: edges.reversed())
        XCTAssertEqual(reversed.validate(in: registry).map { $0.cycle?.path ?? "" }, issues.map { $0.cycle?.path ?? "" })
    }

    // (d) A loop behind a diamond: one issue, the shortest loop, ties by ID.
    func testCycleBehindDiamondIsReportedOnceWithShortestPath() throws {
        let graph = ModulationGraph(generators: F.generators(["a.n", "b.n", "c.n", "d.n"]), edges: [
            F.edge("a.n", "c.n"), F.edge("a.n", "b.n"), F.edge("c.n", "d.n"), F.edge("b.n", "d.n"), F.edge("d.n", "a.n"),
        ])
        let issues = graph.validate(in: try F.registry())
        XCTAssertEqual(issues.map(\.problem), [.cycle])
        XCTAssertEqual(issues.first?.cycle?.path, "a.n → b.n → d.n → a.n")
    }

    // (e) A self-loop inside a larger loop: both are reported, self-loops first.
    func testSelfLoopInsideLargerLoopReportsBoth() throws {
        var graph = F.acceptance
        graph.edges.append(ModulationEdge(source: F.gen("lfo.one"), target: F.gen("lfo.one"), input: "amplitude"))
        let issues = graph.validate(in: try F.registry())
        XCTAssertEqual(issues.map(\.problem), [.selfLoop, .cycle])
        XCTAssertEqual(issues[0].cycle?.path, "lfo.one.amplitude → lfo.one.amplitude")
        XCTAssertEqual(issues[1].cycle?.path, F.acceptancePath, "the self-connection is not used by the larger loop")
    }

    // (f) Without its closing connection the fixture is accepted.
    func testAcceptanceFixtureWithoutClosingEdgeIsAccepted() throws {
        var graph = F.acceptance
        graph.edges.removeLast()
        XCTAssertEqual(graph.validate(in: try F.registry()), [])
        XCTAssertEqual(ModulationGraph().validate(in: try F.registry()), [], "the empty graph is accepted")
    }

    // MOD-014-T05: a long chain needs no deep recursion; limits are enforced first.
    static func chainID(_ i: Int) -> String {
        let digits = String(i)
        return "c.n" + String(repeating: "0", count: max(0, 4 - digits.count)) + digits
    }

    func testThousandNodeChainValidatesInChainOrder() throws {
        // c.n0999 → c.n0998 → … → c.n0000: the evaluation order is the reverse of the ID order.
        let ids = (0..<1_000).map { (i: Int) -> String in Self.chainID(i) }
        let edges = (1..<1_000).map { (i: Int) -> ModulationEdge in F.edge(Self.chainID(i), Self.chainID(i - 1)) }
        let graph = ModulationGraph(generators: F.generators(ids), edges: edges)
        let validated = try ValidatedModulationGraph(graph, registry: try F.registry())
        XCTAssertEqual(validated.evaluationOrder, ids.reversed().map { (id: String) -> ModulationNode in .generator(id) })

        // Closing the chain makes one loop through all 1,000 nodes.
        var closed = graph
        closed.edges.append(F.edge(Self.chainID(0), Self.chainID(999)))
        let issues = closed.validate(in: try F.registry())
        XCTAssertEqual(issues.map(\.problem), [.cycle])
        XCTAssertEqual(issues.first?.cycle?.edges.count, 1_000)
        XCTAssertTrue(issues.first?.cycle?.path.hasPrefix("c.n0000 → c.n0999 → c.n0998") ?? false)
    }

    func testLimitsAreRejectedBeforeAnyOtherCheck() throws {
        let registry = try F.registry()
        let tooManyEdges = ModulationGraph(edges: Array(repeating: F.edge("x.unknown", "x.unknown"), count: 4_097))
        let edgeIssues = tooManyEdges.validate(in: registry)
        XCTAssertEqual(edgeIssues.map(\.problem), [.tooManyEdges])
        XCTAssertTrue(edgeIssues.first?.message.contains("4096") ?? false, edgeIssues.first?.message ?? "")

        let ids = (0..<1_025).map { (i: Int) -> String in Self.chainID(i) }
        XCTAssertEqual(ModulationGraph(generators: F.generators(ids)).validate(in: registry).map(\.problem), [.tooManyNodes])
        XCTAssertEqual(ModulationGraph(generators: F.generators(Array(ids.prefix(1_024)))).validate(in: registry), [],
                       "exactly 1,024 nodes are accepted")
        // Nodes named only by connections count too.
        let named = (0..<1_025).map { (i: Int) -> ModulationEdge in
            ModulationEdge(source: .audio(.band(i % 128)), target: F.gen(Self.chainID(i)))
        }
        XCTAssertEqual(ModulationGraph(edges: named).validate(in: registry).map(\.problem), [.tooManyNodes])
    }
}
