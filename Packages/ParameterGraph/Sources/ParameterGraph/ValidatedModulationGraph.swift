// ValidatedModulationGraph.swift — an accepted graph (MOD-014-R7, R8; contract G7, G8).

/// A modulation graph that passed validation.
public struct ValidatedModulationGraph: Sendable {
    public let graph: ModulationGraph
    public let registry: ParameterRegistry

    /// Validates `graph` against `registry`; throws every issue when it is refused.
    public init(_ graph: ModulationGraph, registry: ParameterRegistry) throws(ModulationGraphError) {
        let result = ModulationGraphValidator(graph: graph, registry: registry).run()
        guard result.issues.isEmpty else { throw ModulationGraphError(issues: result.issues) }
        self.graph = graph
        self.registry = registry
    }
}
