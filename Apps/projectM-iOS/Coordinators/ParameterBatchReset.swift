// ParameterBatchReset.swift — reset selected parameters to their defaults as one undo step (UIX-010-R1 to R9;
// specs/298-uix-010-batch-parameter-reset, research UIX-010-D1 to D7, contracts/batch-reset.md B1).
//
// * `ParameterResetSelection`: the selected IDs of the parameter list's selection mode (in memory, per visit),
//   with per-group Select All and the count-bearing button labels.
// * `ParameterBatchReset.reset`: SCN-015's lock first (it refuses and announces); then SCN-010's `endCoalescing()`,
//   every selected parameter's MOD-001 declared default written through its plain UIX-003 Settings target (in
//   catalog order, skipping values already at default; MOD-017 queued changes of the selection dropped, never
//   quantized), then one `recordStep(label:)`, so one Undo restores every previous value (the SCN-008 recall path).
//   Modulation bindings are separate scene inputs and are not touched.
// Every intermediate is a named, typed value (CI's type-check budget).
import Foundation
import ParameterGraph

// MARK: - Selection (R1, R2, R8)

struct ParameterResetSelection: Equatable {
    private(set) var ids: Set<ParameterID> = []

    var count: Int { ids.count }

    func contains(_ id: ParameterID) -> Bool { ids.contains(id) }

    mutating func toggle(_ id: ParameterID) {
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
    }

    /// Selects (or deselects) every ID of `group` (a section's resettable rows).
    mutating func setAll(_ group: [ParameterID], selected: Bool) {
        if selected { ids.formUnion(group) } else { ids.subtract(group) }
    }

    /// True when `group` is non-empty and every ID in it is selected.
    func allSelected(_ group: [ParameterID]) -> Bool {
        !group.isEmpty && group.allSatisfy { (id: ParameterID) -> Bool in ids.contains(id) }
    }

    mutating func clear() { ids.removeAll() }

    /// "Reset to Defaults" with nothing selected, "Reset 3 to Defaults" otherwise.
    var buttonTitle: String { count == 0 ? "Reset to Defaults" : "Reset \(count) to Defaults" }

    /// "Reset 3 parameters to defaults", "Reset 1 parameter to defaults".
    var buttonAccessibilityLabel: String { "Reset " + ParameterBatchReset.counted(count) + " to defaults" }
}

// MARK: - Reset (R3-R7, R9)

struct ParameterBatchResetResult: Equatable {
    enum Outcome: Equatable {
        case reset
        case alreadyAtDefaults
        case refused
    }

    let outcome: Outcome
    /// The parameters written, in catalog order (empty unless `.reset`).
    let written: [ParameterID]
    /// The undo step's name ("Reset 3 Parameters"), nil when no step was recorded.
    let undoLabel: String?
    /// Shown under the list and announced ("Reset 3 parameters", "Already at defaults", the lock's refusal).
    let message: String
}

@MainActor
enum ParameterBatchReset {
    static let alreadyAtDefaults = "Already at defaults"

    /// A parameter can be selected when it has a Settings write target (R1).
    static func isResettable(_ id: ParameterID, settings: AppSettings) -> Bool {
        ParameterInspectorTargets.target(for: id, settings: settings) != nil
    }

    @discardableResult
    static func reset(_ selection: Set<ParameterID>, settings: AppSettings, history: SceneHistoryCoordinator?,
                      registry: ParameterRegistry? = ParameterInspectorCatalog.registry) -> ParameterBatchResetResult {
        if settings.sceneLock.refusesEdit() {   // R7: refused and announced by the lock
            return ParameterBatchResetResult(outcome: .refused, written: [], undoLabel: nil, message: SceneLock.refusalMessage)
        }
        let all: [ParameterDescriptor] = registry?.descriptors ?? []
        let selected: [ParameterDescriptor] = all.filter { (d: ParameterDescriptor) -> Bool in selection.contains(d.id) }
        settings.parameterQuantizer.cancelQueued(selected.map(\.id))   // R9
        history?.endCoalescing()   // earlier edits stay their own steps (R4)
        var written: [ParameterDescriptor] = []
        for descriptor in selected {
            guard let target = ParameterInspectorTargets.target(for: descriptor.id, settings: settings) else { continue }
            if target.get() == descriptor.defaultValue { continue }   // already at default (R3, D3)
            target.set(descriptor.defaultValue)
            written.append(descriptor)
        }
        guard !written.isEmpty else {   // R6
            return ParameterBatchResetResult(outcome: .alreadyAtDefaults, written: [], undoLabel: nil, message: alreadyAtDefaults)
        }
        let label: String = undoLabel(written)
        history?.recordStep(label: label)   // R4: exactly one step
        let ids: [ParameterID] = written.map(\.id)
        return ParameterBatchResetResult(outcome: .reset, written: ids, undoLabel: label, message: announcement(written))
    }

    /// "Reset Intensity" for one, "Reset 3 Parameters" for several (the undo step's name).
    nonisolated static func undoLabel(_ written: [ParameterDescriptor]) -> String {
        if written.count == 1, let only = written.first { return "Reset " + only.displayName }
        return "Reset \(written.count) Parameters"
    }

    /// "Reset Intensity" for one, "Reset 3 parameters" for several (announced on the parameter lane).
    nonisolated static func announcement(_ written: [ParameterDescriptor]) -> String {
        if written.count == 1, let only = written.first { return "Reset " + only.displayName }
        return "Reset " + counted(written.count)
    }

    /// "1 parameter", "3 parameters".
    nonisolated static func counted(_ count: Int) -> String {
        count == 1 ? "1 parameter" : "\(count) parameters"
    }
}
