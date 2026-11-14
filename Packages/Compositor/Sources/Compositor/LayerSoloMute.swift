// LayerSoloMute.swift — non-destructive solo and mute (CMP-012-R1 to R5; research CMP-012-D1 to D3;
// specs/112-cmp-012-solo-and-mute/contracts/solo-and-mute.md).
//
// CPU only (builds on Linux). A transient view-state overlay kept BESIDE the `LayerStack`, never in
// it: the stack, the scene document, autosave, undo history, show cues and archives cannot see it, and
// it never writes a layer's opacity or a group's enabled flag. The compositor is given one with
// `setSoloMute(_:)`. Deliberately not `Codable`: it is never saved.
//
// The rule (`lets`): a layer passes when it is not muted, its group is not muted, and either no solo
// is active, or the layer or its group is soloed. Solos combine as a union; mute wins over solo, and a
// muted solo still counts as active (so muting the soloed layer does not bring the whole stack back).
// Only IDs present in the stack count: a stale solo cannot black out the picture.

public struct LayerSoloMute: Sendable, Equatable {
    public private(set) var soloedLayers: Set<LayerInstanceID> = []
    public private(set) var mutedLayers: Set<LayerInstanceID> = []
    public private(set) var soloedGroups: Set<LayerGroupID> = []
    public private(set) var mutedGroups: Set<LayerGroupID> = []

    /// Nothing soloed or muted.
    public init() {}

    /// True when nothing is soloed or muted.
    public var isEmpty: Bool { soloedLayers.isEmpty && mutedLayers.isEmpty && soloedGroups.isEmpty && mutedGroups.isEmpty }

    public mutating func setSolo(_ on: Bool, layer id: LayerInstanceID) {
        if on { soloedLayers.insert(id) } else { soloedLayers.remove(id) }
    }

    public mutating func setMute(_ on: Bool, layer id: LayerInstanceID) {
        if on { mutedLayers.insert(id) } else { mutedLayers.remove(id) }
    }

    public mutating func setSolo(_ on: Bool, group id: LayerGroupID) {
        if on { soloedGroups.insert(id) } else { soloedGroups.remove(id) }
    }

    public mutating func setMute(_ on: Bool, group id: LayerGroupID) {
        if on { mutedGroups.insert(id) } else { mutedGroups.remove(id) }
    }

    /// Clears every solo and mute.
    public mutating func clear() { self = LayerSoloMute() }

    public func isSoloed(layer id: LayerInstanceID) -> Bool { soloedLayers.contains(id) }
    public func isMuted(layer id: LayerInstanceID) -> Bool { mutedLayers.contains(id) }
    public func isSoloed(group id: LayerGroupID) -> Bool { soloedGroups.contains(id) }
    public func isMuted(group id: LayerGroupID) -> Bool { mutedGroups.contains(id) }

    /// True when a layer or group of `stack` is soloed (muted solos included; absent IDs ignored).
    public func isSoloActive(in stack: LayerStack) -> Bool {
        if soloedLayers.isEmpty && soloedGroups.isEmpty { return false }
        for e in stack.entries where soloedLayers.contains(e.id) { return true }
        for g in stack.groups where soloedGroups.contains(g.id) { return true }
        return false
    }

    /// Whether the overlay lets `entry` through (CMP-012-R3). The saved conditions (opacity, group on/off)
    /// are not part of this; see `visibleLayers(in:)`.
    public func lets(_ entry: LayerStackEntry, in stack: LayerStack) -> Bool {
        lets(entry, soloActive: isSoloActive(in: stack))
    }

    /// `lets` with `isSoloActive` computed once by the caller.
    public func lets(_ entry: LayerStackEntry, soloActive: Bool) -> Bool {
        if mutedLayers.contains(entry.id) { return false }
        if let g = entry.group, mutedGroups.contains(g) { return false }
        guard soloActive else { return true }
        if soloedLayers.contains(entry.id) { return true }
        if let g = entry.group, soloedGroups.contains(g) { return true }
        return false
    }

    /// The layers of `stack` the overlay hides.
    public func hiddenLayers(in stack: LayerStack) -> Set<LayerInstanceID> {
        let active = isSoloActive(in: stack)
        var hidden: Set<LayerInstanceID> = []
        for e in stack.entries where !lets(e, soloActive: active) { hidden.insert(e.id) }
        return hidden
    }

    /// The layers of `stack` that would be drawn, bottom first: the overlay's rule plus the saved
    /// conditions (saved opacity above 0; for a grouped layer, its group switched on with opacity above 0).
    /// A layer's picture this frame and its animated opacity are the compositor's part.
    public func visibleLayers(in stack: LayerStack) -> [LayerInstanceID] {
        let active = isSoloActive(in: stack)
        var visible: [LayerInstanceID] = []
        for e in stack.entries where e.settings.opacity > 0 && lets(e, soloActive: active) {
            if let g = e.group {
                guard let group = stack.group(g), group.settings.isEnabled, group.settings.opacity > 0 else { continue }
            }
            visible.append(e.id)
        }
        return visible
    }

    /// The overlay without entries for layers or groups `stack` does not have.
    public func pruned(to stack: LayerStack) -> LayerSoloMute {
        let layers = Set(stack.ids)
        let groups = Set(stack.groups.map(\.id))
        var copy = self
        copy.soloedLayers.formIntersection(layers)
        copy.mutedLayers.formIntersection(layers)
        copy.soloedGroups.formIntersection(groups)
        copy.mutedGroups.formIntersection(groups)
        return copy
    }
}
