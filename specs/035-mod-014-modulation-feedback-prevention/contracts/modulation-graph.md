# Contract: modulation graph validation (MOD-014)

- **G1 Model**: `ModulationGraph(generators:edges:)` is a plain value; building one never fails.
- **G2 Validate**: `graph.validate(in: registry) -> [ModulationGraphIssue]` returns every issue,
  empty when the graph is accepted. It never traps, whatever the input.
- **G3 Limits**: more than `maximumEdges` (4,096) connections → exactly one `tooManyEdges` issue;
  else more than `maximumNodes` (1,024) nodes → exactly one `tooManyNodes` issue. Nothing else is
  checked.
- **G4 Structure**: generator issues in declaration order (malformed ID, empty name, duplicate,
  conflicting ID, malformed or duplicate input); then the first problem of each connection in
  connection order (unknown audio feature, unknown or retired parameter, unknown generator as
  source; audio target, unknown or retired parameter, unknown generator as target; unknown input;
  duplicate). Connections with a problem are left out of the loop search.
- **G5 Loops**: then one `selfLoop` issue per self-connection in connection order, then one `cycle`
  issue per strongly connected group of two or more nodes, ordered by the group's smallest node.
  Each carries a `ModulationCycle` whose `path` is the shortest loop through that node (ties by
  target ID, then input name), written as in data-model.md.
- **G6 Bounds**: O(V + E log V) time, O(V + E) memory, constant call depth.
- **G7 Order**: `ValidatedModulationGraph(graph, registry:)` throws `ModulationGraphError` with
  every issue, or provides `evaluationOrder`: every node exactly once, each source before its
  targets, smallest ID first among ready nodes.
- **G8 Incremental**: `wouldCreateCycle(adding: edge)` returns the shortest loop that the edge would
  close, starting at the edge's target and ending with the edge, or nil. Non-nil exactly when
  validating the graph plus the edge yields a `selfLoop` or `cycle` issue. It does not check the
  edge's endpoints (full validation does).
- **G9 Bindings**: `AudioFeatureModulator.modulationGraph` has one `.audio(source) →
  .parameter(target)` value connection per binding, in binding order. `bind` validates the
  candidate set after contract C2 of MOD-002; a loop throws
  `AudioFeatureBindingError.feedbackCycle(target, path:)` and leaves bindings unchanged.
