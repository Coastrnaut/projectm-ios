// SHD-002-T18 (US3; SHD-002-R4, R5, R7, R12; S3, S4): every issue kind with its exact message, cycle
// paths and the limits. CPU only; runs on Linux.
import GeneratorGraph
import XCTest

func graphDoc(_ nodes: [GraphNode], speed: Double = 0.2, name: String = "Test") -> GeneratorGraphDocument {
    GeneratorGraphDocument(name: name, speed: speed, nodes: nodes)
}

/// gradient "c" → output "out", plus `extra` nodes.
func minimalGraph(_ extra: [GraphNode] = [], gradient: GraphNode = GraphNode("c", .gradient)) -> GeneratorGraphDocument {
    graphDoc([gradient, GraphNode("out", .output, inputs: ["color": "c"])] + extra)
}

func messages(_ document: GeneratorGraphDocument) -> [String] {
    GeneratorGraphCompiler.validate(document).map { (i: GeneratorGraphIssue) -> String in i.message }
}

final class GraphValidationTests: XCTestCase {
    func testValidFixturesHaveNoIssues() {
        XCTAssertEqual(messages(minimalGraph()), [])
        for d in GeneratorGraphExamples.all { XCTAssertEqual(messages(d), [], d.name) }
    }

    func testDocumentIssues() {
        var d = minimalGraph()
        d.format = "x"
        d.version = 2
        d.name = String(repeating: "n", count: 65)
        d.speed = 2
        XCTAssertEqual(messages(d), [
            "Unsupported format \"x\"; expected \"projectm-ios.generator-graph\".",
            "Unsupported version 2; this app reads version 1.",
            "Graph name has 65 characters; the limit is 64.",
            "Graph speed 2 is outside -1 to 1.",
        ])
        d = minimalGraph()
        d.speed = -0.5
        XCTAssertEqual(messages(d), [])
        d.speed = .nan
        XCTAssertEqual(messages(d), ["Graph speed nan is outside -1 to 1."])
    }

    func testNodeIssueTable() {
        let cases: [(GeneratorGraphDocument, [String])] = [
            (minimalGraph([GraphNode("1x", .musicLevel)]),
             ["Node ID \"1x\" is invalid: use 1-32 letters, digits, \"-\" or \"_\", starting with a letter."]),
            (minimalGraph([GraphNode("bad id", .musicLevel)]),
             ["Node ID \"bad id\" is invalid: use 1-32 letters, digits, \"-\" or \"_\", starting with a letter."]),
            (minimalGraph([GraphNode("c", .musicLevel), GraphNode("c", .musicLevel)]),
             ["Node ID \"c\" is used more than once."]),
            (minimalGraph([GraphNode("b", "blur")]), ["Node \"b\": unknown kind \"blur\"."]),
            (minimalGraph(gradient: GraphNode("c", .gradient, values: ["foo": 1])),
             ["Node \"c\": kind \"gradient\" has no input or setting \"foo\"."]),
            (minimalGraph([GraphNode("x", .musicLevel), GraphNode("n", .noise, inputs: ["scale": "x"])]),
             ["Node \"n\": \"scale\" is a setting and cannot be connected."]),
            (minimalGraph([GraphNode("s", .musicLevel)], gradient: GraphNode("c", .gradient, inputs: ["t": "s"], values: ["t": 0.5])),
             ["Node \"c\": input \"t\" is both connected and given a value."]),
            (minimalGraph(gradient: GraphNode("c", .gradient, inputs: ["t": "zz"])),
             ["Node \"c\": input \"t\" is connected to missing node \"zz\"."]),
            (minimalGraph([GraphNode("g", .gradient, inputs: ["t": "out"])]),
             ["Node \"g\": input \"t\" is connected to output node \"out\", which gives no value."]),
            (minimalGraph([GraphNode("uv", .coordinates)], gradient: GraphNode("c", .gradient, inputs: ["t": "uv"])),
             ["Node \"c\": input \"t\" expects scalar but node \"uv\" gives point."]),
            (minimalGraph([GraphNode("p", .palette, values: ["shift": 1])]),
             ["Node \"p\": input \"shift\" takes time and cannot be given a value."]),
            (minimalGraph([GraphNode("o", .oscillate)]), ["Node \"o\": required input \"phase\" is not connected."]),
            (minimalGraph(gradient: GraphNode("c", .gradient, values: ["colorA": 0.5])),
             ["Node \"c\": \"colorA\" needs a color (3 numbers)."]),
            (minimalGraph([GraphNode("n", .noise, values: ["scale": [1, 2]])]), ["Node \"n\": \"scale\" needs a number."]),
            (minimalGraph(gradient: GraphNode("c", .gradient, values: ["t": .number(.nan)])),
             ["Node \"c\": \"t\" is not a finite number."]),
            (minimalGraph([GraphNode("n", .noise, values: ["scale": 40])]), ["Node \"n\": \"scale\" is 40, outside 0.5 to 16."]),
            (minimalGraph(gradient: GraphNode("c", .gradient, values: ["colorB": [1, 1.5, 0]])),
             ["Node \"c\": \"colorB\" is 1.5, outside 0 to 1."]),
            (minimalGraph([GraphNode("n", .noise, values: ["octaves": 2.5])]), ["Node \"n\": \"octaves\" must be a whole number."]),
            (minimalGraph([GraphNode("k", .clamp, values: ["min": 2, "max": 1])]), ["Node \"k\": \"min\" must not exceed \"max\"."]),
            (minimalGraph([GraphNode("e", .smoothstep, values: ["edge0": 0.5, "edge1": 0.505])]),
             ["Node \"e\": \"edge0\" and \"edge1\" must differ by at least 0.01."]),
            (minimalGraph([GraphNode("t", .time), GraphNode("d", .drift, inputs: ["phase": "t"], values: ["velocityX": 1, "velocityY": 1])]),
             ["Node \"d\": the drift velocity must be at most 1 long."]),
            (graphDoc([GraphNode("c", .gradient)]), ["Graph has no output node."]),
            (graphDoc([GraphNode("c", .gradient), GraphNode("o1", .output, inputs: ["color": "c"]), GraphNode("o2", .output, inputs: ["color": "c"])]),
             ["Graph has 2 output nodes (\"o1\", \"o2\"); exactly one is allowed."]),
        ]
        for (document, expected) in cases {
            XCTAssertEqual(messages(document), expected)
        }
    }

    func testSeveralIssuesInOneNodeAreAllReportedInOrder() {
        let d = minimalGraph([GraphNode("n", .noise, inputs: ["zeta": "c", "point": "nowhere"], values: ["scale": 99, "alpha": 1])])
        XCTAssertEqual(messages(d), [
            "Node \"n\": input \"point\" is connected to missing node \"nowhere\".",
            "Node \"n\": kind \"noise\" has no input or setting \"zeta\".",
            "Node \"n\": kind \"noise\" has no input or setting \"alpha\".",
            "Node \"n\": \"scale\" is 99, outside 0.5 to 16.",
        ])
    }

    // MARK: Cycles (acceptance: "rejects cycles")

    private func cycleNodes() -> [GraphNode] {
        [GraphNode("a", .add, inputs: ["a": "c"]), GraphNode("b", .add, inputs: ["a": "a"]), GraphNode("c", .add, inputs: ["a": "b"])]
    }

    func testThreeNodeCycleIsReportedAsAPath() {
        let nodes = cycleNodes() + [GraphNode("g", .gradient, inputs: ["t": "a"]), GraphNode("out", .output, inputs: ["color": "g"])]
        XCTAssertEqual(messages(graphDoc(nodes)), ["Graph has a cycle: a → b → c → a."])
        XCTAssertEqual(messages(graphDoc(nodes.reversed())), ["Graph has a cycle: a → b → c → a."], "any node order")
        XCTAssertEqual(GeneratorGraphCompiler.validate(graphDoc(nodes)), [.cycle(["a", "b", "c", "a"])])
    }

    func testSelfLoopAndTwoCyclesInStableOrder() {
        XCTAssertEqual(messages(minimalGraph([GraphNode("a", .add, inputs: ["a": "a"])])), ["Graph has a cycle: a → a."])
        let two = minimalGraph([GraphNode("y", .add, inputs: ["a": "x"]), GraphNode("x", .add, inputs: ["a": "y"]),
                                GraphNode("q", .add, inputs: ["a": "p"]), GraphNode("p", .add, inputs: ["a": "q"])])
        XCTAssertEqual(messages(two), ["Graph has a cycle: p → q → p.", "Graph has a cycle: x → y → x."])
    }

    func testCycleThatDoesNotReachTheOutputIsStillRejected() {
        XCTAssertEqual(messages(minimalGraph(cycleNodes().map { (n: GraphNode) -> GraphNode in
            var m = n
            m.id = "k" + n.id
            m.inputs = n.inputs.mapValues { "k" + $0 }
            return m
        })), ["Graph has a cycle: ka → kb → kc → ka."])
    }

    func testCyclePathFollowsTheShortestWayBack() {
        // a → b → a and a → e → f → a: the reported path is the shorter one.
        let nodes = [GraphNode("a", .add, inputs: ["a": "b", "b": "f"]), GraphNode("b", .add, inputs: ["a": "a"]),
                     GraphNode("e", .add, inputs: ["a": "a"]), GraphNode("f", .add, inputs: ["a": "e"])]
        XCTAssertEqual(messages(minimalGraph(nodes)), ["Graph has a cycle: a → b → a."])
    }

    // MARK: Limits

    func testNodeAndConnectionLimits() {
        let many = (0..<64).map { GraphNode("m\($0)", .musicLevel) }
        XCTAssertEqual(messages(minimalGraph(many)), ["Graph has 66 nodes; the limit is 64."])
        var nodes: [GraphNode] = [GraphNode("s", .musicLevel)]
        for i in 0..<43 { nodes.append(GraphNode("h\(i)", .hsv, inputs: ["hue": "s", "saturation": "s", "value": "s"])) }
        XCTAssertEqual(messages(minimalGraph(nodes)), ["Graph has 130 connections; the limit is 128."])
        nodes.removeLast()
        XCTAssertEqual(messages(minimalGraph(nodes)), [], "127 connections pass")
    }

    func testDepthLimit() {
        func chain(_ n: Int) -> GeneratorGraphDocument {
            var nodes: [GraphNode] = [GraphNode("a0", .add)]
            for i in 1..<n { nodes.append(GraphNode("a\(i)", .add, inputs: ["a": "a\(i - 1)"])) }
            return minimalGraph(nodes, gradient: GraphNode("c", .gradient, inputs: ["t": "a\(n - 1)"]))
        }
        XCTAssertEqual(messages(chain(31)), ["Graph's longest chain has 33 nodes; the limit is 32."])
        XCTAssertEqual(messages(chain(30)), [])
    }

    func testLiveValueLimit() {
        func wide(_ n: Int) -> GeneratorGraphDocument {
            var nodes: [GraphNode] = []
            for i in 0..<n { nodes.append(GraphNode("n\(i < 10 ? "0" : "")\(i)", .noise, values: ["scale": .number(1 + Double(i) * 0.5)])) }
            nodes.append(GraphNode("s01", .add, inputs: ["a": "n00", "b": "n01"]))
            for i in 2..<n { nodes.append(GraphNode("s\(i < 10 ? "0" : "")\(i)", .add, inputs: ["a": "s\(i - 1 < 10 ? "0" : "")\(i - 1)", "b": "n\(i < 10 ? "0" : "")\(i)"])) }
            return minimalGraph(nodes, gradient: GraphNode("c", .gradient, inputs: ["t": "s\(n - 1 < 10 ? "0" : "")\(n - 1)"]))
        }
        XCTAssertEqual(messages(wide(17)), ["Graph needs 17 values at once; the limit is 16."])
        XCTAssertEqual(messages(wide(16)), [])
    }

    // MARK: Rate limit (SHD-002-R12)

    func testStrobeAttemptsAreRefused() {
        let time = minimalGraph([GraphNode("t", .time), GraphNode("o", .oscillate, inputs: ["phase": "t"], values: ["rate": 1]),
                                 GraphNode("m", .multiply, inputs: ["a": "o"], values: ["b": 8]),
                                 GraphNode("w", .wave, inputs: ["x": "m"], values: ["frequency": 4])],
                                gradient: GraphNode("c", .gradient, inputs: ["t": "w"]))
        XCTAssertEqual(messages(time), ["Graph changes too fast with time; it would have to run below 1/64 of normal speed."])
        let music = minimalGraph([GraphNode("l", .musicLevel), GraphNode("m", .multiply, inputs: ["a": "l"], values: ["b": 8]),
                                  GraphNode("w", .wave, inputs: ["x": "m"], values: ["frequency": 16])],
                                 gradient: GraphNode("c", .gradient, inputs: ["t": "w"]))
        XCTAssertEqual(messages(music), ["Graph changes too fast with music; it would have to run below 1/64 of normal speed."])
        let polar = minimalGraph([GraphNode("t", .time), GraphNode("d", .drift, inputs: ["phase": "t"]),
                                  GraphNode("p", .polar, inputs: ["point": "d"]), GraphNode("x", .component, inputs: ["point": "p"])],
                                 gradient: GraphNode("c", .gradient, inputs: ["t": "x"]))
        XCTAssertEqual(messages(polar), ["Graph changes too fast with time; it would have to run below 1/64 of normal speed."],
                       "polar of a moving point jumps at its seam")
    }
}
