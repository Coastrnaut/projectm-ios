// MacroCoordinator.swift — MOD-010: the current scene's parameter macros in the app (MOD-010-R6, R9, R10;
// specs/170-mod-010-parameter-macro, research MOD-010-D2, D4; contract M4).
//
// * `entries`: the scene's `macros` list as stored (nil: none). It is part of `SceneInputs`, so SCN-002 autosaves it
//   and SCN-010 undoes it; a restore (launch, Reopen, undo) hands it back with `restore`, which never applies it.
// * `setValue(_:at:)` rewrites only that entry's `value` and writes each target's evaluated value as a base value
//   through UIX-003's `ParameterInspectorTargets` (the Settings path), so bindings, LFOs and ACC-012's render clamp
//   still apply on top. Targets the macro skips (MOD-010-R5) and registered parameters without an app control are
//   reported in `lastReport` and logged once per change (count public, IDs private).
// * No UserDefaults key: macros live in the scene only.
// Every intermediate is a named, typed value (CI's type-check budget).
import Foundation
import Observation
import os
import ParameterGraph
import SceneFormat

/// What one macro change did.
struct MacroChangeReport: Equatable {
    var applied: [ParameterID] = []
    /// Skipped targets with a readable reason.
    var skipped: [MacroSkippedTarget] = []
}

struct MacroSkippedTarget: Equatable {
    let parameter: ParameterID
    let reason: String
}

@MainActor
@Observable
final class MacroCoordinator {
    static let noAppControl = "this version has no control that sets this parameter"
    /// The target row's value when the app cannot write the parameter.
    static let unavailableValue = "not available"

    /// The scene's macro list as stored (nil: the scene has none).
    private(set) var entries: [SceneMacroEntry]?
    /// The live macros by position (nil: unusable entry), with their usable targets.
    private(set) var macros: [ParameterMacro?] = []
    private(set) var lastReport = MacroChangeReport()

    @ObservationIgnored let registry: ParameterRegistry?
    @ObservationIgnored private let target: @MainActor (ParameterID) -> ParameterInspectorTarget?
    /// SCN-015-R3: the scene lock (nil: never locked, e.g. tests of macros alone).
    @ObservationIgnored var sceneLock: SceneLock?
    private static let log = Logger(subsystem: "org.projectmios.ProjectMiOS", category: "macros")

    init(registry: ParameterRegistry?, target: @escaping @MainActor (ParameterID) -> ParameterInspectorTarget?) {
        self.registry = registry
        self.target = target
    }

    /// The app's coordinator: the visual catalog and the Settings write path.
    static func makeDefault(settings: AppSettings) -> MacroCoordinator {
        let coordinator = MacroCoordinator(registry: ParameterInspectorCatalog.registry) { (id: ParameterID) -> ParameterInspectorTarget? in
            ParameterInspectorTargets.target(for: id, settings: settings)
        }
        coordinator.sceneLock = settings.sceneLock   // SCN-015
        return coordinator
    }

    /// The usable macros with their positions (what Settings › Macros lists).
    var live: [(index: Int, macro: ParameterMacro)] {
        var result: [(index: Int, macro: ParameterMacro)] = []
        for (index, macro) in macros.enumerated() {
            if let macro { result.append((index, macro)) }
        }
        return result
    }

    var isEmpty: Bool { live.isEmpty }

    /// A scene's list (launch restore, Reopen, undo/redo): replaces the macros without applying them.
    func restore(_ entries: [SceneMacroEntry]?) {
        guard entries != self.entries else { return }
        self.entries = entries
        guard let registry, let entries else {
            macros = []
            return
        }
        macros = SceneMacroEntry.read(entries, registry: registry).macros
    }

    /// Sets macro `index` to `value` (limited to 0…1) and writes its targets; nil when there is no such macro.
    @discardableResult
    func setValue(_ value: Double, at index: Int) -> MacroChangeReport? {
        guard let registry, var stored = entries, index >= 0, index < macros.count, index < stored.count,
              var macro = macros[index] else { return nil }
        if sceneLock?.refusesEdit() == true { return nil }   // SCN-015-R3: the value stays as stored
        let m: Double = LinearMapping.clampedPosition(value)
        macro.value = m
        stored[index] = stored[index].settingValue(m)
        macros[index] = macro
        entries = stored
        let evaluation: MacroEvaluation = macro.evaluate(at: m, registry: registry)
        var report = MacroChangeReport()
        for skip in evaluation.skipped {
            report.skipped.append(MacroSkippedTarget(parameter: skip.parameter, reason: skip.problem.description))
        }
        for assignment in evaluation.assignments {
            guard let write = target(assignment.parameter) else {
                report.skipped.append(MacroSkippedTarget(parameter: assignment.parameter, reason: Self.noAppControl))
                continue
            }
            if write.get() != assignment.value { write.set(assignment.value) }
            report.applied.append(assignment.parameter)
        }
        if !report.skipped.isEmpty && report.skipped != lastReport.skipped {
            let count: Int = report.skipped.count
            let ids: String = report.skipped.map(\.parameter.rawValue).joined(separator: ", ")
            Self.log.notice("Macro \(index, privacy: .public): \(count, privacy: .public) targets skipped: \(ids, privacy: .private)")
        }
        lastReport = report
        return report
    }
}
