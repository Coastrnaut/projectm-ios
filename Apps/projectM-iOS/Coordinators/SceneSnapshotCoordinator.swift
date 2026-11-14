// SceneSnapshotCoordinator.swift — SCN-008: named parameter snapshots of the current scene (SCN-008-R5 to R9;
// specs/169-scn-008-scene-snapshots, research SCN-008-D4 to D6, contract N6, N7).
//
// * The list is the current scene's `snapshots` (SCN-002's carry). `entries` mirrors it and reloads when the
//   Settings section appears; Save, Rename and Delete replace it and commit the scene at once (not undo steps).
// * Save captures the current manual values of the app-held registry parameters (`ParameterInspectorTargets`).
// * Recall validates the snapshot against the registry (`SceneSnapshotRecallPlan`), writes only values that
//   differ through the same targets Settings writes, and records one SCN-010 step "Recall <name>". It never
//   touches media, the visual, the preset, the effect chain, text or layers: it can only reach `write`.
// * Messages go to `status` (shown under the list) and to the announcer's library lane (ACC-004).
import Foundation
import Observation
import ParameterGraph
import SceneFormat

/// One row of the Snapshots list.
struct SceneSnapshotRow: Equatable, Identifiable {
    let index: Int
    let name: String
    /// nil for an entry that cannot be used (kept from a newer app or a damaged file).
    let valueCount: Int?
    var id: Int { index }

    var isUsable: Bool { valueCount != nil }

    /// "7 values", "1 value", "Can't be used".
    var summary: String {
        guard let count = valueCount else { return "Can't be used" }
        return count == 1 ? "1 value" : "\(count) values"
    }
}

/// What a recall did (tests and the status line).
struct SceneSnapshotRecallResult: Equatable {
    var written: [ParameterID] = []
    var skipped: [SceneSnapshotRecallPlan.Skip] = []
    var message: String = ""
}

@MainActor
@Observable
final class SceneSnapshotCoordinator {
    private(set) var entries: [SceneSnapshotEntry] = []
    /// The last action's message ("Saved Snapshot 1", "Recalled S1; 1 value skipped: …").
    private(set) var status: String?

    @ObservationIgnored var registry: ParameterRegistry?
    /// The parameters a snapshot captures and recall can set.
    @ObservationIgnored let parameterIDs: [ParameterID]
    /// The current scene's stored list (SCN-002).
    @ObservationIgnored var load: () -> [SceneSnapshotEntry] = { () -> [SceneSnapshotEntry] in [] }
    /// Replaces the current scene's list and commits it.
    @ObservationIgnored var store: ([SceneSnapshotEntry]) -> Void = { (_: [SceneSnapshotEntry]) -> Void in }
    /// The current manual value of a parameter (nil: no app control).
    @ObservationIgnored var read: (ParameterID) -> ParameterValue? = { (_: ParameterID) -> ParameterValue? in nil }
    /// Writes a value through the Settings path; false when the app has no control for it.
    @ObservationIgnored var write: (ParameterID, ParameterValue) -> Bool = { (_: ParameterID, _: ParameterValue) -> Bool in false }
    /// SCN-010 (nil in previews).
    @ObservationIgnored var history: SceneHistoryCoordinator?
    /// ACC-004: the library lane.
    @ObservationIgnored var announce: (String) -> Void = { (_: String) -> Void in }
    /// SCN-015-R3: save, rename, delete and recall are refused while the scene is locked (nil: never locked).
    @ObservationIgnored var sceneLock: SceneLock?

    init(registry: ParameterRegistry? = ParameterInspectorCatalog.registry,
         parameterIDs: [ParameterID] = ParameterInspectorTargets.inspectableIDs) {
        self.registry = registry
        self.parameterIDs = parameterIDs
    }

    var rows: [SceneSnapshotRow] {
        let read: [SceneSnapshot?] = SceneSnapshotEntry.read(entries).snapshots
        return entries.indices.map { (i: Int) -> SceneSnapshotRow in
            let snapshot: SceneSnapshot? = i < read.count ? read[i] : nil
            let name: String = snapshot?.name ?? entries[i].name ?? "Snapshot \(i + 1)"
            return SceneSnapshotRow(index: i, name: name, valueCount: snapshot?.values.count)
        }
    }

    var canSave: Bool { entries.count < SceneLimits.maximumSnapshots }

    /// Reads the current scene's list again (the Settings section appeared).
    func reload() {
        entries = load()
    }

    // MARK: - Editing

    /// SCN-008-R5: the current values under the next free "Snapshot N" name.
    @discardableResult
    func save() -> Bool {
        if refusedByLock() { return false }
        reload()
        var values: [ParameterID: ParameterValue] = [:]
        for id in parameterIDs {
            if let value = read(id) { values[id] = value }
        }
        let name: String = SceneSnapshotEditing.nextDefaultName(in: entries)
        do {
            apply(try SceneSnapshotEditing.adding(SceneSnapshot(name: name, values: values), to: entries))
            report("Saved \(name)")
            return true
        } catch {
            report(error.description)
            return false
        }
    }

    /// SCN-008-R8: nil when renamed, else the refusal (the name is unchanged).
    @discardableResult
    func rename(at index: Int, to name: String) -> String? {
        if refusedByLock() { return SceneLock.refusalMessage }
        do {
            let updated: [SceneSnapshotEntry] = try SceneSnapshotEditing.renaming(at: index, to: name, in: entries)
            apply(updated)
            report("Renamed to \(updated[index].name ?? name)")
            return nil
        } catch {
            report(error.description)
            return error.description
        }
    }

    func delete(at index: Int) {
        if refusedByLock() { return }
        let name: String? = rows.first { (r: SceneSnapshotRow) -> Bool in r.index == index }?.name
        do {
            apply(try SceneSnapshotEditing.removing(at: index, from: entries))
            report("Deleted \(name ?? "snapshot")")
        } catch {
            report(error.description)
        }
    }

    /// SCN-015: the lock announces the refusal itself; the row's status shows it.
    private func refusedByLock() -> Bool {
        guard sceneLock?.refusesEdit() == true else { return false }
        status = SceneLock.refusalMessage
        return true
    }

    private func apply(_ updated: [SceneSnapshotEntry]) {
        entries = updated
        store(updated)
    }

    // MARK: - Recall (SCN-008-R6, R7)

    @discardableResult
    func recall(at index: Int) -> SceneSnapshotRecallResult {
        if refusedByLock() { return SceneSnapshotRecallResult(message: SceneLock.refusalMessage) }
        let read: [SceneSnapshot?] = SceneSnapshotEntry.read(entries).snapshots
        guard index < read.count, let snapshot = read[index], let registry else {
            let message = "That snapshot can't be used."
            report(message)
            return SceneSnapshotRecallResult(message: message)
        }
        let settable: Set<ParameterID> = Set(parameterIDs)
        let plan = SceneSnapshotRecallPlan(snapshot, registry: registry,
                                           settable: { (id: ParameterID) -> Bool in settable.contains(id) })
        var result = SceneSnapshotRecallResult(skipped: plan.skipped)
        history?.endCoalescing()   // earlier edits stay their own steps
        for item in plan.writes where self.read(item.id) != item.value {
            if write(item.id, item.value) {
                result.written.append(item.id)
            } else {
                result.skipped.append(SceneSnapshotRecallPlan.Skip(id: item.id, reason: .notSettable))
            }
        }
        if !result.written.isEmpty { history?.recordStep(label: "Recall \(snapshot.name)") }
        result.message = Self.message(name: snapshot.name, result: result)
        report(result.message)
        return result
    }

    static func message(name: String, result: SceneSnapshotRecallResult) -> String {
        let skipped: [SceneSnapshotRecallPlan.Skip] = result.skipped
        guard !skipped.isEmpty else {
            return result.written.isEmpty ? "\(name) is already applied" : "Recalled \(name)"
        }
        let count: String = skipped.count == 1 ? "1 value skipped" : "\(skipped.count) values skipped"
        let ids: String = skipped.map { (s: SceneSnapshotRecallPlan.Skip) -> String in s.id.rawValue }.joined(separator: ", ")
        let head: String = result.written.isEmpty ? "Nothing recalled from \(name)" : "Recalled \(name)"
        return head + "; " + count + ": " + ids
    }

    private func report(_ message: String) {
        status = message
        announce(message)
    }
}
