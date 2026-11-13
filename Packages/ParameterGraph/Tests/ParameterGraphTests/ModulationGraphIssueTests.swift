// ModulationGraphIssueTests.swift — MOD-014-T09: every structural mistake is its own readable issue,
// in a stable order (MOD-014-R4, R5; contract G4, G5).
import ParameterGraph
import XCTest

final class ModulationGraphIssueTests: XCTestCase {
    typealias F = ModulationFixtures
    typealias Problem = ModulationGraphIssue.Problem

    private func problems(_ graph: ModulationGraph, file: StaticString = #filePath, line: UInt = #line) throws -> [Problem] {
        let issues = graph.validate(in: try F.registry())
        for issue in issues {
            if let edge = issue.edge {
                XCTAssertTrue(issue.message.contains(edge.description), "\(issue.message) names \(edge)", file: file, line: line)
            }
            if let id = issue.generatorID {
                XCTAssertTrue(issue.message.contains("\"\(id)\""), "\(issue.message) names \(id)", file: file, line: line)
            }
        }
        return issues.map(\.problem)
    }

    func testGeneratorProblems() throws {
        let cases: [(ModulationGenerator, Problem)] = [
            (ModulationGenerator(id: "Bad", displayName: "Bad"), .malformedGeneratorID),
            (ModulationGenerator(id: "lfo", displayName: "One segment"), .malformedGeneratorID),
            (ModulationGenerator(id: "e.one", displayName: "  "), .emptyGeneratorName),
            (ModulationGenerator(id: "visual.ring.gap", displayName: "Registered"), .conflictingGeneratorID),
            (ModulationGenerator(id: "visual.ring.old", displayName: "Retired"), .conflictingGeneratorID),
            (ModulationGenerator(id: "audio.custom", displayName: "Audio domain"), .conflictingGeneratorID),
            (ModulationGenerator(id: "l.one", displayName: "L", inputs: ["Rate"]), .malformedInput),
            (ModulationGenerator(id: "l.two", displayName: "L", inputs: ["rate", "rate"]), .duplicateInput),
        ]
        for (generator, expected) in cases {
            XCTAssertEqual(try problems(ModulationGraph(generators: [generator])), [expected], generator.id)
        }
        XCTAssertEqual(try problems(ModulationGraph(generators: [F.macro, F.macro])), [.duplicateGenerator])
    }

    func testConnectionProblems() throws {
        let macro = F.gen("macro.a"), lfo = F.gen("lfo.one"), gap = F.param(F.gap)
        let cases: [(ModulationEdge, Problem)] = [
            (ModulationEdge(source: .audio(.band(128)), target: gap), .unknownAudioFeature),
            (ModulationEdge(source: .audio(.band(-1)), target: gap), .unknownAudioFeature),
            (ModulationEdge(source: F.param("visual.ring.nope"), target: gap), .unknownParameter),
            (ModulationEdge(source: gap, target: F.param("visual.ring.nope")), .unknownParameter),
            (ModulationEdge(source: F.param(F.retired), target: gap), .retiredParameter),
            (ModulationEdge(source: gap, target: F.param(F.retired)), .retiredParameter),
            (ModulationEdge(source: F.gen("lfo.two"), target: gap), .unknownGenerator),
            (ModulationEdge(source: gap, target: F.gen("lfo.two")), .unknownGenerator),
            (ModulationEdge(source: gap, target: .audio(.onset)), .audioTarget),
            (ModulationEdge(source: macro, target: gap, input: "rate"), .unknownInput),
            (ModulationEdge(source: gap, target: lfo, input: "phase"), .unknownInput),
            (ModulationEdge(source: gap, target: lfo), .unknownInput),   // the LFO declares no `value` input
        ]
        for (edge, expected) in cases {
            XCTAssertEqual(try problems(ModulationGraph(generators: [F.macro, F.lfo], edges: [edge])), [expected], "\(edge)")
        }
        let edge = ModulationEdge(source: macro, target: gap)
        XCTAssertEqual(try problems(ModulationGraph(generators: [F.macro], edges: [edge, edge])), [.duplicateEdge])
        let message = try F.registry()   // readable sentences
        let issue = ModulationGraph(edges: [ModulationEdge(source: F.param(F.retired), target: gap)]).validate(in: message).first
        XCTAssertEqual(issue?.message, "connection visual.ring.old → visual.ring.gap: the source \"visual.ring.old\" is a retired parameter")
    }

    func testIssuesAppearInContractOrder() throws {
        let macro = F.gen("macro.a"), lfo = F.gen("lfo.one"), gap = F.param(F.gap)
        let graph = ModulationGraph(generators: [F.macro, F.lfo, ModulationGenerator(id: "Bad", displayName: "Bad"), F.macro], edges: [
            ModulationEdge(source: lfo, target: macro),
            ModulationEdge(source: F.param("visual.ring.nope"), target: gap),
            ModulationEdge(source: macro, target: gap),
            ModulationEdge(source: macro, target: gap),
            ModulationEdge(source: lfo, target: lfo, input: "rate"),
            ModulationEdge(source: gap, target: lfo, input: "rate"),
            ModulationEdge(source: gap, target: .audio(.onset)),
        ])
        XCTAssertEqual(try problems(graph),
                       [.malformedGeneratorID, .duplicateGenerator, .unknownParameter, .duplicateEdge, .audioTarget, .selfLoop, .cycle])
        XCTAssertEqual(graph.validate(in: try F.registry()).last?.cycle?.path, F.acceptancePath)
    }

    func testConnectionWithAProblemIsNotPartOfALoop() throws {
        let graph = ModulationGraph(generators: [F.macro, F.lfo], edges: [
            ModulationEdge(source: F.gen("macro.a"), target: F.param(F.gap)),
            ModulationEdge(source: F.param(F.gap), target: F.gen("lfo.one"), input: "phase"),
            ModulationEdge(source: F.gen("lfo.one"), target: F.gen("macro.a")),
        ])
        XCTAssertEqual(try problems(graph), [.unknownInput], "the loop needs the bad connection, so only that is reported")
    }
}
