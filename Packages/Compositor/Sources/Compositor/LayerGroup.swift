// LayerGroup.swift — layer groups (CMP-011-R1 to R5, R7; research CMP-011-D1 to D3;
// specs/109-cmp-011-layer-groups/contracts/layer-groups.md; ADR-0039).
//
// CPU only (builds on Linux). A group is a record beside the stack's entries: an ID, a name, an
// enabled flag, an opacity and a CMP-005 transform. Membership is a field of each entry; a group's
// members are one unbroken run of the stack and its child order is the stack order (no nesting).
// A grouped layer is drawn with the matrix G(a) · L(a) (the group's placement after the layer's own,
// for the output aspect a); its own transform is never changed. A group is an isolated group: the
// compositor flattens it only when that is exact (`LayerGroupComposition.needsIsolation`).

/// The stable identity of one group. Unique within a stack and never reused by it (its own counter,
/// separate from layer IDs).
public struct LayerGroupID: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let rawValue: UInt64

    public init(rawValue: UInt64) { self.rawValue = rawValue }

    public static func < (lhs: LayerGroupID, rhs: LayerGroupID) -> Bool { lhs.rawValue < rhs.rawValue }

    public var description: String { "group#\(rawValue)" }
}

/// What a group shares with its layers.
public struct LayerGroupSettings: Sendable, Equatable {
    /// Free text (a UI row applies its own rule).
    public var name: String
    /// False hides every member (they keep rendering; research CMP-011-D7).
    public var isEnabled: Bool
    /// 0…1 (clamped; non-finite reads 1): the group drawn as one picture at this opacity.
    public var opacity: Double
    /// CMP-005; the anchor is in fractions of the output (a group has no picture of its own).
    public var transform: LayerTransform

    public init(name: String = "", isEnabled: Bool = true, opacity: Double = 1, transform: LayerTransform = .identity) {
        self.name = name
        self.isEnabled = isEnabled
        self.opacity = opacity.isFinite ? min(max(opacity, 0), 1) : 1
        self.transform = transform
    }
}

public struct LayerGroup: Sendable, Equatable {
    public let id: LayerGroupID
    public var settings: LayerGroupSettings

    public init(id: LayerGroupID, settings: LayerGroupSettings = LayerGroupSettings()) {
        self.id = id
        self.settings = settings
    }
}

/// The plain-Swift rules the compositor draws groups by (CPU reference, every host).
public enum LayerGroupComposition {
    /// Normalized layer → normalized output for a grouped layer: `group.matrix(a) * local.matrix(a)`
    /// (the layer's own placement first, then the group's). Typed steps, so equal values give
    /// bit-equal matrices on every host.
    public static func matrix(group: LayerTransform, local: LayerTransform, aspect: Double) -> LayerTransformMatrix {
        let g: LayerTransformMatrix = group.matrix(aspect: aspect)
        let l: LayerTransformMatrix = local.matrix(aspect: aspect)
        return g * l
    }

    /// `matrix(group:local:aspect: width ÷ height)`.
    public static func matrix(group: LayerTransform, local: LayerTransform, outputWidth: Int,
                              outputHeight: Int) -> LayerTransformMatrix {
        let aspect: Double = outputHeight > 0 ? Double(outputWidth) / Double(outputHeight) : 1
        return matrix(group: group, local: local, aspect: aspect)
    }

    /// True when the group must be drawn into its own picture first (ADR-0039): its opacity is below
    /// 1, or a visible member uses a blend mode other than normal ("over" is associative; the modes
    /// are not). Otherwise drawing the members straight onto the composite gives the same result.
    public static func needsIsolation<Modes: Sequence>(opacity: Double, modes: Modes) -> Bool where Modes.Element == LayerBlendMode {
        if opacity < 1 { return true }
        for mode in modes where mode != .normal { return true }
        return false
    }
}

// MARK: - Stack operations (CMP-011-R3)

extension LayerStack {
    /// The group with this ID.
    public func group(_ id: LayerGroupID) -> LayerGroup? { groups.first { (g: LayerGroup) -> Bool in g.id == id } }

    /// The group's members, bottom first (empty for an unknown ID).
    public func members(of id: LayerGroupID) -> [LayerInstanceID] {
        entries.compactMap { (e: LayerStackEntry) -> LayerInstanceID? in e.group == id ? e.id : nil }
    }

    /// Makes one group of `ids` (any order; they must be ungrouped and one unbroken run of the stack).
    @discardableResult
    public mutating func makeGroup(_ ids: [LayerInstanceID],
                                   settings: LayerGroupSettings = LayerGroupSettings()) throws(LayerStackError) -> LayerGroupID {
        guard !ids.isEmpty else { throw .emptyGroup(nil) }
        var indexes: [Int] = []
        for id in ids {
            guard let i = index(of: id) else { throw .unknownLayer(id) }
            if entries[i].group != nil { throw .layerAlreadyGrouped(id) }
            if !indexes.contains(i) { indexes.append(i) }
        }
        indexes.sort()
        guard let first = indexes.first, let last = indexes.last, last - first + 1 == indexes.count else {
            throw .layersNotContiguous
        }
        let id = takeGroupID()
        for i in indexes { entries[i].group = id }
        insertGroupRecord(LayerGroup(id: id, settings: settings))
        return id
    }

    /// Removes the group; its members become ungrouped with their own settings untouched.
    @discardableResult
    public mutating func ungroup(_ id: LayerGroupID) throws(LayerStackError) -> LayerGroup {
        guard let k = groups.firstIndex(where: { (g: LayerGroup) -> Bool in g.id == id }) else { throw .unknownGroup(id) }
        for i in entries.indices where entries[i].group == id { entries[i].group = nil }
        return groups.remove(at: k)
    }

    /// Replaces the group's name, enabled flag, opacity and transform.
    public mutating func setGroupSettings(_ settings: LayerGroupSettings, of id: LayerGroupID) throws(LayerStackError) {
        guard let k = groups.firstIndex(where: { (g: LayerGroup) -> Bool in g.id == id }) else { throw .unknownGroup(id) }
        groups[k].settings = settings
    }

    /// Moves the whole group so that its bottom member ends at `index` of the stack without the group
    /// (0…count − members). Refuses an index strictly inside another group's run.
    public mutating func moveGroup(_ id: LayerGroupID, to index: Int) throws(LayerStackError) {
        guard group(id) != nil else { throw .unknownGroup(id) }
        let run = entries.filter { (e: LayerStackEntry) -> Bool in e.group == id }
        var rest = entries.filter { (e: LayerStackEntry) -> Bool in e.group != id }
        guard (0...rest.count).contains(index) else { throw .indexOutOfRange(index: index, validRange: 0...rest.count) }
        if index > 0, index < rest.count, let below = rest[index - 1].group, below == rest[index].group {
            throw .splitsGroup(below)
        }
        rest.insert(contentsOf: run, at: index)
        entries = rest
        sortGroupRecords()
    }
}
