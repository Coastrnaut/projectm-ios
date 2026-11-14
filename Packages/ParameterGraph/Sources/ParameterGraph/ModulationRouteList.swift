// ModulationRouteList.swift — the modulation matrix's view of a binding list and its two edits on a plain list
// (MOD-012-R1, R3, R6; contract specs/189-mod-012-modulation-matrix/contracts/modulation-matrix.md M2).
//
// The same edits as `AudioFeatureModulator.setEnabled` and `moveLayer`, for a list held outside a modulator (the
// scene carry while no native visual exists). Pure and Foundation-free.

/// One destination and its bindings in fold order (MOD-012-R1).
public struct ModulationRouteGroup: Sendable, Hashable {
    public let target: ParameterID
    public let layers: [AudioFeatureBinding]

    public init(target: ParameterID, layers: [AudioFeatureBinding]) {
        self.target = target
        self.layers = layers
    }
}

public enum ModulationRouteList {
    /// Groups `list` by destination, destinations in first-appearance order, layers in list (fold) order.
    public static func groups(_ list: [AudioFeatureBinding]) -> [ModulationRouteGroup] {
        var order: [ParameterID] = []
        var layers: [ParameterID: [AudioFeatureBinding]] = [:]
        for binding in list {
            if layers[binding.target] == nil { order.append(binding.target) }
            layers[binding.target, default: []].append(binding)
        }
        return order.map { (id: ParameterID) -> ModulationRouteGroup in ModulationRouteGroup(target: id, layers: layers[id] ?? []) }
    }

    /// The list index of `target`'s `layer`-th binding (0-based), or nil.
    public static func index(in list: [AudioFeatureBinding], target: ParameterID, layer: Int) -> Int? {
        var seen = 0
        for (i, binding) in list.enumerated() where binding.target == target {
            if seen == layer { return i }
            seen += 1
        }
        return nil
    }

    /// `list` with `target`'s `layer`-th binding turned on or off; nil when there is no such layer.
    public static func settingEnabled(_ enabled: Bool, in list: [AudioFeatureBinding], target: ParameterID,
                                      layer: Int) -> [AudioFeatureBinding]? {
        guard let i = index(in: list, target: target, layer: layer) else { return nil }
        var result: [AudioFeatureBinding] = list
        result[i].isEnabled = enabled
        return result
    }

    /// `list` with `target`'s layer `from` moved to layer position `to`; the target's bindings keep the list positions
    /// they occupy. Nil when either position is out of range.
    public static func moving(in list: [AudioFeatureBinding], target: ParameterID, from: Int, to: Int) -> [AudioFeatureBinding]? {
        let positions: [Int] = list.indices.filter { (i: Int) -> Bool in list[i].target == target }
        guard positions.indices.contains(from), positions.indices.contains(to) else { return nil }
        var ordered: [AudioFeatureBinding] = positions.map { (i: Int) -> AudioFeatureBinding in list[i] }
        let moved: AudioFeatureBinding = ordered.remove(at: from)
        ordered.insert(moved, at: to)
        var result: [AudioFeatureBinding] = list
        for (k, i) in positions.enumerated() { result[i] = ordered[k] }
        return result
    }
}
