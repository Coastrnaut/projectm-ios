// ModulationGraphValidator.swift — structural checks and loop detection (MOD-014-R2 to R6; research
// MOD-014-D2 to D5; contract G3 to G6).
//
// 1. Limits: over 4,096 connections or 1,024 nodes → one size issue, nothing else.
// 2. Generators in declaration order, then each connection's first problem in connection order;
//    connections with a problem, and exact repeats, are left out of the loop search.
// 3. Nodes are indexed in stable-ID order; adjacency is sorted by (source, target, input).
// 4. Self-connections are reported in connection order; the others feed an iterative Tarjan pass
//    (no recursion). Each strongly connected group of two or more nodes gets one issue with the
//    shortest loop through its smallest node (breadth-first search, neighbours in ID order).

struct ModulationGraphValidator {
    let graph: ModulationGraph
    let registry: ParameterRegistry

    /// Everything a `ValidatedModulationGraph` needs besides the issues.
    struct Result {
        var issues: [ModulationGraphIssue] = []
        /// Generators that may be named by connections (well-formed, first declaration, no conflict).
        var generators: [String: ModulationGenerator] = [:]
        /// Nodes in stable-ID order.
        var nodes: [ModulationNode] = []
        var index: [ModulationNode: Int] = [:]
        /// Adjacency (compressed rows): connections leaving node `v` are `offsets[v] ..< offsets[v + 1]`.
        var offsets: [Int] = [0]
        var targets: [Int] = []
        var sources: [Int] = []
        var edges: [ModulationEdge] = []
    }

    func run() -> Result {
        var result = Result()
        let g = graph

        // 1. Limits (contract G3).
        if g.edges.count > ModulationGraph.maximumEdges {
            result.issues = [Self.issue(.tooManyEdges, message: "the graph has \(g.edges.count) connections; "
                + "at most \(ModulationGraph.maximumEdges) are allowed")]
            return result
        }
        var allNodes: Set<ModulationNode> = []
        if g.generators.count <= ModulationGraph.maximumNodes {
            for generator in g.generators { allNodes.insert(.generator(generator.id)) }
            for edge in g.edges {
                allNodes.insert(edge.source)
                allNodes.insert(edge.target)
            }
        }
        let nodeCount = max(allNodes.count, g.generators.count)
        if nodeCount > ModulationGraph.maximumNodes {
            result.issues = [Self.issue(.tooManyNodes, message: "the graph has \(nodeCount) or more nodes; "
                + "at most \(ModulationGraph.maximumNodes) are allowed")]
            return result
        }

        // 2a. Generators, in declaration order.
        var declared: Set<String> = []
        for generator in g.generators {
            let id = generator.id
            func add(_ problem: ModulationGraphIssue.Problem, _ text: String) {
                result.issues.append(ModulationGraphIssue(problem: problem, edge: nil, generatorID: id, cycle: nil,
                                                          message: "generator \"\(id)\": " + text))
            }
            if let syntax = ParameterID(id).syntaxProblem {
                add(.malformedGeneratorID, "malformed ID: \(syntax)")
                continue
            }
            if !declared.insert(id).inserted {
                add(.duplicateGenerator, "declared more than once")
                continue
            }
            let asParameter = ParameterID(id)
            if registry.contains(asParameter) || registry.retiredIDs.contains(asParameter) || asParameter.domain == "audio" {
                add(.conflictingGeneratorID, registry.contains(asParameter) ? "the ID is a registered parameter"
                    : registry.retiredIDs.contains(asParameter) ? "the ID is a retired parameter"
                    : "the audio domain is reserved for audio features")
                continue
            }
            if generator.displayName.allSatisfy(\.isWhitespace) {
                add(.emptyGeneratorName, "the display name is empty")
            }
            var inputs: Set<String> = []
            for input in generator.inputs {
                if let syntax = ParameterSyntax.segmentProblem(Substring(input)) {
                    add(.malformedInput, "input \"\(input)\": \(syntax)")
                } else if !inputs.insert(input).inserted {
                    add(.duplicateInput, "input \"\(input)\" is declared more than once")
                }
            }
            result.generators[id] = generator
        }

        // 2b. Connections, in connection order: first problem, then exact repeats.
        var seen: Set<ModulationEdge> = []
        var valid: [ModulationEdge] = []
        var selfLoops: [ModulationEdge] = []
        for edge in g.edges {
            if let (problem, text) = Self.problem(of: edge, generators: result.generators, registry: registry) {
                result.issues.append(ModulationGraphIssue(problem: problem, edge: edge, generatorID: nil, cycle: nil,
                                                          message: "connection \(edge): " + text))
                continue
            }
            if !seen.insert(edge).inserted {
                result.issues.append(ModulationGraphIssue(problem: .duplicateEdge, edge: edge, generatorID: nil, cycle: nil,
                                                          message: "connection \(edge): appears more than once"))
                continue
            }
            if edge.source == edge.target { selfLoops.append(edge) } else { valid.append(edge) }
        }

        // 3. Nodes in stable-ID order and sorted adjacency.
        var nodeSet: Set<ModulationNode> = []
        for id in result.generators.keys { nodeSet.insert(.generator(id)) }
        for edge in valid + selfLoops {
            nodeSet.insert(edge.source)
            nodeSet.insert(edge.target)
        }
        result.nodes = nodeSet.sorted()
        for (i, node) in result.nodes.enumerated() { result.index[node] = i }
        let index = result.index
        let rows: [(source: Int, target: Int, edge: ModulationEdge)] = valid
            .map { (edge: ModulationEdge) -> (source: Int, target: Int, edge: ModulationEdge) in
                (index[edge.source] ?? 0, index[edge.target] ?? 0, edge)
            }
            .sorted { (a: (source: Int, target: Int, edge: ModulationEdge), b: (source: Int, target: Int, edge: ModulationEdge)) -> Bool in
                if a.source != b.source { return a.source < b.source }
                if a.target != b.target { return a.target < b.target }
                return a.edge.input < b.edge.input
            }
        let n = result.nodes.count
        var offsets = [Int](repeating: 0, count: n + 1)
        for row in rows { offsets[row.source + 1] += 1 }
        for v in 0..<n { offsets[v + 1] += offsets[v] }
        result.offsets = offsets
        result.sources = rows.map { (row: (source: Int, target: Int, edge: ModulationEdge)) -> Int in row.source }
        result.targets = rows.map { (row: (source: Int, target: Int, edge: ModulationEdge)) -> Int in row.target }
        result.edges = rows.map { (row: (source: Int, target: Int, edge: ModulationEdge)) -> ModulationEdge in row.edge }

        // 4a. Self-loops, in connection order.
        for edge in selfLoops {
            let cycle = makeCycle([edge], generators: result.generators)
            result.issues.append(ModulationGraphIssue(problem: .selfLoop, edge: edge, generatorID: nil, cycle: cycle,
                                                      message: "\"\(edge.source.id)\" drives its own input: \(cycle.path)"))
        }

        // 4b. One shortest loop per strongly connected group, by the group's smallest node.
        let component = Self.stronglyConnectedComponents(nodeCount: n, offsets: offsets, targets: result.targets)
        var size = [Int](repeating: 0, count: n)
        for v in 0..<n { size[component[v]] += 1 }
        var reported = [Bool](repeating: false, count: n)
        var stamp = [Int](repeating: -1, count: n)
        var parentEdge = [Int](repeating: -1, count: n)
        for start in 0..<n {   // ascending index = ascending stable ID
            let c = component[start]
            guard size[c] >= 2, !reported[c] else { continue }
            reported[c] = true
            guard let loop = Self.shortestPath(from: start, to: start, offsets: offsets, sources: result.sources,
                                               targets: result.targets, stamp: &stamp, parentEdge: &parentEdge,
                                               stampValue: start, allowed: { (w: Int) -> Bool in component[w] == c })
            else { continue }   // unreachable: every node of a group lies on a loop through any other
            let cycle = makeCycle(loop.map { (k: Int) -> ModulationEdge in result.edges[k] }, generators: result.generators)
            result.issues.append(ModulationGraphIssue(problem: .cycle, edge: nil, generatorID: nil, cycle: cycle,
                                                      message: "feedback loop (\(size[c]) nodes in the loop group): \(cycle.path)"))
        }
        return result
    }

    // MARK: Connection checks (contract G4)

    /// The first problem of one connection, or nil when it is well formed.
    static func problem(of edge: ModulationEdge, generators: [String: ModulationGenerator],
                        registry: ParameterRegistry) -> (ModulationGraphIssue.Problem, String)? {
        if let problem = endpointProblem(edge.source, generators: generators, registry: registry, role: "source") {
            return problem
        }
        if case let .audio(source) = edge.target {
            return (.audioTarget, "the audio feature \"\(source.id)\" is a source only and has no inputs")
        }
        if let problem = endpointProblem(edge.target, generators: generators, registry: registry, role: "target") {
            return problem
        }
        switch edge.target {
        case let .parameter(id) where edge.input != ModulationEdge.valueInput:
            return (.unknownInput, "parameter \"\(id)\" has only the input \"\(ModulationEdge.valueInput)\", not \"\(edge.input)\"")
        case let .generator(id):
            if let generator = generators[id], !generator.inputs.contains(edge.input) {
                return (.unknownInput, "generator \"\(id)\" declares no input \"\(edge.input)\"")
            }
        default:
            break
        }
        return nil
    }

    private static func endpointProblem(_ node: ModulationNode, generators: [String: ModulationGenerator],
                                        registry: ParameterRegistry, role: String) -> (ModulationGraphIssue.Problem, String)? {
        switch node {
        case let .audio(source):
            if case let .band(index) = source, !(0...AudioFeatureSource.maximumBandIndex).contains(index) {
                return (.unknownAudioFeature, "the \(role) band \(index) is outside 0…\(AudioFeatureSource.maximumBandIndex)")
            }
            return nil
        case let .parameter(id):
            if registry.contains(id) { return nil }
            if registry.retiredIDs.contains(id) { return (.retiredParameter, "the \(role) \"\(id)\" is a retired parameter") }
            return (.unknownParameter, "the \(role) \"\(id)\" is not a registered parameter")
        case let .generator(id):
            return generators[id] == nil ? (.unknownGenerator, "the \(role) \"\(id)\" is not a declared generator") : nil
        }
    }

    // MARK: Paths

    /// A loop from its connections in order; the path starts where the last connection enters.
    func makeCycle(_ edges: [ModulationEdge], generators: [String: ModulationGenerator]) -> ModulationCycle {
        guard let last = edges.last else { return ModulationCycle(edges: [], path: "", displayPath: "") }
        let steps = [last] + edges
        let path = steps.map { (edge: ModulationEdge) -> String in edge.targetText }.joined(separator: " → ")
        let display = steps.map { (edge: ModulationEdge) -> String in
            displayText(edge.target, input: edge.input, generators: generators)
        }.joined(separator: " → ")
        return ModulationCycle(edges: edges, path: path, displayPath: display)
    }

    private func displayText(_ node: ModulationNode, input: String, generators: [String: ModulationGenerator]) -> String {
        let name: String
        switch node {
        case let .audio(source): name = source.id
        case let .parameter(id): name = registry.descriptor(for: id)?.displayName ?? id.rawValue
        case let .generator(id):
            let declared = generators[id]?.displayName ?? ""
            name = declared.allSatisfy(\.isWhitespace) ? id : declared
        }
        return input == ModulationEdge.valueInput ? name : name + " (" + input + ")"
    }

    static func issue(_ problem: ModulationGraphIssue.Problem, message: String) -> ModulationGraphIssue {
        ModulationGraphIssue(problem: problem, edge: nil, generatorID: nil, cycle: nil, message: message)
    }

    // MARK: Graph algorithms (iterative; research MOD-014-D3)

    /// Tarjan's strongly connected components with an explicit stack; returns each node's component.
    static func stronglyConnectedComponents(nodeCount n: Int, offsets: [Int], targets: [Int]) -> [Int] {
        var order = [Int](repeating: -1, count: n)
        var low = [Int](repeating: 0, count: n)
        var onStack = [Bool](repeating: false, count: n)
        var component = [Int](repeating: -1, count: n)
        var stack: [Int] = []
        var frames: [(node: Int, next: Int)] = []
        var counter = 0
        var components = 0
        for root in 0..<n where order[root] < 0 {
            order[root] = counter; low[root] = counter; counter += 1
            stack.append(root); onStack[root] = true
            frames.append((root, offsets[root]))
            while let top = frames.last {
                let v = top.node
                if top.next < offsets[v + 1] {
                    frames[frames.count - 1].next += 1
                    let w = targets[top.next]
                    if order[w] < 0 {
                        order[w] = counter; low[w] = counter; counter += 1
                        stack.append(w); onStack[w] = true
                        frames.append((w, offsets[w]))
                    } else if onStack[w] {
                        low[v] = min(low[v], order[w])
                    }
                } else {
                    frames.removeLast()
                    if let parent = frames.last { low[parent.node] = min(low[parent.node], low[v]) }
                    if low[v] == order[v] {
                        while let w = stack.popLast() {
                            onStack[w] = false
                            component[w] = components
                            if w == v { break }
                        }
                        components += 1
                    }
                }
            }
        }
        return component
    }

    /// The shortest path (connection positions) from `start` to `goal` through allowed nodes,
    /// neighbours in adjacency order; with `start == goal` the shortest loop. `stamp` and
    /// `parentEdge` are scratch arrays reused across calls (`stampValue` marks this call's visits).
    static func shortestPath(from start: Int, to goal: Int, offsets: [Int], sources: [Int], targets: [Int],
                             stamp: inout [Int], parentEdge: inout [Int], stampValue: Int,
                             allowed: (Int) -> Bool) -> [Int]? {
        var queue: [Int] = [start]
        var head = 0
        stamp[start] = stampValue
        parentEdge[start] = -1
        while head < queue.count {
            let v = queue[head]
            head += 1
            for k in offsets[v]..<offsets[v + 1] {
                let w = targets[k]
                guard allowed(w) else { continue }
                if w == goal {
                    var path = [k]
                    var u = v
                    while u != start {
                        let e = parentEdge[u]
                        path.append(e)
                        u = sources[e]
                    }
                    return path.reversed()
                }
                if stamp[w] != stampValue {
                    stamp[w] = stampValue
                    parentEdge[w] = k
                    queue.append(w)
                }
            }
        }
        return nil
    }
}
