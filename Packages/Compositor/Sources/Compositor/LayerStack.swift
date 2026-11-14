// LayerStack.swift — the ordered layer stack (CMP-002-R1 to R6, R12; research CMP-002-D1 to D5;
// specs/040-cmp-002-ordered-layer-stack/contracts/layer-stack.md).
//
// A plain value, CPU only (builds on Linux): callers edit it and hand it to
// `Compositor.apply(_:makeLayer:)`, which diffs it by instance ID. Index 0 is the BOTTOM layer;
// the last index is drawn on top. Every operation either succeeds or throws and leaves the stack
// unchanged. Opacity (CMP-003), transforms (CMP-005), blend modes (CMP-004) and fits (CMP-006)
// live in each entry's `LayerCompositeSettings`; masks (CMP-007) too; solo/mute will add
// fields to the entry. CMP-011 (LayerGroup.swift): `entry.group` and `groups`; every group is one
// unbroken run, kept so by the membership rule in `add`, `duplicate`, `move` and `remove`. SCN-001 adds `init(restoring:)`: a saved scene's stack is rebuilt with its
// own instance IDs (specs/059-scn-001-versioned-scene-format, research SCN-001-D7).

/// The stable identity of one stack entry. Unique within a stack and never reused by it, so the
/// compositor can keep a live layer per ID across edits.
public struct LayerInstanceID: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let rawValue: UInt64

    public init(rawValue: UInt64) { self.rawValue = rawValue }

    public static func < (lhs: LayerInstanceID, rhs: LayerInstanceID) -> Bool { lhs.rawValue < rhs.rawValue }

    public var description: String { "layer#\(rawValue)" }
}

/// What sort of layer an entry is. Declared by the layer targets (`.camera` in CameraLayer,
/// `.circularSpectrum` and `.linearSpectrum` in SpectrumLayers), so Compositor names none of them.
public struct LayerKind: Hashable, Sendable, CustomStringConvertible {
    /// Stable identifier, e.g. `camera`.
    public let identifier: String
    /// How many entries of this kind one stack may hold; nil: only the stack's own limit.
    public let maximumInstances: Int?

    public init(_ identifier: String, maximumInstances: Int? = nil) {
        self.identifier = identifier
        self.maximumInstances = maximumInstances.map { max($0, 0) }
    }

    public var description: String { identifier }
}

/// A layer independent of its live object: its kind and its own parameters.
public struct LayerDescriptor: Equatable, Sendable {
    public var kind: LayerKind
    /// The layer's own values (copied by `duplicate`); their meaning belongs to the kind.
    public var parameters: [String: Double]

    public init(kind: LayerKind, parameters: [String: Double] = [:]) {
        self.kind = kind
        self.parameters = parameters
    }
}

public struct LayerStackEntry: Equatable, Sendable {
    public let id: LayerInstanceID
    public var descriptor: LayerDescriptor
    /// Any opacity (CMP-003; the target a layer settles at), transform (CMP-005) and blend mode
    /// (CMP-004); transform and mode are shown from the next frame.
    public var settings: LayerCompositeSettings
    /// CMP-011: the group this layer belongs to (nil: ungrouped).
    public var group: LayerGroupID?

    public init(id: LayerInstanceID, descriptor: LayerDescriptor, settings: LayerCompositeSettings = LayerCompositeSettings(),
                group: LayerGroupID? = nil) {
        self.id = id
        self.descriptor = descriptor
        self.settings = settings
        self.group = group
    }
}

/// Why a stack operation was refused (the stack is unchanged).
public enum LayerStackError: Error, Equatable, Sendable {
    case unknownLayer(LayerInstanceID)
    case indexOutOfRange(index: Int, validRange: ClosedRange<Int>)
    case stackFull(limit: Int)
    /// The kind's `maximumInstances` is reached (`.camera`: one capture session).
    case kindLimitReached(LayerKind)
    /// `init(restoring:)` was given two entries with the same ID (SCN-001).
    case duplicateLayer(LayerInstanceID)
    /// CMP-011: no group with this ID.
    case unknownGroup(LayerGroupID)
    /// CMP-011: `init(restoring:groups:)` was given two groups with the same ID.
    case duplicateGroup(LayerGroupID)
    /// CMP-011: a group without members (nil: `makeGroup` was given no layers).
    case emptyGroup(LayerGroupID?)
    /// CMP-011: a restored group's members are not one unbroken run.
    case groupNotContiguous(LayerGroupID)
    /// CMP-011: the layer is in a group already (groups do not nest or overlap).
    case layerAlreadyGrouped(LayerInstanceID)
    /// CMP-011: the layers to group are not one unbroken run of the stack.
    case layersNotContiguous
    /// CMP-011: the index lies strictly inside this group's run.
    case splitsGroup(LayerGroupID)
}

public struct LayerStack: Equatable, Sendable {
    /// At most 8 layers: each holds one or two drawable-size pictures and costs a render pass and a
    /// composite draw per frame (spec Clarifications; research CMP-002-D5).
    public static let maximumLayerCount = 8

    /// Bottom first.
    public internal(set) var entries: [LayerStackEntry] = []
    /// CMP-011: in the order of their runs' first members.
    public internal(set) var groups: [LayerGroup] = []
    /// The next ID's raw value; never decreases, so IDs are never reused.
    private var nextRawID: UInt64 = 1
    /// CMP-011: the next group ID's raw value (never reused either).
    private var nextRawGroupID: UInt64 = 1

    public init() {}

    /// Rebuilds a saved stack with its own instance IDs, bottom first (SCN-001, research
    /// SCN-001-D7; CMP-002 amendment). Refuses duplicate IDs, more than `maximumLayerCount` entries
    /// and kinds over their `maximumInstances`. The next added layer gets the largest restored ID + 1,
    /// so restored IDs are never reused.
    /// CMP-011: `groups` are the saved groups; each entry's `group` must name one of them, every group
    /// needs a member and its members must be one unbroken run (else a typed refusal).
    public init(restoring entries: [LayerStackEntry], groups: [LayerGroup] = []) throws(LayerStackError) {
        var seen: Set<LayerInstanceID> = []
        var largest: UInt64 = 0
        for entry in entries {
            guard seen.insert(entry.id).inserted else { throw .duplicateLayer(entry.id) }
            try checkRoom(for: entry.descriptor.kind)
            self.entries.append(entry)
            largest = max(largest, entry.id.rawValue)
        }
        nextRawID = largest == UInt64.max ? largest : largest + 1
        var groupIDs: Set<LayerGroupID> = []
        var largestGroup: UInt64 = 0
        for group in groups {
            guard groupIDs.insert(group.id).inserted else { throw .duplicateGroup(group.id) }
            largestGroup = max(largestGroup, group.id.rawValue)
        }
        for entry in entries {
            if let g = entry.group, !groupIDs.contains(g) { throw .unknownGroup(g) }
        }
        for group in groups {
            guard entries.contains(where: { (e: LayerStackEntry) -> Bool in e.group == group.id }) else { throw .emptyGroup(group.id) }
            guard isContiguous(group.id) else { throw .groupNotContiguous(group.id) }
        }
        self.groups = groups
        nextRawGroupID = largestGroup == UInt64.max ? largestGroup : largestGroup + 1
        sortGroupRecords()
    }

    public var count: Int { entries.count }
    public var isEmpty: Bool { entries.isEmpty }
    /// Bottom first.
    public var ids: [LayerInstanceID] { entries.map(\.id) }

    public func index(of id: LayerInstanceID) -> Int? { entries.firstIndex { $0.id == id } }

    public func entry(_ id: LayerInstanceID) -> LayerStackEntry? { index(of: id).map { entries[$0] } }

    /// Adds a layer at `index` (0…count; nil: on top) and returns its new ID.
    @discardableResult
    public mutating func add(_ descriptor: LayerDescriptor, settings: LayerCompositeSettings = LayerCompositeSettings(),
                             at index: Int? = nil) throws(LayerStackError) -> LayerInstanceID {
        let position = index ?? entries.count
        guard (0...entries.count).contains(position) else {
            throw .indexOutOfRange(index: position, validRange: 0...entries.count)
        }
        try checkRoom(for: descriptor.kind)
        let id = LayerInstanceID(rawValue: nextRawID)
        nextRawID += 1
        entries.insert(LayerStackEntry(id: id, descriptor: descriptor, settings: settings), at: position)
        settleMembership(at: position)   // CMP-011: inside a group's run it joins the group
        return id
    }

    /// Removes the layer and returns its entry.
    @discardableResult
    public mutating func remove(_ id: LayerInstanceID) throws(LayerStackError) -> LayerStackEntry {
        guard let i = index(of: id) else { throw .unknownLayer(id) }
        let removed = entries.remove(at: i)
        pruneEmptyGroups()   // CMP-011: a group left without members is removed
        return removed
    }

    /// Copies the layer directly above the original (same descriptor and settings, new ID).
    @discardableResult
    public mutating func duplicate(_ id: LayerInstanceID) throws(LayerStackError) -> LayerInstanceID {
        guard let i = index(of: id) else { throw .unknownLayer(id) }
        let original = entries[i]
        let copy = try add(original.descriptor, settings: original.settings, at: i + 1)
        if let group = original.group { entries[i + 1].group = group }   // CMP-011: joins its original's group
        return copy
    }

    /// Moves the layer so that it ends at `index` (0…count − 1).
    public mutating func move(_ id: LayerInstanceID, to index: Int) throws(LayerStackError) {
        guard let from = self.index(of: id) else { throw .unknownLayer(id) }
        guard (0..<entries.count).contains(index) else {
            throw .indexOutOfRange(index: index, validRange: 0...(entries.count - 1))
        }
        guard from != index else { return }
        let entry = entries.remove(at: from)
        entries.insert(entry, at: index)
        settleMembership(at: index)   // CMP-011
    }

    /// Replaces the layer's composite settings (CMP-003: its opacity is the target the compositor
    /// fades to at the next apply).
    public mutating func setSettings(_ settings: LayerCompositeSettings, of id: LayerInstanceID) throws(LayerStackError) {
        guard let i = index(of: id) else { throw .unknownLayer(id) }
        entries[i].settings = settings
    }

    private func checkRoom(for kind: LayerKind) throws(LayerStackError) {
        guard entries.count < Self.maximumLayerCount else { throw .stackFull(limit: Self.maximumLayerCount) }
        if let limit = kind.maximumInstances {
            var existing = 0
            for e in entries where e.descriptor.kind == kind { existing += 1 }
            if existing >= limit { throw .kindLimitReached(kind) }
        }
    }

    // MARK: - Groups (CMP-011; research CMP-011-D2)

    /// The entry just placed at `i` joins group H when both its neighbours are in H; otherwise it
    /// leaves its own group when that is no longer one unbroken run. Then empty groups are removed.
    /// Removing an entry from a run keeps every run unbroken, and a placement breaks a run only
    /// strictly between two of its members, so this keeps every group one run.
    private mutating func settleMembership(at i: Int) {
        if i > 0, i < entries.count - 1, let below = entries[i - 1].group, below == entries[i + 1].group {
            entries[i].group = below
        } else if let own = entries[i].group, !isContiguous(own) {
            entries[i].group = nil
        }
        pruneEmptyGroups()
    }

    /// Whether the members of `group` are one unbroken run (true for no members).
    func isContiguous(_ group: LayerGroupID) -> Bool {
        var first: Int?
        var last = -1
        var count = 0
        for (i, e) in entries.enumerated() where e.group == group {
            if first == nil { first = i }
            last = i
            count += 1
        }
        guard let first else { return true }
        return last - first + 1 == count
    }

    mutating func pruneEmptyGroups() {
        groups.removeAll { (g: LayerGroup) -> Bool in !entries.contains { (e: LayerStackEntry) -> Bool in e.group == g.id } }
        sortGroupRecords()
    }

    /// Orders the group records by their runs' first members (empty groups last; none after pruning).
    mutating func sortGroupRecords() {
        func start(_ g: LayerGroup) -> Int { entries.firstIndex { (e: LayerStackEntry) -> Bool in e.group == g.id } ?? Int.max }
        groups.sort { (a: LayerGroup, b: LayerGroup) -> Bool in start(a) < start(b) }
    }

    mutating func takeGroupID() -> LayerGroupID {
        let id = LayerGroupID(rawValue: nextRawGroupID)
        if nextRawGroupID < UInt64.max { nextRawGroupID += 1 }
        return id
    }

    mutating func insertGroupRecord(_ group: LayerGroup) {
        groups.append(group)
        sortGroupRecords()
    }

    /// Equal when the entries and groups are (the ID counters are bookkeeping, not content).
    public static func == (lhs: LayerStack, rhs: LayerStack) -> Bool { lhs.entries == rhs.entries && lhs.groups == rhs.groups }
}
