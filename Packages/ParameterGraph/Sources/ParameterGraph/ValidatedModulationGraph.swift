// ValidatedModulationGraph.swift — an accepted graph: its evaluation order and the incremental
// "would this connection close a loop?" check (MOD-014-R7, R8; research MOD-014-D4; contract G7,
// G8). Built at edit or load time (it allocates); later rows evaluate per frame in
// `evaluationOrder` without revalidating.

/// A modulation graph that passed validation.
public struct ValidatedModulationGraph: Sendable {
    public let graph: ModulationGraph
    public let registry: ParameterRegistry
    /// Every node once, each source before its targets, smallest stable ID first among ready nodes.
    public let evaluationOrder: [ModulationNode]

    private let generators: [String: ModulationGenerator]
    private let index: [ModulationNode: Int]
    private let offsets: [Int]
    private let sources: [Int]
    private let targets: [Int]
    private let edges: [ModulationEdge]

    /// Validates `graph` against `registry`; throws every issue when it is refused.
    public init(_ graph: ModulationGraph, registry: ParameterRegistry) throws(ModulationGraphError) {
        let result = ModulationGraphValidator(graph: graph, registry: registry).run()
        guard result.issues.isEmpty else { throw ModulationGraphError(issues: result.issues) }
        self.graph = graph
        self.registry = registry
        generators = result.generators
        index = result.index
        offsets = result.offsets
        sources = result.sources
        targets = result.targets
        edges = result.edges
        evaluationOrder = Self.topologicalOrder(nodeCount: result.nodes.count, offsets: result.offsets,
                                                targets: result.targets).map { (i: Int) -> ModulationNode in result.nodes[i] }
    }

    /// The loop that adding `edge` would close, starting at the edge's target and ending with the
    /// edge, or nil. A connection with a structural problem returns nil (full validation reports
    /// that problem and leaves the connection out of the loop search).
    public func wouldCreateCycle(adding edge: ModulationEdge) -> ModulationCycle? {
        guard ModulationGraphValidator.problem(of: edge, generators: generators, registry: registry) == nil else { return nil }
        let validator = ModulationGraphValidator(graph: graph, registry: registry)
        if edge.source == edge.target { return validator.makeCycle([edge], generators: generators) }
        guard let start = index[edge.target], let goal = index[edge.source] else { return nil }
        var stamp = [Int](repeating: -1, count: offsets.count - 1)
        var parentEdge = [Int](repeating: -1, count: offsets.count - 1)
        guard let path = ModulationGraphValidator.shortestPath(from: start, to: goal, offsets: offsets, sources: sources,
                                                               targets: targets, stamp: &stamp, parentEdge: &parentEdge,
                                                               stampValue: 0, allowed: { (_: Int) -> Bool in true })
        else { return nil }
        return validator.makeCycle(path.map { (k: Int) -> ModulationEdge in edges[k] } + [edge], generators: generators)
    }

    /// Kahn's algorithm with a binary min-heap on the node index (= stable-ID order).
    static func topologicalOrder(nodeCount n: Int, offsets: [Int], targets: [Int]) -> [Int] {
        var indegree = [Int](repeating: 0, count: n)
        for t in targets { indegree[t] += 1 }
        var heap = MinHeap()
        for v in 0..<n where indegree[v] == 0 { heap.push(v) }
        var order: [Int] = []
        order.reserveCapacity(n)
        while let v = heap.pop() {
            order.append(v)
            for k in offsets[v]..<offsets[v + 1] {
                let w = targets[k]
                indegree[w] -= 1
                if indegree[w] == 0 { heap.push(w) }
            }
        }
        return order
    }
}

/// A binary min-heap of node indices.
private struct MinHeap {
    private var items: [Int] = []

    mutating func push(_ value: Int) {
        items.append(value)
        var child = items.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard items[child] < items[parent] else { break }
            items.swapAt(child, parent)
            child = parent
        }
    }

    mutating func pop() -> Int? {
        guard let first = items.first else { return nil }
        let last = items.removeLast()
        if !items.isEmpty {
            items[0] = last
            var parent = 0
            while true {
                let left = 2 * parent + 1, right = left + 1
                var smallest = parent
                if left < items.count, items[left] < items[smallest] { smallest = left }
                if right < items.count, items[right] < items[smallest] { smallest = right }
                guard smallest != parent else { break }
                items.swapAt(parent, smallest)
                parent = smallest
            }
        }
        return first
    }
}
