// SHD-002-T16 (US2; SHD-002-R6, R9; S2, S5): random type-correct graphs from a fixed seed always
// compile (or are refused only by the rate or live-value limits), compile to the same bytes in any
// node order, and draw finite, valid pixels. The CPU part runs on Linux; the drawing needs Metal.
import GeneratorGraph
import XCTest

enum RandomGraphs {
    static let kinds: [GraphNodeKind] = GraphNodeKind.allCases.filter { $0 != .output }

    /// A random, valid graph of 2…24 nodes (ignoring the rate and live-value limits).
    static func make(_ random: inout GraphTestRandom) -> GeneratorGraphDocument {
        var nodes: [GraphNode] = []
        var types: [String: GraphPortType] = [:]
        let count = 1 + random.int(23)
        func pick(_ type: GraphPortType, _ random: inout GraphTestRandom) -> String? {
            let candidates = nodes.filter { types[$0.id] == type }.map { $0.id }
            return candidates.isEmpty ? nil : candidates[random.int(candidates.count)]
        }
        for i in 0..<count {
            let kind = kinds[random.int(kinds.count)]
            let spec = kind.spec
            var node = GraphNode((i < 10 ? "n0" : "n") + String(i), kind)
            for input in spec.inputs {
                if input.type == .phase {
                    if input.required || random.unit() < 0.5 {
                        var t = pick(.phase, &random)
                        if t == nil {
                            let id = "t\(i)"
                            nodes.append(GraphNode(id, .time))
                            types[id] = .phase
                            t = id
                        }
                        node.inputs[input.name] = t
                    }
                    continue
                }
                if random.unit() < 0.6, let source = pick(input.type, &random) {
                    node.inputs[input.name] = source
                } else if input.type != .point, random.unit() < 0.5 {
                    let values = (0..<input.type.componentCount).map { (_: Int) -> Double in
                        input.lower + (input.upper - input.lower) * random.unit()
                    }
                    node.values[input.name] = values.count == 1 ? .number(values[0]) : .numbers(values)
                }
            }
            for s in spec.settings {
                var v = s.lower + (s.upper - s.lower) * random.unit()
                if s.whole { v = v.rounded() }
                node.values[s.name] = .number(v)
            }
            switch kind {
            case .clamp:
                let a = GraphTestRandom.value(node.values["min"]), b = GraphTestRandom.value(node.values["max"])
                node.values["min"] = .number(min(a, b)); node.values["max"] = .number(max(a, b))
            case .smoothstep:
                let a = GraphTestRandom.value(node.values["edge0"])
                node.values["edge1"] = .number(a < 0 ? a + 0.5 : a - 0.5)
            case .drift:
                let x = GraphTestRandom.value(node.values["velocityX"]), y = GraphTestRandom.value(node.values["velocityY"])
                let length = (x * x + y * y).squareRoot()
                if length > 1 { node.values["velocityX"] = .number(x / length * 0.99); node.values["velocityY"] = .number(y / length * 0.99) }
            default:
                break
            }
            nodes.append(node)
            types[node.id] = spec.output
        }
        if let color = pick(.color, &random) {
            nodes.append(GraphNode("out", .output, inputs: ["color": color]))
        } else {
            var g = GraphNode("g", .gradient)
            if let s = pick(.scalar, &random) { g.inputs["t"] = s }
            nodes.append(g)
            nodes.append(GraphNode("out", .output, inputs: ["color": "g"]))
        }
        return GeneratorGraphDocument(name: "random", speed: 2 * random.unit() - 1, nodes: nodes)
    }
}

extension GraphTestRandom {
    static func value(_ v: GraphValue?) -> Double {
        if case let .number(x)? = v { return x }
        return 0
    }
}

final class GraphPropertyTests: XCTestCase {
    static let seed: UInt64 = 0x5D02

    func testRandomGraphsCompileDeterministically() throws {
        var random = GraphTestRandom(seed: Self.seed)
        var compiled = 0
        for n in 0..<200 {
            let document = RandomGraphs.make(&random)
            let issues = GeneratorGraphCompiler.validate(document)
            if !issues.isEmpty {
                for issue in issues {
                    switch issue {
                    case .tooFast, .tooManyLiveValues: break
                    default: XCTFail("graph \(n): \(issue.message)")
                    }
                }
                continue
            }
            compiled += 1
            let plan = try GeneratorGraphCompiler.compile(document)
            XCTAssertEqual(try GeneratorGraphCompiler.compile(document).planBytes, plan.planBytes, "graph \(n)")
            var shuffled = document
            shuffled.nodes = random.shuffled(document.nodes)
            XCTAssertEqual(try GeneratorGraphCompiler.compile(shuffled).planBytes, plan.planBytes, "graph \(n) shuffled")
            XCTAssertLessThanOrEqual(plan.instructions.count, GeneratorGraphLimits.nodes)
            XCTAssertLessThanOrEqual(plan.speedCap, 1)
            XCTAssertGreaterThanOrEqual(plan.speedCap, 1 / GeneratorGraphLimits.maxSlowdown)
        }
        XCTAssertGreaterThanOrEqual(compiled, 100, "most random graphs compile (\(compiled) of 200)")
    }

    #if canImport(Metal) && !COMPOSITOR_NO_METAL
    func testRandomGraphsDrawValidPixels() throws {
        let rig = try GraphGPURig()
        var random = GraphTestRandom(seed: Self.seed)
        var drawn = 0
        while drawn < 20 {
            let document = RandomGraphs.make(&random)
            guard let plan = try? GeneratorGraphCompiler.compile(document) else { continue }
            let layer = GeneratorGraphLayer(compiled: plan, pipeline: try rig.pipeline())
            layer.setSpeed(1)
            let driver = try GraphGPURig.Driver(rig: rig, layer: layer, width: 32, height: 32)
            for _ in 0..<3 { try driver.step(bands: [0.5, 1, 0]) }
            XCTAssertEqual(invalidGraphPixelCount(try driver.read()), 0, "random graph \(drawn)")
            drawn += 1
        }
    }
    #endif
}
