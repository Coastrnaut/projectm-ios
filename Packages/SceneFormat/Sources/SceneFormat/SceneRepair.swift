// SceneRepair.swift — the repair report shown before a scene opens, and the repairs it offers
// (SCN-012-R1 to R7, R15; specs/079-scn-012-scene-validation, contracts/scene-repair-report.md;
// ADR-0028 amendment).
//
// * A report turns a decode refusal, decode warnings, SCN-001 validation issues and MOD-013's
//   per-edge problems into grouped entries: the item in plain words, the problem, what happens if the
//   scene is opened anyway, and the repair actions. There is no second definition of validity: every
//   entry comes from an existing issue code or refusal.
// * Repairs are pure and deterministic: `repairing` runs the chosen actions in one canonical order,
//   and each action re-validates the document it is given and acts only on the paths of the codes
//   it owns (research SCN-012-D2). A clean document has no targets, so repairs are idempotent.
//   The scene ID, unknown layer kinds, unknown fields and unknown parameter values are never touched.
// Plain Swift, no Foundation: no files, no networking, nothing from a document is executed.
import Compositor
import ParameterGraph

/// One deterministic transformation of a document, in canonical order (data model table).
public enum SceneRepairAction: String, Sendable, Hashable, CaseIterable, Comparable {
    case renameScene
    case renumberLayers
    case removeBrokenLayers
    case removeExtraLayers
    case dropInvalidValues
    case dropInvalidModulation
    case dropMissingMedia
    case dropInvalidMappings
    /// Changes nothing: unknown content is kept by default (SCN-012-R15).
    case keepUnknownContent

    public var title: String {
        switch self {
        case .renameScene: "Name it \"\(SceneRepairAction.untitledName)\""
        case .renumberLayers: "Renumber duplicate layers"
        case .removeBrokenLayers: "Remove damaged layers"
        case .removeExtraLayers: "Remove extra layers"
        case .dropInvalidValues: "Drop invalid values"
        case .dropInvalidModulation: "Remove invalid modulation generators"
        case .dropMissingMedia: "Open without the missing media"
        case .dropInvalidMappings: "Drop invalid mappings"
        case .keepUnknownContent: "Keep unknown content"
        }
    }

    /// The name an invalid scene name is replaced with.
    public static let untitledName = "Untitled scene"

    /// Whether the action can change a document (`keepUnknownContent` never does).
    public var changesDocument: Bool { self != .keepUnknownContent }

    var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }

    public static func < (lhs: SceneRepairAction, rhs: SceneRepairAction) -> Bool { lhs.order < rhs.order }
}

/// The grouped problems of one scene and whether it can open (contract R1).
public struct SceneRepairReport: Sendable, Hashable {
    public enum Group: String, Sendable, Hashable, CaseIterable {
        case damagedFile
        case unsupportedVersion
        case missingMedia
        case invalidMappings
        case unknownContent
        case valuesAdjusted
        /// SCN-013: the scene was migrated from an older format version (a note only).
        case formatUpdated

        public var title: String {
            switch self {
            case .damagedFile: "Damaged file"
            case .unsupportedVersion: "Unsupported version"
            case .missingMedia: "Missing media"
            case .invalidMappings: "Invalid mappings"
            case .unknownContent: "Unknown content kept"
            case .valuesAdjusted: "Values adjusted"
            case .formatUpdated: "Updated format"
            }
        }

        var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    }

    public enum Severity: Int, Sendable, Hashable, Comparable, CaseIterable {
        /// Opens as is; nothing visible is lost.
        case note = 0
        /// Opens as is, but part of the scene is not shown or has no effect.
        case problem = 1
        /// Cannot open as is; a repair makes it openable.
        case needsRepair = 2
        /// Cannot open at all.
        case cannotOpen = 3

        public var title: String {
            switch self {
            case .note: "Note"
            case .problem: "Opens with a problem"
            case .needsRepair: "Needs repair"
            case .cannotOpen: "Cannot open"
            }
        }

        public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public struct Entry: Sendable, Hashable, CustomStringConvertible {
        public let group: Group
        public let severity: Severity
        /// The affected item in plain words: "Layer 2 (photo)", "Photo \"photo\"", "Scene file".
        public let item: String
        public let problem: String
        /// What happens if the scene is opened anyway.
        public let ifOpened: String
        public let actions: [SceneRepairAction]
        /// The SCN-001 issue code, or `refusal.<kind>` for a decode refusal.
        public let code: String
        public let path: String

        public var description: String {
            "\(group.rawValue) \(severity) \(code) \(item): \(problem) [\(actions.map(\.rawValue).joined(separator: ","))]"
        }
    }

    /// In group order, then source order.
    public let entries: [Entry]

    init(entries: [Entry]) {
        self.entries = entries.enumerated().sorted { (a: (offset: Int, element: Entry), b: (offset: Int, element: Entry)) -> Bool in
            a.element.group.order != b.element.group.order ? a.element.group.order < b.element.group.order : a.offset < b.offset
        }.map(\.element)
    }

    // MARK: Flags

    public var cannotOpen: Bool { entries.contains { (e: Entry) -> Bool in e.severity == .cannotOpen } }
    /// No entry needs a repair or refuses the scene.
    public var canOpenAsIs: Bool { entries.allSatisfy { (e: Entry) -> Bool in e.severity < .needsRepair } }
    /// Every action any entry offers, in canonical order.
    public var repairActions: [SceneRepairAction] {
        Set(entries.flatMap(\.actions)).sorted()
    }
    /// Openable after `repairActions`, and at least one of them changes the document.
    public var canOpenWithRepairs: Bool {
        !cannotOpen && repairActions.contains { (a: SceneRepairAction) -> Bool in a.changesDocument }
    }
    /// The user should see the report before the scene opens (SCN-012-R8): any problem or worse.
    public var needsReview: Bool { entries.contains { (e: Entry) -> Bool in e.severity >= .problem } }
    /// Groups that have entries, in order.
    public var groups: [Group] {
        Group.allCases.filter { (g: Group) -> Bool in entries.contains { (e: Entry) -> Bool in e.group == g } }
    }

    public func entries(in group: Group) -> [Entry] { entries.filter { (e: Entry) -> Bool in e.group == group } }

    /// "Cannot open", "Needs repair", "Opens with problems" or "Ready".
    public var statusText: String {
        if cannotOpen { return "Cannot open" }
        if !canOpenAsIs { return "Needs repair" }
        if needsReview { return "Opens with problems" }
        return "Ready"
    }
}

// MARK: - Building

/// What `SceneRepairReport.open(bytes:)` returns: the report, and the document when it decoded.
public struct SceneRepairOpening: Sendable {
    public let report: SceneRepairReport
    public let document: SceneDocument?
    public let decodeWarnings: [SceneIssue]
}

extension SceneRepairReport {
    /// A decode refusal: one cannot-open entry, no actions (SCN-012-R6).
    public init(refusal: SceneDecodeError) {
        let group: Group
        let ifOpened: String
        switch refusal {
        case .newerVersion:
            group = .unsupportedVersion
            ifOpened = "Made by a newer version of the app: update the app to open it."
        case .migrationFailed:
            group = .unsupportedVersion
            ifOpened = "The scene's older format cannot be updated by this version of the app, so it cannot open."
        case .invalidVersion:
            group = .unsupportedVersion
            ifOpened = "The scene's format version cannot be read, so it cannot open."
        default:
            group = .damagedFile
            ifOpened = "The file is damaged and cannot open."
        }
        self.init(entries: [Entry(group: group, severity: .cannotOpen, item: "Scene file", problem: refusal.message,
                                  ifOpened: ifOpened, actions: [], code: "refusal." + Self.refusalName(refusal), path: "$")])
    }

    static func refusalName(_ refusal: SceneDecodeError) -> String {
        switch refusal {
        case .empty: "empty"
        case .tooLarge: "tooLarge"
        case .notJSON: "notJSON"
        case .nestingTooDeep: "nestingTooDeep"
        case .duplicateKey: "duplicateKey"
        case .notAScene: "notAScene"
        case .newerVersion: "newerVersion"
        case .invalidVersion: "invalidVersion"
        case .tooMany: "tooMany"
        case .malformed: "malformed"
        case .migrationFailed: "migrationFailed"
        }
    }

    /// A decoded document: one entry per decode warning and per validation issue (MOD-013's included).
    public init(document: SceneDocument, decodeWarnings: [SceneIssue] = [], registry: ParameterRegistry,
                assets availability: (any SceneAssetAvailability)? = nil) {
        let issues = decodeWarnings + document.validate(registry: registry, assets: availability)
        self.init(entries: issues.map { (issue: SceneIssue) -> Entry in Self.entry(for: issue, in: document) })
    }

    /// Bytes to a report (and the document when it decoded). Never throws, never traps (SCN-012-R7).
    /// `migrator` is the app's chain; tests pass synthetic chains (SCN-013).
    public static func open(bytes: [UInt8], registry: ParameterRegistry,
                            assets availability: (any SceneAssetAvailability)? = nil,
                            migrator: SceneMigrator = .standard) -> SceneRepairOpening {
        let decoded: SceneDecodeResult
        do {
            decoded = try SceneDocument.decode(bytes, migrator: migrator)
        } catch {
            return SceneRepairOpening(report: SceneRepairReport(refusal: error), document: nil, decodeWarnings: [])
        }
        var report = SceneRepairReport(document: decoded.document, decodeWarnings: decoded.warnings, registry: registry,
                                       assets: availability)
        if decoded.migration.migrated { report = report.adding(migrationNote(decoded.migration)) }
        return SceneRepairOpening(report: report, document: decoded.document, decodeWarnings: decoded.warnings)
    }

    /// SCN-013-R11: a migrated document gets one note; a note never makes the report need review.
    static func migrationNote(_ record: SceneMigrationRecord) -> Entry {
        Entry(group: .formatUpdated, severity: .note, item: "Scene file",
              problem: "Updated from an older format (version \(record.sourceVersion) to \(record.targetVersion)).",
              ifOpened: "It opens in the current format; the original file is kept when the scene is next saved.",
              actions: [], code: "migration.updated", path: "$")
    }

    func adding(_ entry: Entry) -> SceneRepairReport { SceneRepairReport(entries: entries + [entry]) }

    // MARK: Classification

    static let mappingCodes: Set<SceneIssue.Code> = [.invalidBinding, .duplicateBindingTarget, .invalidExpression, .orphanedBinding,
                                                     .orphanedConnection, .rejectedConnection, .retiredReference]
    /// Warnings the user should see before opening (Clarifications Q1).
    static let userRelevantWarnings: Set<SceneIssue.Code> = mappingCodes.union([.missingAsset, .unknownLayerKind])

    /// The group and the action that repairs an issue code (data model table).
    static func classify(_ code: SceneIssue.Code) -> (group: Group, action: SceneRepairAction?) {
        switch code {
        case .invalidSceneID: (.damagedFile, nil)
        case .invalidName: (.damagedFile, .renameScene)
        case .instanceOutOfRange, .duplicateInstance: (.damagedFile, .renumberLayers)
        case .kindLimit: (.damagedFile, .removeExtraLayers)
        case .invalidValueName, .malformedParameterID: (.damagedFile, .dropInvalidValues)
        case .unknownMaterial, .assetTypeMismatch, .invalidAssetKey, .invalidStoreID, .invalidTextAsset, .invalidGraphAsset:
            (.damagedFile, .removeBrokenLayers)
        case .danglingAsset: (.missingMedia, .removeBrokenLayers)
        case .missingAsset: (.missingMedia, .dropMissingMedia)
        case .invalidBinding, .duplicateBindingTarget, .invalidExpression, .orphanedBinding, .orphanedConnection, .rejectedConnection,
             .retiredReference:
            (.invalidMappings, .dropInvalidMappings)
        case .invalidModulation: (.invalidMappings, .dropInvalidModulation)
        case .unknownLayerKind: (.unknownContent, .keepUnknownContent)
        case .unknownAssetType, .unusedAsset, .orphanedParameter: (.unknownContent, nil)
        case .unsupportedBlendMode, .unsupportedFitMode, .unsupportedMaskShape, .valueClamped, .droppedField, .parameterClamped, .rejectedParameter, .migratedReference:
            (.valuesAdjusted, nil)
        }
    }

    static func entry(for issue: SceneIssue, in document: SceneDocument) -> Entry {
        let (group, action) = classify(issue.code)
        let severity: Severity
        if issue.isError {
            severity = action == nil ? .cannotOpen : .needsRepair
        } else {
            severity = userRelevantWarnings.contains(issue.code) ? .problem : .note
        }
        return Entry(group: group, severity: severity, item: ScenePathItem.describe(issue.path, in: document), problem: issue.message,
                     ifOpened: ifOpened(issue.code, severity), actions: action.map { (a: SceneRepairAction) -> [SceneRepairAction] in [a] } ?? [],
                     code: issue.code.rawValue, path: issue.path)
    }

    static func ifOpened(_ code: SceneIssue.Code, _ severity: Severity) -> String {
        switch severity {
        case .cannotOpen: return "The scene cannot open."
        case .needsRepair: return "The scene cannot open until this is repaired."
        case .problem, .note: break
        }
        switch code {
        case .missingAsset: return "Its layer draws nothing until the media is stored again."
        case .retiredReference: return "It is dropped and not saved again."
        case .invalidBinding, .duplicateBindingTarget, .invalidExpression, .orphanedBinding, .orphanedConnection, .rejectedConnection:
            return "It is kept in the scene but has no effect."
        case .unknownLayerKind: return "The layer is kept but not shown."
        case .unknownAssetType, .unusedAsset, .orphanedParameter: return "It is kept but not used by this version."
        case .rejectedParameter: return "The current value is kept."
        case .migratedReference: return "It is applied under its new name."
        default: return "It opens with the adjusted value."
        }
    }
}

// MARK: - Paths in plain words

enum ScenePathItem {
    /// The index after `prefix` in `path` ("$.layers[3].kind" with "$.layers[" → 3).
    static func index(_ path: String, after prefix: String) -> Int? {
        guard path.hasPrefix(prefix) else { return nil }
        var value = 0
        var digits = 0
        for c in path.dropFirst(prefix.count) {
            guard let d = c.wholeNumberValue, c.isASCII else { return c == "]" && digits > 0 ? value : nil }
            guard digits < 9 else { return nil }
            value = value * 10 + d
            digits += 1
        }
        return nil
    }

    /// Whether `path` is `base` or inside it.
    static func isWithin(_ path: String, _ base: String) -> Bool {
        path == base || path.hasPrefix(base + ".") || path.hasPrefix(base + "[")
    }

    static func assetKey(_ path: String, in document: SceneDocument) -> String? {
        document.assets.keys.first { (key: String) -> Bool in isWithin(path, ScenePath.key("$.assets", key)) }
    }

    static func assetTitle(_ kind: SceneAssetKind) -> String {
        switch kind {
        case .photo: "Photo"
        case .video: "Video"
        case .text: "Text"
        case .generatorGraph: "Generator graph"
        case .unknown: "Asset"
        }
    }

    static func describe(_ path: String, in document: SceneDocument) -> String {
        if let i = index(path, after: "$.layers[") {
            let kind = i < document.layers.count ? document.layers[i].kind : "layer"
            return "Layer \(i + 1) (\(kind))"
        }
        if let key = assetKey(path, in: document), let asset = document.assets[key] {
            return "\(assetTitle(asset.kind)) \"\(key)\""
        }
        if let i = index(path, after: "$.bindings[") {
            return i < document.bindings.count ? "Mapping \(i + 1) (\(document.bindings[i].edgeText))" : "Mapping \(i + 1)"
        }
        if let j = index(path, after: "$.modulation.connections[") {
            let connections = document.modulation.connections
            return j < connections.count ? "Connection \(j + 1) (\(connections[j]))" : "Connection \(j + 1)"
        }
        if let k = index(path, after: "$.modulation.generators[") {
            let generators = document.modulation.generators
            return k < generators.count ? "Generator \"\(generators[k].id)\"" : "Generator \(k + 1)"
        }
        if let id = document.parameters.keys.first(where: { (id: ParameterID) -> Bool in path == ScenePath.key("$.parameters", id.rawValue) }) {
            return "Value \"\(id)\""
        }
        switch path {
        case "$.name": return "Scene name"
        case "$.id": return "Scene ID"
        case "$.modulation": return "Modulation"
        default: return "Scene"
        }
    }
}

// MARK: - Repairing

extension SceneDocument {
    /// The document with `actions` applied in canonical order (contract R2). Pure and idempotent; the
    /// stored file is the caller's and is never touched here.
    public func repairing(_ actions: [SceneRepairAction], registry: ParameterRegistry,
                          assets availability: (any SceneAssetAvailability)? = nil) -> SceneDocument {
        var document = self
        let cache = SceneIssueCache(registry: registry, assets: availability)
        for action in Set(actions).sorted() {
            document = document.applying(action, cache)
        }
        return document
    }

    /// The report's own repairs (what "Open with repairs" applies).
    public func repairing(with report: SceneRepairReport, registry: ParameterRegistry,
                          assets availability: (any SceneAssetAvailability)? = nil) -> SceneDocument {
        repairing(report.repairActions, registry: registry, assets: availability)
    }

    private func issuePaths(_ codes: Set<SceneIssue.Code>, _ cache: SceneIssueCache) -> [String] {
        cache.issues(of: self)
            .filter { (issue: SceneIssue) -> Bool in codes.contains(issue.code) }
            .map(\.path)
    }

    private func applying(_ action: SceneRepairAction, _ cache: SceneIssueCache) -> SceneDocument {
        let registry = cache.registry
        var d = self
        switch action {
        case .renameScene:
            if !Self.isValidName(d.name) { d.name = SceneRepairAction.untitledName }
        case .renumberLayers:
            d.renumberLayers()
        case .removeBrokenLayers:
            let paths = issuePaths([.unknownMaterial, .assetTypeMismatch, .danglingAsset, .invalidAssetKey, .invalidStoreID,
                                    .invalidTextAsset, .invalidGraphAsset], cache)
            let layers = Set(paths.compactMap { (p: String) -> Int? in ScenePathItem.index(p, after: "$.layers[") })
            let keys = Set(paths.compactMap { (p: String) -> String? in ScenePathItem.assetKey(p, in: d) })
            d.removeLayers(at: layers, andAssets: keys)
        case .removeExtraLayers:
            var count: [String: Int] = [:]
            var extra: Set<Int> = []
            for (i, layer) in d.layers.enumerated() {
                let n = (count[layer.kind] ?? 0) + 1
                count[layer.kind] = n
                if let limit = layer.content.layerKind?.maximumInstances, n > limit { extra.insert(i) }
            }
            d.removeLayers(at: extra, andAssets: [])
        case .dropInvalidValues:
            for i in d.layers.indices {
                d.layers[i].values = d.layers[i].values.filter { (entry: (key: String, value: Double)) -> Bool in
                    Self.isValidValueName(entry.key)
                }
            }
            d.parameters = d.parameters.filter { (entry: (key: ParameterID, value: ParameterValue)) -> Bool in
                entry.key.syntaxProblem == nil
            }
        case .dropInvalidModulation:
            d.dropInvalidGenerators(cache)
        case .dropMissingMedia:
            let keys = Set(issuePaths([.missingAsset], cache).compactMap { (p: String) -> String? in
                ScenePathItem.assetKey(p, in: d)
            })
            d.removeLayers(at: [], andAssets: keys)
        case .dropInvalidMappings:
            let report = d.restoreModulation(registry: registry).report
            let applied = Set(report.entries.filter { (e: SceneModulationReport.Entry) -> Bool in e.outcome.isApplied }.map(\.path))
            d.bindings = d.bindings.enumerated().filter { (item: (offset: Int, element: SceneBinding)) -> Bool in
                applied.contains("$.bindings[\(item.offset)]")
            }.map(\.element)
            d.modulation.connections = d.modulation.connections.enumerated().filter { (item: (offset: Int, element: SceneConnection)) -> Bool in
                applied.contains("$.modulation.connections[\(item.offset)]")
            }.map(\.element)
        case .keepUnknownContent:
            break
        }
        return d
    }

    /// Research SCN-012-D3: the first layer with each valid ID keeps it; every later duplicate or
    /// out-of-range layer gets the smallest positive ID not yet used, in document order.
    private mutating func renumberLayers() {
        var used: Set<UInt64> = []
        var renumber: [Int] = []
        for (i, layer) in layers.enumerated() {
            let id = layer.instance
            if id >= 1, id <= SceneLimits.maximumInstanceID, !used.contains(id) {
                used.insert(id)
            } else {
                renumber.append(i)
            }
        }
        var next: UInt64 = 1
        for i in renumber {
            while used.contains(next) { next += 1 }
            layers[i].instance = next
            used.insert(next)
        }
    }

    /// Removes the layers at `indexes` and every layer using a key in `keys`, then the assets in
    /// `keys` and the assets only the removed layers used.
    private mutating func removeLayers(at indexes: Set<Int>, andAssets keys: Set<String>) {
        guard !indexes.isEmpty || !keys.isEmpty else { return }
        var removedKeys: Set<String> = []
        var kept: [SceneLayer] = []
        for (i, layer) in layers.enumerated() {
            let key = layer.content.assetKey
            if indexes.contains(i) || key.map({ (k: String) -> Bool in keys.contains(k) }) == true {
                if let key { removedKeys.insert(key) }
            } else {
                kept.append(layer)
            }
        }
        layers = kept
        let stillUsed = Set(kept.compactMap { (l: SceneLayer) -> String? in l.content.assetKey })
        for key in keys.union(removedKeys) where !stillUsed.contains(key) {
            assets[key] = nil
        }
    }

    /// Removes the generators MOD-014 reports at a declaration (all of them when a problem has no
    /// declaration), then the connections that use a generator no longer declared.
    private mutating func dropInvalidGenerators(_ cache: SceneIssueCache) {
        let paths = issuePaths([.invalidModulation], cache)
        guard !paths.isEmpty else { return }
        let flagged = paths.map { (p: String) -> Int? in ScenePathItem.index(p, after: "$.modulation.generators[") }
        if flagged.contains(where: { (k: Int?) -> Bool in k == nil }) {
            modulation.generators = []
        } else {
            let remove = Set(flagged.compactMap { (k: Int?) -> Int? in k })
            modulation.generators = modulation.generators.enumerated().filter { (item: (offset: Int, element: ModulationGenerator)) -> Bool in
                !remove.contains(item.offset)
            }.map(\.element)
            // A removal can expose another declaration problem; then the section goes as a whole.
            if !issuePaths([.invalidModulation], cache).isEmpty { modulation.generators = [] }
        }
        let declared = Set(modulation.generators.map(\.id))
        modulation.connections = modulation.connections.filter { (c: SceneConnection) -> Bool in
            [c.source, c.target].allSatisfy { (n: SceneNodeRef) -> Bool in
                if case let .generator(id) = n { declared.contains(id) } else { true }
            }
        }
    }
}

/// One repair run's validation results, keyed by the document's canonical bytes: actions that change
/// nothing do not validate again (owner rule 7: the fuzz stays within its budget).
private final class SceneIssueCache {
    let registry: ParameterRegistry
    let availability: (any SceneAssetAvailability)?
    private var bytes: [UInt8]?
    private var cached: [SceneIssue] = []

    init(registry: ParameterRegistry, assets availability: (any SceneAssetAvailability)?) {
        self.registry = registry
        self.availability = availability
    }

    func issues(of document: SceneDocument) -> [SceneIssue] {
        let key = document.encoded()
        if key == bytes { return cached }
        bytes = key
        cached = document.validate(registry: registry, assets: availability)
        return cached
    }
}
