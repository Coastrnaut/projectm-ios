// SceneModulationRestore.swift — per-edge restore of a document's bindings and modulation
// connections (MOD-013-R5 to R9; research MOD-013-D2, D3, D6; contract M3, M4;
// specs/064-mod-013-modulation-serialization).
//
// Every binding (`$.bindings[i]`) and connection (`$.modulation.connections[j]`) gets exactly one
// outcome, in document order: rejected (malformed ID), dropped (an end is retired), orphaned (an end
// is unknown but well-formed), rejected (invalid in this version, a feedback loop included), then
// rewritten (IDs migrated) or restored. Only restored and rewritten edges are applied; orphaned and
// rejected edges are preserved verbatim for re-save; dropped edges are not. Nothing is evaluated.
import ParameterExpression
import ParameterGraph

/// What became of one stored edge.
public enum SceneModulationOutcome: String, Sendable, Hashable, CaseIterable {
    /// Valid with its IDs as written; live.
    case restored
    /// Valid after the migration table rewrote an ID; live, re-saved with the new IDs.
    case rewritten
    /// An end is retired; not applied and not re-saved.
    case dropped
    /// An end is well-formed but unknown to this version; not applied, kept.
    case orphaned
    /// Malformed or invalid in this version; not applied, kept.
    case rejected

    /// Whether the edge is live after restore.
    public var isApplied: Bool { self == .restored || self == .rewritten }
    /// Whether capture writes the edge back as stored.
    public var isPreserved: Bool { self == .orphaned || self == .rejected }
}

/// The per-edge restore report (MOD-013-R7).
public struct SceneModulationReport: Sendable, Hashable {
    public struct Entry: Sendable, Hashable, CustomStringConvertible {
        /// `$.bindings[2]` or `$.modulation.connections[0]`.
        public let path: String
        public let outcome: SceneModulationOutcome
        /// The edge as stored, `source → target[.input]`.
        public let written: String
        /// The edge as applied (restored and rewritten only).
        public let applied: String?
        /// A readable reason (empty for restored edges).
        public let reason: String

        public var description: String {
            "\(outcome.rawValue) \(path): \(written)" + (applied.map { (a: String) -> String in a == written ? "" : " as \(a)" } ?? "")
                + (reason.isEmpty ? "" : " (\(reason))")
        }
    }

    /// Every binding then every connection, in document order, each exactly once.
    public var entries: [Entry]

    public init(entries: [Entry] = []) { self.entries = entries }

    /// The paths with `outcome`, in order.
    public func paths(_ outcome: SceneModulationOutcome) -> [String] {
        entries.filter { (e: Entry) -> Bool in e.outcome == outcome }.map(\.path)
    }
}

/// Orphaned and rejected edges, verbatim (unknown fields included), in document order.
public struct SceneModulationPreserved: Sendable, Hashable {
    public var bindings: [SceneBinding]
    public var connections: [SceneConnection]

    public init(bindings: [SceneBinding] = [], connections: [SceneConnection] = []) {
        self.bindings = bindings
        self.connections = connections
    }

    public var isEmpty: Bool { bindings.isEmpty && connections.isEmpty }
}

/// The result of `SceneDocument.restoreModulation(registry:)`.
public struct SceneModulationRestore: Sendable {
    /// Applied bindings, migrated, in document order.
    public var bindings: [AudioFeatureBinding]
    /// SHD-009 source text by (migrated) bound target.
    public var expressions: [ParameterID: String]
    /// Declared generators and applied connections (migrated); binding edges are in `bindings`.
    public var graph: ModulationGraph
    public var preserved: SceneModulationPreserved
    public var report: SceneModulationReport
    /// Contract M4 issues, in order: bindings, generator declarations, connections.
    public var issues: [SceneIssue]
}

extension SceneDocument {
    /// Restores every binding and connection on its own (contract M3). Never throws.
    public func restoreModulation(registry: ParameterRegistry) -> SceneModulationRestore {
        var restore = SceneModulationRestore(bindings: [], expressions: [:], graph: ModulationGraph(generators: modulation.generators),
                                             preserved: SceneModulationPreserved(), report: SceneModulationReport(), issues: [])
        let modulator = AudioFeatureModulator(registry: registry)
        var firstIndexByTarget: [ParameterID: Int] = [:]
        for (i, binding) in bindings.enumerated() {
            restoreBinding(binding, at: i, registry: registry, modulator: modulator, firstIndexByTarget: &firstIndexByTarget,
                           into: &restore)
        }
        restoreConnections(registry: registry, into: &restore)
        return restore
    }

    // MARK: Bindings

    private func restoreBinding(_ binding: SceneBinding, at i: Int, registry: ParameterRegistry, modulator: AudioFeatureModulator,
                                firstIndexByTarget: inout [ParameterID: Int], into restore: inout SceneModulationRestore) {
        let path = "$.bindings[\(i)]"
        func finish(_ outcome: SceneModulationOutcome, _ reason: String, applied: String? = nil, issue: SceneIssue? = nil) {
            restore.report.entries.append(SceneModulationReport.Entry(path: path, outcome: outcome, written: binding.edgeText,
                                                                      applied: applied, reason: reason))
            if let issue { restore.issues.append(issue) }
            if outcome.isPreserved { restore.preserved.bindings.append(binding) }
        }
        if let problem = binding.target.syntaxProblem {
            let reason = "the target \"\(binding.target)\" is ill-formed: \(problem)"
            return finish(.rejected, reason, issue: SceneIssue(.invalidBinding, path: path, "Binding \(i): \(reason)."))
        }
        if !ModulationIDMigrations.isAudioFeatureID(binding.sourceID) || ModulationIDMigrations.idProblem(binding.sourceID) != nil {
            let reason = "the audio feature ID \"\(binding.sourceID)\" is ill-formed"
            return finish(.rejected, reason, issue: SceneIssue(.invalidBinding, path: path + ".source", "Binding \(i): \(reason)."))
        }
        let source = Self.resolve(audio: binding.sourceID, registry)
        let target = Self.resolve(parameter: binding.target, registry)
        if let retired = source.retired ?? target.retired {
            let reason = "\"\(retired)\" is retired"
            return finish(.dropped, reason, issue: SceneIssue(.retiredReference, path: path,
                                                              "Binding \(i) (\(binding.edgeText)): \(reason); it is dropped and not saved again."))
        }
        guard let feature = AudioFeatureSource(id: source.id) else {
            let reason = "the audio feature \"\(source.id)\" is not known to this version"
            return finish(.orphaned, reason, issue: SceneIssue(.orphanedBinding, path: path + ".source",
                                                               "Binding \(i): \(reason); it is kept but not applied."))
        }
        let targetID = ParameterID(target.id)
        guard registry.contains(targetID) else {
            let reason = "\"\(targetID)\" is not a parameter of this version"
            return finish(.orphaned, reason, issue: SceneIssue(.orphanedBinding, path: path + ".target",
                                                               "Binding \(i): \(reason); it is kept but not applied."))
        }
        if let j = firstIndexByTarget[targetID] {
            let reason = "\"\(targetID)\" is already bound by binding \(j)"
            return finish(.rejected, reason, issue: SceneIssue(.duplicateBindingTarget, path: path + ".target",
                                                               "Binding \(i) targets \"\(targetID)\", already bound by binding \(j)."))
        }
        if binding.hasUnreadableCurve {   // MOD-004 contract K8: kept verbatim, never guessed
            return finish(.rejected, "the curve cannot be read by this version",
                          issue: SceneIssue(.unsupportedCurve, path: path + ".curve",
                                            "Binding \(i) uses a curve this version cannot read; it is kept but not applied."))
        }
        if let text = binding.expression {
            do {
                _ = try CompiledExpression(source: text)
            } catch {
                return finish(.rejected, "the expression does not compile: \(error)",
                              issue: SceneIssue(.invalidExpression, path: path + ".expression", "Binding \(i) expression: \(error)."))
            }
        }
        let live = binding.audioFeatureBinding(source: feature, target: targetID)
        do {
            try modulator.bind(live)
        } catch {
            // MOD-005-R10: an invalid attack or release time is reported at the envelope itself.
            let at: String = if case .invalidEnvelope = error { path + ".envelope" } else { path }
            return finish(.rejected, error.description, issue: SceneIssue(.invalidBinding, path: at, "Binding \(i): \(error.description)."))
        }
        firstIndexByTarget[targetID] = i
        restore.bindings.append(live)
        if let text = binding.expression { restore.expressions[targetID] = text }
        let applied = feature.id + " → " + targetID.rawValue
        if source.changed || target.changed {
            finish(.rewritten, "migrated to \(applied)", applied: applied,
                   issue: SceneIssue(.migratedReference, path: path, "Binding \(i) (\(binding.edgeText)) is applied as \(applied)."))
        } else {
            finish(.restored, "", applied: applied)
        }
    }

    // MARK: Connections

    private func restoreConnections(registry: ParameterRegistry, into restore: inout SceneModulationRestore) {
        let base = "$.modulation.connections"
        // Generator declarations alone (MOD-014): a contradictory declaration refuses the document.
        let declarationIssues = ModulationGraph(generators: modulation.generators).validate(in: registry)
        for issue in declarationIssues {
            // A duplicate is reported at its repeat; any other generator problem at its declaration.
            let k = issue.generatorID.flatMap { (id: String) -> Int? in
                let matches = { (g: ModulationGenerator) -> Bool in g.id == id }
                return issue.problem == .duplicateGenerator ? modulation.generators.lastIndex(where: matches)
                    : modulation.generators.firstIndex(where: matches)
            }
            restore.issues.append(SceneIssue(.invalidModulation, path: k.map { (k: Int) -> String in "$.modulation.generators[\(k)]" } ?? "$.modulation",
                                             "Modulation: \(issue.message)"))
        }
        let bindingEdges = restore.bindings.map { (b: AudioFeatureBinding) -> ModulationEdge in
            ModulationEdge(source: .audio(b.source), target: .parameter(b.target))
        }
        var accepted: [ModulationEdge] = []
        for (j, connection) in modulation.connections.enumerated() {
            let path = "\(base)[\(j)]"
            func finish(_ outcome: SceneModulationOutcome, _ reason: String, applied: String? = nil, issue: SceneIssue? = nil) {
                restore.report.entries.append(SceneModulationReport.Entry(path: path, outcome: outcome, written: connection.description,
                                                                          applied: applied, reason: reason))
                if let issue { restore.issues.append(issue) }
                if outcome.isPreserved { restore.preserved.connections.append(connection) }
            }
            func reject(_ reason: String) {
                finish(.rejected, reason, issue: SceneIssue(.rejectedConnection, path: path,
                                                            "Connection \(j) (\(connection)): \(reason); it is kept but not applied."))
            }
            guard declarationIssues.isEmpty else { reject("the modulation section's generators are invalid"); continue }
            let ends = [connection.source, connection.target]
            if let malformed = ends.first(where: { (n: SceneNodeRef) -> Bool in Self.malformed(n) }) {
                reject("\"\(malformed.id)\" is ill-formed"); continue
            }
            let resolved = ends.map { (n: SceneNodeRef) -> (ref: SceneNodeRef, retired: String?, changed: Bool) in
                Self.resolve(n, registry)
            }
            if let retired = resolved.compactMap(\.retired).first {
                let reason = "\"\(retired)\" is retired"
                finish(.dropped, reason, issue: SceneIssue(.retiredReference, path: path,
                                                           "Connection \(j) (\(connection)): \(reason); it is dropped and not saved again."))
                continue
            }
            if let unknown = resolved.map(\.ref).first(where: { (n: SceneNodeRef) -> Bool in Self.isUnknown(n, registry) }) {
                let reason = "the \(unknown.kindName) \"\(unknown.id)\" is not known to this version"
                finish(.orphaned, reason, issue: SceneIssue(.orphanedConnection, path: path,
                                                            "Connection \(j) (\(connection)): \(reason); it is kept but not applied."))
                continue
            }
            let migrated = SceneConnection(source: resolved[0].ref, target: resolved[1].ref, input: connection.input)
            guard let edge = migrated.edge else { reject("an end cannot be resolved"); continue }
            // Greedy in document order (research MOD-013-D3): any issue is this edge's.
            let candidate = ModulationGraph(generators: modulation.generators, edges: bindingEdges + accepted + [edge])
            if let issue = candidate.validate(in: registry).first {
                reject(issue.message); continue
            }
            accepted.append(edge)
            let applied = edge.description
            if resolved[0].changed || resolved[1].changed {
                finish(.rewritten, "migrated to \(applied)", applied: applied,
                       issue: SceneIssue(.migratedReference, path: path, "Connection \(j) (\(connection)) is applied as \(applied)."))
            } else {
                finish(.restored, "", applied: applied)
            }
        }
        restore.graph = ModulationGraph(generators: modulation.generators, edges: accepted)
    }

    // MARK: ID resolution

    private struct Resolved {
        let id: String
        let retired: String?
        let changed: Bool
    }

    private static func resolved(_ id: String, _ resolution: ModulationIDResolution) -> Resolved {
        switch resolution {
        case .unchanged: Resolved(id: id, retired: nil, changed: false)
        case let .renamed(to, _): Resolved(id: to, retired: nil, changed: true)
        case let .retired(chain): Resolved(id: chain.last ?? id, retired: chain.last ?? id, changed: true)
        }
    }

    private static func resolve(audio id: String, _ registry: ParameterRegistry) -> Resolved {
        resolved(id, registry.resolveAudioFeature(id))
    }

    private static func resolve(parameter id: ParameterID, _ registry: ParameterRegistry) -> Resolved {
        resolved(id.rawValue, registry.resolveParameter(id))
    }

    private static func resolve(_ node: SceneNodeRef, _ registry: ParameterRegistry) -> (ref: SceneNodeRef, retired: String?, changed: Bool) {
        switch node {
        case let .audio(id):
            let r = resolve(audio: id, registry)
            return (.audio(r.id), r.retired, r.changed)
        case let .parameter(id):
            let r = resolve(parameter: id, registry)
            return (.parameter(ParameterID(r.id)), r.retired, r.changed)
        case .generator:
            return (node, nil, false)   // document-local; declared or rejected by MOD-014
        }
    }

    /// Malformed IDs can never be known by any version: rejected, never orphaned.
    private static func malformed(_ node: SceneNodeRef) -> Bool {
        switch node {
        case let .audio(id): ModulationIDMigrations.idProblem(id) != nil || !ModulationIDMigrations.isAudioFeatureID(id)
        case let .parameter(id): id.syntaxProblem != nil
        case .generator: false   // MOD-014 reports malformed generator references
        }
    }

    private static func isUnknown(_ node: SceneNodeRef, _ registry: ParameterRegistry) -> Bool {
        switch node {
        case let .audio(id): AudioFeatureSource(id: id) == nil
        case let .parameter(id): !registry.contains(id)
        case .generator: false
        }
    }
}
