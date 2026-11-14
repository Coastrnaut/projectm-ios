// ModulationMatrixCoordinator.swift — MOD-012: Settings › Modulation (MOD-012-R1 to R8; research MOD-012-D5;
// contract specs/189-mod-012-modulation-matrix/contracts/modulation-matrix.md M2, M4).
//
// * `routes` mirrors the current scene's binding list (the native spectrum's modulator while one exists, else the
//   autosave carry). It is observed: `SceneInputs.bindings` reads it, so SCN-002 saves every edit and SCN-010 records
//   each one as its own undo step ("Turn Off Kick → Glow Intensity", "Reorder Glow Intensity").
// * An edit goes through `store` (AppCoordinator: in place on the host, signals kept, and into the carry), then the
//   mirror refreshes and `didEdit` closes the undo step. Undo and redo hand a whole list to `restore`.
// * No create or delete (MOD-012-R10, research MOD-012-D6): routes come with scenes.
import Foundation
import Observation
import ParameterGraph

/// One matrix edit (contract M2).
enum ModulationRouteEdit: Equatable {
    case setEnabled(Bool, target: ParameterID, layer: Int)
    case move(target: ParameterID, from: Int, to: Int)
    case replace([AudioFeatureBinding])

    /// The list after the edit, or nil when it is refused.
    func applied(to list: [AudioFeatureBinding]) -> [AudioFeatureBinding]? {
        switch self {
        case let .setEnabled(enabled, target, layer):
            return ModulationRouteList.settingEnabled(enabled, in: list, target: target, layer: layer)
        case let .move(target, from, to):
            return ModulationRouteList.moving(in: list, target: target, from: from, to: to)
        case let .replace(new):
            return new
        }
    }
}

@MainActor
@Observable
final class ModulationMatrixCoordinator {
    /// The current scene's routes, in list order (observed by `SceneInputs`).
    private(set) var routes: [AudioFeatureBinding] = []

    /// The live list (host modulator, else the carried list).
    @ObservationIgnored var live: @MainActor () -> [AudioFeatureBinding] = { () -> [AudioFeatureBinding] in [] }
    /// Applies an edit to the live list; false when refused (nothing changed).
    @ObservationIgnored var store: @MainActor (ModulationRouteEdit) -> Bool = { (_: ModulationRouteEdit) -> Bool in false }
    /// Closes the undo step after an edit (SCN-010 `endCoalescing`).
    @ObservationIgnored var didEdit: @MainActor () -> Void = { () -> Void in }

    /// Destinations in first-appearance order, layers in fold order (MOD-012-R1).
    var groups: [ModulationRouteGroup] { ModulationRouteList.groups(routes) }

    /// "3 routes", "1 route", "No routes".
    var countText: String {
        switch routes.count {
        case 0: return "No routes"
        case 1: return "1 route"
        default: return "\(routes.count) routes"
        }
    }

    /// Re-reads the live list (after a restore, a native spectrum's creation, Reopen or Start fresh).
    func refresh() {
        let now: [AudioFeatureBinding] = live()
        if now != routes { routes = now }
    }

    /// MOD-012-R3: one layer on or off; one undo step.
    func setEnabled(_ enabled: Bool, target: ParameterID, layer: Int) {
        perform(.setEnabled(enabled, target: target, layer: layer))
    }

    /// MOD-012-R6: one layer moved within its destination; one undo step.
    func move(target: ParameterID, from: Int, to: Int) {
        guard from != to else { return }
        perform(.move(target: target, from: from, to: to))
    }

    /// SwiftUI `onMove` within one destination's section.
    func move(target: ParameterID, fromOffsets: IndexSet, toOffset: Int) {
        guard fromOffsets.count == 1, let from = fromOffsets.first else { return }
        let to: Int = toOffset > from ? toOffset - 1 : toOffset
        move(target: target, from: from, to: to)
    }

    /// SCN-010 undo/redo: sets the list a history state recorded (nil: the state does not track routes).
    func restore(_ list: [AudioFeatureBinding]?) {
        if let list, list != live() { _ = store(.replace(list)) }
        refresh()
    }

    private func perform(_ edit: ModulationRouteEdit) {
        guard store(edit) else { return refresh() }
        refresh()
        didEdit()
    }
}

/// MOD-012-R8 (contract M4): the undo step's name for a change of the route list; nil when it did not change.
@MainActor
enum ModulationHistoryEdit {
    static func describe(from old: [AudioFeatureBinding]?, to new: [AudioFeatureBinding]?) -> (label: String, key: String?)? {
        guard let old, let new, old != new else { return old == new ? nil : ("Modulation", nil) }
        if old.count == new.count {
            let changed: [Int] = old.indices.filter { (i: Int) -> Bool in old[i] != new[i] }
            if changed.count == 1, let i = changed.first {
                var flipped: AudioFeatureBinding = old[i]
                flipped.isEnabled = new[i].isEnabled
                if flipped == new[i] {
                    let verb: String = new[i].isEnabled ? "Turn On " : "Turn Off "
                    return (verb + ModulationRouteText.routeTitle(new[i]), nil)
                }
            }
            let targets: Set<ParameterID> = Set(changed.map { (i: Int) -> ParameterID in new[i].target })
            if targets.count == 1, let target = targets.first, Set(old.map(\.target)) == Set(new.map(\.target)) {
                return ("Reorder " + ModulationRouteText.destinationName(target), nil)
            }
        }
        return ("Modulation", nil)
    }
}

/// The matrix's names for people.
enum ModulationRouteText {
    /// "Glow Intensity", "Circular Spectrum Gap"; the raw ID when the catalog does not know it.
    static func destinationName(_ id: ParameterID) -> String {
        guard let descriptor = ParameterInspectorCatalog.descriptor(id) else { return id.rawValue }
        let name: String = descriptor.displayName.components(separatedBy: " (").first ?? descriptor.displayName
        return descriptor.group.displayName + " " + name
    }

    /// "Kick → Glow Intensity".
    static func routeTitle(_ binding: AudioFeatureBinding) -> String {
        binding.source.inspectorName + " → " + destinationName(binding.target)
    }

    /// "replace 60%…60% · linear · no smoothing" (mix, range, curve, envelope).
    static func summary(_ binding: AudioFeatureBinding) -> String {
        let range: String = rangeText(binding)
        return binding.mixMode.rawValue + " " + range + " · " + curveText(binding.curve) + " · " + envelopeText(binding.envelope)
    }

    static func rangeText(_ binding: AudioFeatureBinding) -> String {
        guard let descriptor = ParameterInspectorCatalog.descriptor(binding.target) else {
            return String(format: "%.3g…%.3g", binding.outputStart, binding.outputEnd)
        }
        let full: String = ParameterModulationReader.describe(binding, descriptor: descriptor)
        let afterArrow: Substring = full.split(separator: "→", maxSplits: 1).last ?? Substring(full)
        let range: String = afterArrow.split(separator: "(").first.map(String.init) ?? String(afterArrow)
        return range.trimmingCharacters(in: .whitespaces)
    }

    static func curveText(_ curve: MappingCurve) -> String { curve == .linear ? "linear" : curve.kindName }

    static func envelopeText(_ envelope: AudioFeatureEnvelope) -> String {
        guard envelope != .none else { return "no smoothing" }
        return String(format: "attack %.2f s, release %.2f s", envelope.attackSeconds, envelope.releaseSeconds)
    }
}
