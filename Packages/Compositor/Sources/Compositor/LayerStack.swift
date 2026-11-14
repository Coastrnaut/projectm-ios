// LayerStack.swift — the ordered layer stack (CMP-002-R1 to R6, R12; research CMP-002-D1 to D5;
// specs/040-cmp-002-ordered-layer-stack/contracts/layer-stack.md).
//
// A plain value, CPU only (builds on Linux): callers edit it and hand it to
// `Compositor.apply(_:makeLayer:)`, which diffs it by instance ID. Index 0 is the BOTTOM layer;
// the last index is drawn on top. Every operation either succeeds or throws and leaves the stack
// unchanged. Opacity (CMP-003), transforms (CMP-005), blend modes (CMP-004) and fits (CMP-006)
// live in each entry's `LayerCompositeSettings`; groups, masks and solo/mute will add
// fields to the entry. SCN-001 adds `init(restoring:)`: a saved scene's stack is rebuilt with its
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

    public init(id: LayerInstanceID, descriptor: LayerDescriptor, settings: LayerCompositeSettings = LayerCompositeSettings()) {
        self.id = id
        self.descriptor = descriptor
        self.settings = settings
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
}

public struct LayerStack: Equatable, Sendable {
    /// At most 8 layers: each holds one or two drawable-size pictures and costs a render pass and a
    /// composite draw per frame (spec Clarifications; research CMP-002-D5).
    public static let maximumLayerCount = 8

    /// Bottom first.
    public private(set) var entries: [LayerStackEntry] = []
    /// The next ID's raw value; never decreases, so IDs are never reused.
    private var nextRawID: UInt64 = 1

    public init() {}

    /// Rebuilds a saved stack with its own instance IDs, bottom first (SCN-001, research
    /// SCN-001-D7; CMP-002 amendment). Refuses duplicate IDs, more than `maximumLayerCount` entries
    /// and kinds over their `maximumInstances`. The next added layer gets the largest restored ID + 1,
    /// so restored IDs are never reused.
    public init(restoring entries: [LayerStackEntry]) throws(LayerStackError) {
        var seen: Set<LayerInstanceID> = []
        var largest: UInt64 = 0
        for entry in entries {
            guard seen.insert(entry.id).inserted else { throw .duplicateLayer(entry.id) }
            try checkRoom(for: entry.descriptor.kind)
            self.entries.append(entry)
            largest = max(largest, entry.id.rawValue)
        }
        nextRawID = largest == UInt64.max ? largest : largest + 1
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
        return id
    }

    /// Removes the layer and returns its entry.
    @discardableResult
    public mutating func remove(_ id: LayerInstanceID) throws(LayerStackError) -> LayerStackEntry {
        guard let i = index(of: id) else { throw .unknownLayer(id) }
        return entries.remove(at: i)
    }

    /// Copies the layer directly above the original (same descriptor and settings, new ID).
    @discardableResult
    public mutating func duplicate(_ id: LayerInstanceID) throws(LayerStackError) -> LayerInstanceID {
        guard let i = index(of: id) else { throw .unknownLayer(id) }
        let original = entries[i]
        return try add(original.descriptor, settings: original.settings, at: i + 1)
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

    /// Equal when the entries are (the ID counter is bookkeeping, not content).
    public static func == (lhs: LayerStack, rhs: LayerStack) -> Bool { lhs.entries == rhs.entries }
}
