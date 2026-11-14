// SceneGroup.swift — CMP-011 layer groups in the scene document (CMP-011-R11, R12; research
// CMP-011-D4, D5; specs/109-cmp-011-layer-groups/contracts/layer-groups.md; ADR-0028 amendment).
//
// An optional top-level `groups` array, written only when a scene has groups (format version 1, so
// scenes without groups encode byte-identically and QA-004's matrix gains no row). Each group keeps
// its children as written: layer instance numbers, or anything else (a nested group from a newer
// version) kept verbatim. Degenerate structures are warnings (`invalidGroup`), never refusals. A layer
// belongs to the first group that lists it (document order): later listings are bad references.
// An invalid group is drawn ungrouped and kept for re-save; the repair `repairGroups` drops bad
// references, then removes groups still invalid. Plain Swift, no Foundation.
import Compositor

/// One saved child of a group.
public enum SceneGroupChild: Sendable, Hashable {
    /// A layer's instance ID.
    case layer(UInt64)
    /// Anything else, kept verbatim (drawn ungrouped and warned about).
    case other(SceneJSON)

    var json: SceneJSON {
        switch self {
        case let .layer(instance): .number(SceneNumber(instance))
        case let .other(value): value
        }
    }
}

/// One saved group (contract table in specs/109).
public struct SceneGroup: Sendable, Hashable {
    /// 1 … 2^53 − 1, unique among the scene's groups.
    public var id: UInt64
    public var name: String
    public var enabled: Bool
    /// 0…1.
    public var opacity: Double
    public var transform: LayerTransform
    /// In stack order when written by the app.
    public var children: [SceneGroupChild]
    /// Unknown group fields, kept verbatim.
    public var extra: [String: SceneJSON]

    public init(id: UInt64, name: String = "", enabled: Bool = true, opacity: Double = 1, transform: LayerTransform = .identity,
                children: [SceneGroupChild] = [], extra: [String: SceneJSON] = [:]) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.opacity = opacity
        self.transform = transform
        self.children = children
        self.extra = extra
    }

    /// A live group's saved form with its members (bottom first).
    public init(_ group: LayerGroup, members: [LayerInstanceID]) {
        self.init(id: group.id.rawValue, name: group.settings.name, enabled: group.settings.isEnabled, opacity: group.settings.opacity,
                  transform: group.settings.transform,
                  children: members.map { (m: LayerInstanceID) -> SceneGroupChild in .layer(m.rawValue) })
    }

    /// The live settings.
    public var settings: LayerGroupSettings {
        LayerGroupSettings(name: name, isEnabled: enabled, opacity: opacity, transform: transform)
    }

    public static func == (lhs: SceneGroup, rhs: SceneGroup) -> Bool { SceneEncoder.group(lhs) == SceneEncoder.group(rhs) }

    public func hash(into hasher: inout Hasher) { hasher.combine(SceneEncoder.group(self)) }
}

extension SceneLimits {
    /// CMP-011: at most one group per layer.
    public static let maximumGroups = LayerStack.maximumLayerCount
    /// CMP-011: children listed by one group.
    public static let maximumGroupChildren = LayerStack.maximumLayerCount
}

extension SceneEncoder {
    static func group(_ g: SceneGroup) -> SceneJSON {
        var o = g.extra
        o["id"] = .number(SceneNumber(g.id))
        o["name"] = .string(g.name)
        o["enabled"] = .bool(g.enabled)
        o["opacity"] = .double(g.opacity)
        o["transform"] = transform(g.transform)
        o["children"] = .array(g.children.map(\.json))
        return .object(o)
    }
}

// MARK: - Validation and repair

/// What the group rules say about a document's groups (one pass shared by validation, load and repair).
struct SceneGroupAnalysis {
    var issues: [SceneIssue] = []
    /// Indexes of `groups` without problems.
    var valid: [Int] = []
}

extension SceneDocument {
    /// The first layer index of each instance ID.
    private var layerIndexByInstance: [UInt64: Int] {
        var map: [UInt64: Int] = [:]
        for (i, layer) in layers.enumerated() where map[layer.instance] == nil { map[layer.instance] = i }
        return map
    }

    /// CMP-011 rules (contract "Scene document"): ID range and uniqueness, good child references (a
    /// layer of the scene, listed once, not listed by an earlier group), at least one layer, one
    /// unbroken run of `layers`.
    func analyzeGroups() -> SceneGroupAnalysis {
        var result = SceneGroupAnalysis()
        let indexByInstance = layerIndexByInstance
        var seenIDs: Set<UInt64> = []
        var claimedBy: [UInt64: Int] = [:]
        for (g, group) in groups.enumerated() {
            let path = "$.groups[\(g)]"
            let before = result.issues.count
            if group.id == 0 || group.id > SceneLimits.maximumInstanceID {
                result.issues.append(SceneIssue(.invalidGroup, path: path + ".id",
                                                "Group \(g) has ID \(group.id); group IDs are 1…\(SceneLimits.maximumInstanceID). Its layers are drawn ungrouped."))
            } else if !seenIDs.insert(group.id).inserted {
                result.issues.append(SceneIssue(.invalidGroup, path: path + ".id",
                                                "Group \(g) uses ID \(group.id), already used by an earlier group. Its layers are drawn ungrouped."))
            }
            var indexes: [Int] = []
            for (c, child) in group.children.enumerated() {
                let childPath = "\(path).children[\(c)]"
                guard case let .layer(instance) = child else {
                    result.issues.append(SceneIssue(.invalidGroup, path: childPath,
                                                    "Group \(g) lists something that is not a layer (nested groups are not drawn by this version). Its layers are drawn ungrouped."))
                    continue
                }
                guard let index = indexByInstance[instance] else {
                    result.issues.append(SceneIssue(.invalidGroup, path: childPath,
                                                    "Group \(g) lists layer \(instance), which the scene does not have. Its layers are drawn ungrouped."))
                    continue
                }
                if let owner = claimedBy[instance] {
                    let whose = owner == g ? "twice" : "already listed by group \(owner)"
                    result.issues.append(SceneIssue(.invalidGroup, path: childPath,
                                                    "Group \(g) lists layer \(instance) \(whose). Its layers are drawn ungrouped."))
                    continue
                }
                claimedBy[instance] = g
                indexes.append(index)
            }
            if group.children.isEmpty {
                result.issues.append(SceneIssue(.invalidGroup, path: path + ".children", "Group \(g) has no layers."))
            } else if let first = indexes.min(), let last = indexes.max(), last - first + 1 != indexes.count {
                result.issues.append(SceneIssue(.invalidGroup, path: path + ".children",
                                                "Group \(g)'s layers are not next to each other in the layer order. Its layers are drawn ungrouped."))
            }
            if result.issues.count == before { result.valid.append(g) }
        }
        return result
    }

    /// `repairGroups` (research CMP-011-D5): drops child references that are not layers of the scene,
    /// repeated, or listed by an earlier group; then removes groups that are still invalid (bad or
    /// repeated ID, no layers, not one unbroken run). Idempotent.
    mutating func repairGroups() {
        let indexByInstance = layerIndexByInstance
        var claimed: Set<UInt64> = []
        var ids: Set<UInt64> = []
        var kept: [SceneGroup] = []
        for var group in groups {
            var indexes: [Int] = []
            group.children = group.children.filter { (child: SceneGroupChild) -> Bool in
                guard case let .layer(instance) = child, let index = indexByInstance[instance],
                      claimed.insert(instance).inserted else { return false }
                indexes.append(index)
                return true
            }
            let idOK: Bool = group.id >= 1 && group.id <= SceneLimits.maximumInstanceID && !ids.contains(group.id)
            guard idOK, let first = indexes.min(), let last = indexes.max(), last - first + 1 == indexes.count else { continue }
            ids.insert(group.id)
            kept.append(group)
        }
        groups = kept
    }

    /// After layers were removed: drops references to instances no layer has any more, and the groups
    /// that this leaves without children (so a layer repair never leaves a dangling group reference).
    mutating func dropGroupReferences(toRemoved removed: Set<UInt64>) {
        guard !removed.isEmpty, !groups.isEmpty else { return }
        let remaining = Set(layers.map(\.instance))
        let gone = removed.subtracting(remaining)
        guard !gone.isEmpty else { return }
        groups = groups.compactMap { (group: SceneGroup) -> SceneGroup? in
            var g = group
            let wasEmpty = g.children.isEmpty
            g.children = g.children.filter { (child: SceneGroupChild) -> Bool in
                if case let .layer(instance) = child { return !gone.contains(instance) }
                return true
            }
            return g.children.isEmpty && !wasEmpty ? nil : g
        }
    }
}
