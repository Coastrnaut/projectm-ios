// GeneratorGraphCompiler.swift — validates a document and compiles it into a plan for the fixed
// interpreter (SHD-002-R4-R7, R12; research SHD-002-D2, D3, D5; contracts/generator-graph.md "API").
//
// Steps: validation (GeneratorGraphValidator); the nodes that feed the output, ordered by Kahn's
// algorithm with ties broken by node ID (so node order in the document never matters); rate bounds
// per node and the speed and music limits; registers (the lowest free one, freed after a value's
// last use; at most 16); one instruction per node except `time` (its value reaches consumers as
// per-frame time terms) and `coordinates` (operands read the picture coordinates directly).
// Nothing here produces code: an instruction is an opcode from the closed kind set plus numbers.
// Plain Swift; builds on Linux.

public enum GeneratorGraphCompiler {
    /// Every problem of `document`; empty when it compiles.
    public static func validate(_ document: GeneratorGraphDocument) -> [GeneratorGraphIssue] {
        do {
            _ = try compile(document)
            return []
        } catch {
            return error.issues
        }
    }

    public static func compile(_ document: GeneratorGraphDocument) throws(GeneratorGraphValidationError) -> CompiledGeneratorGraph {
        let (issues, structure) = GeneratorGraphValidator.validate(document)
        guard issues.isEmpty, let outputID = structure.outputID else {
            throw GeneratorGraphValidationError(issues: issues.isEmpty ? [.noOutput] : issues)
        }

        // Nodes that feed the output.
        var reachable: Set<String> = [outputID]
        var pending: [String] = [outputID]
        while let id = pending.popLast() {
            for p in structure.predecessors[id] ?? [] where !reachable.contains(p) {
                reachable.insert(p)
                pending.append(p)
            }
        }
        let ids = structure.sortedIDs.filter { reachable.contains($0) }
        let order = GeneratorGraphValidator.topologicalOrder(structure, ids: ids)

        // Bounds.
        var bounds: [String: GraphBound] = [:]
        for id in order {
            guard let node = structure.nodes[id], let kind = structure.kinds[id] else { continue }
            let spec = kind.spec
            let inputs = spec.valueInputs.map { (input: GraphInputSpec) -> GraphBound in
                inputBound(input, node: node, bounds: bounds)
            }
            let phaseConnected = spec.phaseInput.map { node.inputs[$0.name] != nil } ?? false
            bounds[id] = GraphRateBounds.bound(kind, inputs: inputs, phaseConnected: phaseConnected) { (name: String) -> Double in
                GraphSettings.value(name, of: node, kind: kind)
            }
        }
        let rate = bounds[outputID]?.d ?? .zero
        var late: [GeneratorGraphIssue] = []
        let limit = GeneratorGraphLimits.maxSlowdown * GeneratorGraphLimits.rateBudget
        if !(rate.p <= limit) { late.append(.tooFast(.time)) }
        if !(rate.a <= limit) { late.append(.tooFast(.music)) }

        // Registers and instructions.
        let emitted = order.filter { (id: String) -> Bool in
            let kind = structure.kinds[id]
            return kind != .time && kind != .coordinates
        }
        var lastUse: [String: Int] = [:]
        for (index, id) in emitted.enumerated() {
            for source in structure.nodes[id]?.inputs.values.map({ (s: String) -> String in s }) ?? [] {
                lastUse[source] = index
            }
        }
        var free: [Int] = []          // sorted ascending
        var nextRegister = 0
        var register: [String: Int] = [:]
        var instructions: [GraphInstruction] = []
        var terms: [GraphTimeTerm] = []
        for (index, id) in emitted.enumerated() {
            guard let node = structure.nodes[id], let kind = structure.kinds[id] else { continue }
            let instruction = makeInstruction(node, kind: kind, register: register)
            // Sources whose last use is here are freed before the result is assigned.
            let released = Set(node.inputs.values).filter { lastUse[$0] == index }.compactMap { register[$0] }
            for r in released.sorted() { insertSorted(&free, r) }
            var dst = 0
            if kind != .output {
                if free.isEmpty {
                    dst = nextRegister
                    nextRegister += 1
                } else {
                    dst = free.removeFirst()
                }
                register[id] = dst
                if lastUse[id] == nil { insertSorted(&free, dst) }
            }
            var i = instruction
            i.dst = UInt32(dst)
            instructions.append(i)
            terms.append(timeTerm(node, kind: kind))
        }
        if nextRegister > GeneratorGraphLimits.registers { late.insert(.tooManyLiveValues(count: nextRegister), at: 0) }
        guard late.isEmpty else { throw GeneratorGraphValidationError(issues: late) }

        let speedCap = rate.p > 0 ? min(1, GeneratorGraphLimits.rateBudget / rate.p) : 1
        let musicRate = rate.a > 0 ? min(1, GeneratorGraphLimits.rateBudget / rate.a) : 1
        return CompiledGeneratorGraph(name: document.name, speedCap: speedCap, musicRate: musicRate,
                                      defaultSpeed: min(max(document.speed, -speedCap), speedCap),
                                      timeRateBound: rate.p, musicRateBound: rate.a, order: order,
                                      instructions: instructions, timeTerms: terms, registerCount: nextRegister)
    }

    private static func insertSorted(_ list: inout [Int], _ v: Int) {
        let at = list.firstIndex { $0 > v } ?? list.count
        list.insert(v, at: at)
    }

    private static func inputBound(_ input: GraphInputSpec, node: GraphNode, bounds: [String: GraphBound]) -> GraphBound {
        if let source = node.inputs[input.name] {
            let b = bounds[source] ?? GraphBound(m: .infinity, d: GraphRate(p: .infinity, a: .infinity))
            return input.type == .point ? b : b.clamped(input.lower, input.upper)
        }
        if let literal = node.values[input.name] { return .literal(literal.components) }
        return input.type == .point ? .coordinates : .literal(input.defaultValue)
    }

    private static func makeInstruction(_ node: GraphNode, kind: GraphNodeKind, register: [String: Int]) -> GraphInstruction {
        let spec = kind.spec
        var sources: UInt32 = 0
        var flags: UInt32 = 0
        var operands = [SIMD4<Float>](repeating: .zero, count: 3)
        for (slot, input) in spec.valueInputs.enumerated() where slot < 3 {
            var source = GraphInstruction.literalSource
            if let from = node.inputs[input.name] {
                if let r = register[from] {
                    source = UInt32(r)
                    if input.type != .point {
                        flags |= 1 << UInt32(slot)
                        operands[slot] = SIMD4(Float(input.lower), Float(input.upper), 0, 0)
                    }
                } else {
                    source = GraphInstruction.coordinatesSource     // a `coordinates` node
                }
            } else if let literal = node.values[input.name] {
                operands[slot] = vector(literal.components)
            } else if input.type == .point {
                source = GraphInstruction.coordinatesSource
            } else {
                operands[slot] = vector(input.defaultValue)
            }
            sources |= source << (8 * UInt32(slot))
        }
        var settings = SIMD4<Float>.zero
        for (k, setting) in spec.settings.enumerated() where k < 4 {
            settings[k] = Float(GraphSettings.value(setting.name, of: node, kind: kind))
        }
        // Unused operand slots read as literals.
        for slot in spec.valueInputs.count..<3 { sources |= GraphInstruction.literalSource << (8 * UInt32(slot)) }
        return GraphInstruction(op: kind.opcode, dst: 0, sources: sources, flags: flags,
                                a: operands[0], b: operands[1], c: operands[2], settings: settings)
    }

    private static func vector(_ v: [Double]) -> SIMD4<Float> {
        SIMD4(v.count > 0 ? Float(v[0]) : 0, v.count > 1 ? Float(v[1]) : 0, v.count > 2 ? Float(v[2]) : 0, 0)
    }

    private static func timeTerm(_ node: GraphNode, kind: GraphNodeKind) -> GraphTimeTerm {
        let s = { (name: String) -> Double in GraphSettings.value(name, of: node, kind: kind) }
        switch kind {
        case .oscillate: return .cycle(rate: s("rate"), offset: s("offset"))
        case .spin: return .cycle(rate: s("rate"), offset: 0)
        case .drift: return .drift(x: s("velocityX"), y: s("velocityY"))
        case .palette: return node.inputs["shift"] != nil ? .cycle(rate: s("shiftRate"), offset: 0) : .none
        default: return .none
        }
    }
}
