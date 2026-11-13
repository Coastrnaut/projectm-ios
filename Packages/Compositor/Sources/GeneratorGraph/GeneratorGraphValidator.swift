// GeneratorGraphValidator.swift — checks a document before anything is compiled (SHD-002-R4, R5, R7;
// research SHD-002-D3; contracts/generator-graph.md "Messages").
//
// Order of issues: document (format, version, name, speed), size limits (more than 64 nodes or 128
// connections stops validation at once, so oversized input costs no further work), node IDs, then
// per node in document order: connections (by input name, sorted), literals (by name, sorted),
// required inputs (in the kind's order), setting rules; then the output count, the cycles (ordered
// by their start ID) and, for an acyclic graph, the longest chain. Connections run from a source to
// the node that reads it, so a cycle "a → b → a" means a feeds b and b feeds a.
//
// Cycle detection reuses the approach of MOD-014's validator (ParameterGraph
// ModulationGraphValidator.swift): an iterative Tarjan pass with an explicit stack (no recursion on
// hostile input), stable ordering, readable paths. Plain Swift; builds on Linux.

/// IDs compare by their UTF-8 bytes (locale-free, stable).
@inline(__always)
func graphIDPrecedes(_ a: String, _ b: String) -> Bool { a.utf8.lexicographicallyPrecedes(b.utf8) }

/// The structure validation found: unique, well-formed nodes of known kinds and their connections.
struct GraphStructure {
    /// Node by ID (first occurrence of each valid ID).
    var nodes: [String: GraphNode] = [:]
    var kinds: [String: GraphNodeKind] = [:]
    /// Valid IDs, sorted by `graphIDPrecedes`.
    var sortedIDs: [String] = []
    /// source → readers (sorted, unique), over connections whose source exists.
    var successors: [String: [String]] = [:]
    /// reader → sources (sorted, unique).
    var predecessors: [String: [String]] = [:]
    var outputID: String?
}

enum GeneratorGraphValidator {
    static func validate(_ document: GeneratorGraphDocument) -> (issues: [GeneratorGraphIssue], structure: GraphStructure) {
        var issues: [GeneratorGraphIssue] = []
        var structure = GraphStructure()

        if document.format != GeneratorGraphDocument.formatName { issues.append(.unsupportedFormat(document.format)) }
        if document.version != GeneratorGraphDocument.currentVersion { issues.append(.unsupportedVersion(document.version)) }
        let nameLength = document.name.count
        if nameLength > GeneratorGraphLimits.nameLength { issues.append(.nameTooLong(count: nameLength)) }
        if !document.speed.isFinite || document.speed < -1 || document.speed > 1 { issues.append(.speedOutOfRange(document.speed)) }

        let connectionCount = document.nodes.reduce(0) { (n: Int, node: GraphNode) -> Int in n + node.inputs.count }
        var oversized = false
        if document.nodes.count > GeneratorGraphLimits.nodes {
            issues.append(.tooManyNodes(count: document.nodes.count))
            oversized = true
        }
        if connectionCount > GeneratorGraphLimits.connections {
            issues.append(.tooManyConnections(count: connectionCount))
            oversized = true
        }
        if oversized { return (issues, structure) }

        // IDs.
        var seen: Set<String> = []
        var reportedDuplicate: Set<String> = []
        for node in document.nodes {
            if !isValidID(node.id) {
                issues.append(.invalidNodeID(node.id))
                continue
            }
            if seen.contains(node.id) {
                if !reportedDuplicate.contains(node.id) {
                    issues.append(.duplicateNodeID(node.id))
                    reportedDuplicate.insert(node.id)
                }
                continue
            }
            seen.insert(node.id)
            structure.nodes[node.id] = node
            if let kind = GraphNodeKind(rawValue: node.kind) { structure.kinds[node.id] = kind }
        }

        // Nodes.
        var outputs: [String] = []
        for node in document.nodes where isValidID(node.id) {
            guard structure.nodes[node.id] == node else { continue }   // a duplicate
            guard let kind = GraphNodeKind(rawValue: node.kind) else {
                issues.append(.unknownKind(node: node.id, kind: node.kind))
                continue
            }
            if kind == .output { outputs.append(node.id) }
            issues += nodeIssues(node, kind: kind, structure: structure)
        }
        if outputs.isEmpty { issues.append(.noOutput) }
        if outputs.count > 1 { issues.append(.multipleOutputs(outputs)) }
        structure.outputID = outputs.count == 1 ? outputs[0] : nil

        // Connections between existing nodes.
        structure.sortedIDs = structure.nodes.keys.sorted(by: graphIDPrecedes)
        var successors: [String: Set<String>] = [:]
        var predecessors: [String: Set<String>] = [:]
        for id in structure.sortedIDs {
            guard let node = structure.nodes[id] else { continue }
            for (_, source) in node.inputs where structure.nodes[source] != nil {
                successors[source, default: []].insert(id)
                predecessors[id, default: []].insert(source)
            }
        }
        for (k, v) in successors { structure.successors[k] = v.sorted(by: graphIDPrecedes) }
        for (k, v) in predecessors { structure.predecessors[k] = v.sorted(by: graphIDPrecedes) }

        let cycles = findCycles(structure)
        issues += cycles.map { (path: [String]) -> GeneratorGraphIssue in .cycle(path) }
        if cycles.isEmpty {
            let depth = longestChain(structure)
            if depth > GeneratorGraphLimits.depth { issues.append(.tooDeep(nodes: depth)) }
        }
        return (issues, structure)
    }

    static func isValidID(_ id: String) -> Bool {
        let bytes = Array(id.utf8)
        guard (1...GeneratorGraphLimits.idLength).contains(bytes.count) else { return false }
        func letter(_ b: UInt8) -> Bool { (b >= 65 && b <= 90) || (b >= 97 && b <= 122) }
        guard letter(bytes[0]) else { return false }
        for b in bytes where !(letter(b) || (b >= 48 && b <= 57) || b == 45 || b == 95) { return false }
        return true
    }

    private static func nodeIssues(_ node: GraphNode, kind: GraphNodeKind, structure: GraphStructure) -> [GeneratorGraphIssue] {
        var issues: [GeneratorGraphIssue] = []
        let spec = kind.spec
        for name in node.inputs.keys.sorted(by: graphIDPrecedes) {
            guard let source = node.inputs[name] else { continue }
            guard let input = spec.input(named: name) else {
                issues.append(spec.setting(named: name) != nil
                              ? .settingConnected(node: node.id, name: name)
                              : .unknownName(node: node.id, kind: kind.rawValue, name: name))
                continue
            }
            if node.values[name] != nil { issues.append(.connectedAndSet(node: node.id, input: name)) }
            guard structure.nodes[source] != nil else {
                issues.append(.missingSource(node: node.id, input: name, source: source))
                continue
            }
            guard let sourceKind = structure.kinds[source] else { continue }   // reported as unknown kind
            guard let produced = sourceKind.spec.output else {
                issues.append(.sourceIsOutput(node: node.id, input: name, source: source))
                continue
            }
            if produced != input.type {
                issues.append(.typeMismatch(node: node.id, input: name, expected: input.type, source: source, actual: produced))
            }
        }
        for name in node.values.keys.sorted(by: graphIDPrecedes) {
            guard let value = node.values[name] else { continue }
            if let input = spec.input(named: name) {
                if input.type == .phase {
                    issues.append(.phaseLiteral(node: node.id, input: name))
                    continue
                }
                if node.inputs[name] != nil { continue }   // reported as connected and set
                issues += literalIssues(node.id, name, value.components, count: input.type.componentCount,
                                        expected: input.type, lower: input.lower, upper: input.upper, whole: false)
            } else if let setting = spec.setting(named: name) {
                issues += literalIssues(node.id, name, value.components, count: 1, expected: .scalar,
                                        lower: setting.lower, upper: setting.upper, whole: setting.whole)
            } else {
                issues.append(.unknownName(node: node.id, kind: kind.rawValue, name: name))
            }
        }
        for input in spec.inputs where input.required && node.inputs[input.name] == nil {
            issues.append(.missingInput(node: node.id, input: input.name))
        }
        let s = { (name: String) -> Double in GraphSettings.value(name, of: node, kind: kind) }
        switch kind {
        case .clamp where s("min") > s("max"):
            issues.append(.invalidSetting(node: node.id, rule: "\"min\" must not exceed \"max\""))
        case .smoothstep where abs(s("edge1") - s("edge0")) < 0.01:
            issues.append(.invalidSetting(node: node.id, rule: "\"edge0\" and \"edge1\" must differ by at least 0.01"))
        case .drift where (s("velocityX") * s("velocityX") + s("velocityY") * s("velocityY")).squareRoot() > 1 + 1e-9:
            issues.append(.invalidSetting(node: node.id, rule: "the drift velocity must be at most 1 long"))
        default:
            break
        }
        return issues
    }

    private static func literalIssues(_ node: String, _ name: String, _ components: [Double], count: Int,
                                      expected: GraphPortType, lower: Double, upper: Double, whole: Bool) -> [GeneratorGraphIssue] {
        guard components.count == count else { return [.wrongValueShape(node: node, name: name, expected: expected)] }
        for v in components where !v.isFinite { return [.notFinite(node: node, name: name)] }
        for v in components where v < lower || v > upper {
            return [.outOfRange(node: node, name: name, value: v, lower: lower, upper: upper)]
        }
        if whole, let v = components.first, v != v.rounded() { return [.notWhole(node: node, name: name)] }
        return []
    }

    // MARK: Cycles

    /// Every cycle as a path that starts and ends at its smallest node ID, ordered by that ID.
    static func findCycles(_ s: GraphStructure) -> [[String]] {
        let ids = s.sortedIDs
        var index: [String: Int] = [:]
        for (i, id) in ids.enumerated() { index[id] = i }
        let n = ids.count
        let succ: [[Int]] = ids.map { (id: String) -> [Int] in (s.successors[id] ?? []).compactMap { index[$0] } }

        // Iterative Tarjan.
        var order = [Int](repeating: -1, count: n)
        var low = [Int](repeating: 0, count: n)
        var onStack = [Bool](repeating: false, count: n)
        var stack: [Int] = []
        var component = [Int](repeating: -1, count: n)
        var components = 0
        var counter = 0
        for root in 0..<n where order[root] < 0 {
            var work: [(node: Int, next: Int)] = [(root, 0)]
            order[root] = counter; low[root] = counter; counter += 1
            stack.append(root); onStack[root] = true
            while let top = work.last {
                let v = top.node
                if top.next < succ[v].count {
                    work[work.count - 1].next += 1
                    let w = succ[v][top.next]
                    if order[w] < 0 {
                        order[w] = counter; low[w] = counter; counter += 1
                        stack.append(w); onStack[w] = true
                        work.append((w, 0))
                    } else if onStack[w] {
                        low[v] = min(low[v], order[w])
                    }
                } else {
                    work.removeLast()
                    if let parent = work.last { low[parent.node] = min(low[parent.node], low[v]) }
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

        var members = [[Int]](repeating: [], count: components)
        for v in 0..<n { members[component[v]].append(v) }
        var cycles: [[String]] = []
        for group in members {
            guard let start = group.min() else { continue }   // indices follow sorted IDs
            let selfLoop = succ[start].contains(start)
            guard group.count > 1 || selfLoop else { continue }
            cycles.append(cyclePath(from: start, in: Set(group), succ: succ).map { ids[$0] })
        }
        cycles.sort { (a: [String], b: [String]) -> Bool in graphIDPrecedes(a[0], b[0]) }
        return cycles
    }

    /// The shortest way from `start` back to itself inside one component, smallest IDs first.
    private static func cyclePath(from start: Int, in group: Set<Int>, succ: [[Int]]) -> [Int] {
        var parent: [Int: Int] = [:]
        var queue: [Int] = [start]
        var head = 0
        while head < queue.count {
            let u = queue[head]
            head += 1
            for v in succ[u] where group.contains(v) {
                if v == start {
                    var path: [Int] = [u]
                    var x = u
                    while x != start, let p = parent[x] {
                        path.append(p)
                        x = p
                    }
                    return path.reversed() + [start]
                }
                if parent[v] == nil && v != start {
                    parent[v] = u
                    queue.append(v)
                }
            }
        }
        return [start, start]
    }

    /// The most nodes on any chain (the graph must be acyclic).
    static func longestChain(_ s: GraphStructure) -> Int {
        var depth: [String: Int] = [:]
        var best = 0
        for id in topologicalOrder(s, ids: s.sortedIDs) {
            let d = 1 + (s.predecessors[id] ?? []).reduce(0) { (m: Int, p: String) -> Int in max(m, depth[p] ?? 0) }
            depth[id] = d
            best = max(best, d)
        }
        return best
    }

    /// Kahn's algorithm over `ids` (a subset closed under predecessors), ready nodes by smallest ID.
    static func topologicalOrder(_ s: GraphStructure, ids: [String]) -> [String] {
        let members = Set(ids)
        var remaining: [String: Int] = [:]
        for id in ids { remaining[id] = (s.predecessors[id] ?? []).filter { members.contains($0) }.count }
        var ready: [String] = ids.filter { remaining[$0] == 0 }.sorted(by: graphIDPrecedes)
        var order: [String] = []
        while !ready.isEmpty {
            let id = ready.removeFirst()
            order.append(id)
            for next in s.successors[id] ?? [] where members.contains(next) {
                remaining[next, default: 0] -= 1
                if remaining[next] == 0 {
                    let at = ready.firstIndex { graphIDPrecedes(next, $0) } ?? ready.count
                    ready.insert(next, at: at)
                }
            }
        }
        return order
    }
}

/// Setting values with defaults.
enum GraphSettings {
    static func value(_ name: String, of node: GraphNode, kind: GraphNodeKind) -> Double {
        if let v = node.values[name]?.components, v.count == 1, kind.spec.setting(named: name) != nil { return v[0] }
        return kind.spec.setting(named: name)?.defaultValue ?? 0
    }
}
