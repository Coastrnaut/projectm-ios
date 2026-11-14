// SceneCompareCoordinator.swift — SCN-009: A/B compare of two scene states (specs/222-scn-009-scene-ab-compare;
// R2 to R11; research SCN-009-D1 to D8; contract C1).
//
// * A session holds the pre-Compare inputs and app-held parameter values, side A (the current scene or a snapshot)
//   and side B (a snapshot). A side's values are the pre-Compare values overlaid with the snapshot's usable values
//   (`SceneSnapshotRecallPlan`), so switching always reaches exactly the same two states (D4).
// * Start flushes a pending autosave edit and closes history coalescing, then suspends SCN-002's autosave and
//   SCN-010's history: nothing reaches the scene file, its backup, the snapshot list or the undo stack (D1).
// * A switch writes only differing values through the snapshot coordinator's Settings targets: a cut, never
//   crossfaded or quantized (D3). Keep commits once and records one undo step; Cancel restores the pre-Compare scene
//   through the history's apply path (D5); a history restart (cue, Reopen, media) abandons Compare (D7).
// * SCN-015: start, switch and Keep are refused while locked; Cancel always works (D6).
// * Messages go to `status` and to the announcer's library lane (ACC-004, D8).
import Foundation
import Observation
import ParameterGraph
import SceneFormat

/// What a side shows.
enum SceneCompareChoice: Hashable, Sendable {
    /// The scene as it was when Compare started (side A only).
    case current
    /// The snapshot at this index of the current scene's list.
    case snapshot(Int)
}

enum SceneCompareSide: String, Hashable, Sendable {
    case a = "A"
    case b = "B"

    var other: SceneCompareSide { self == .a ? .b : .a }
}

/// One Compare session (data-model.md).
struct SceneCompareSession: Equatable {
    let baseline: SceneInputs
    let baselineValues: [ParameterID: ParameterValue]
    let a: SceneCompareChoice
    let b: SceneCompareChoice
    let aName: String
    let bName: String
    let aValues: [ParameterID: ParameterValue]
    let bValues: [ParameterID: ParameterValue]
    var shown: SceneCompareSide

    func name(_ side: SceneCompareSide) -> String { side == .a ? aName : bName }

    func values(_ side: SceneCompareSide) -> [ParameterID: ParameterValue] { side == .a ? aValues : bValues }

    /// "B, Snapshot 2" (the bar's accessibility value and the switch announcement).
    func spoken(_ side: SceneCompareSide) -> String { side.rawValue + ", " + name(side) }
}

@MainActor
@Observable
final class SceneCompareCoordinator {
    static let currentName = "Current scene"
    static let title = "Comparing A/B"
    static let cancelledMessage = "Compare cancelled"
    static let endedMessage = "Compare ended"
    static let sameStateRefusal = "Choose two different states."
    static let unusableRefusal = "That snapshot can't be used."
    static let unavailableRefusal = "Compare isn't available."

    private(set) var session: SceneCompareSession?
    /// The last message ("Comparing A/B: A, S1", "Kept S2", a refusal).
    private(set) var status: String?
    /// The bar's "Finish Compare?" question is shown.
    var isConfirmingFinish = false

    var isActive: Bool { session != nil }

    @ObservationIgnored weak var snapshots: SceneSnapshotCoordinator?
    @ObservationIgnored weak var autosave: SceneAutosaveCoordinator?
    @ObservationIgnored weak var history: SceneHistoryCoordinator?
    @ObservationIgnored var lock: SceneLock?
    /// The app's live inputs (nil: Compare unavailable).
    @ObservationIgnored var inputs: () -> SceneInputs? = { () -> SceneInputs? in nil }
    /// Sets a whole scene state through the Settings path (SCN-010's apply).
    @ObservationIgnored var restore: (SceneInputs) -> Void = { (_: SceneInputs) -> Void in }
    /// ACC-004: the library lane.
    @ObservationIgnored var announce: (String) -> Void = { (_: String) -> Void in }
    /// Compare started (the app closes Settings so the output is visible).
    @ObservationIgnored var onStarted: () -> Void = { () -> Void in }

    // MARK: - Start (R2)

    /// nil when Compare started; else the refusal (also in `status` and announced).
    @discardableResult
    func start(a: SceneCompareChoice, b: Int) -> String? {
        guard session == nil, let snapshots, let registry = snapshots.registry, inputs() != nil else {
            return refuse(Self.unavailableRefusal)
        }
        if a == .snapshot(b) { return refuse(Self.sameStateRefusal) }
        if lock?.refusesEdit() == true {   // SCN-015 announces the refusal itself
            status = SceneLock.refusalMessage
            return SceneLock.refusalMessage
        }
        snapshots.reload()
        autosave?.flushSynchronously()   // D2: the files hold the pre-Compare scene
        history?.endCoalescing()
        guard let baseline = inputs() else { return refuse(Self.unavailableRefusal) }
        let base: [ParameterID: ParameterValue] = currentValues(snapshots)
        guard let sideA = side(a, base: base, snapshots: snapshots, registry: registry),
              let sideB = side(.snapshot(b), base: base, snapshots: snapshots, registry: registry) else {
            return refuse(Self.unusableRefusal)
        }
        autosave?.suspend()
        history?.suspend()
        let started = SceneCompareSession(baseline: baseline, baselineValues: base, a: a, b: .snapshot(b),
                                          aName: sideA.name, bName: sideB.name, aValues: sideA.values,
                                          bValues: sideB.values, shown: .a)
        session = started
        apply(started.aValues)
        report(Self.title + ": " + started.spoken(.a))
        onStarted()
        return nil
    }

    private func currentValues(_ snapshots: SceneSnapshotCoordinator) -> [ParameterID: ParameterValue] {
        var values: [ParameterID: ParameterValue] = [:]
        for id in snapshots.parameterIDs {
            if let value = snapshots.read(id) { values[id] = value }
        }
        return values
    }

    /// D4: the pre-Compare values overlaid with the snapshot's usable values.
    private func side(_ choice: SceneCompareChoice, base: [ParameterID: ParameterValue], snapshots: SceneSnapshotCoordinator,
                      registry: ParameterRegistry) -> (name: String, values: [ParameterID: ParameterValue])? {
        guard case let .snapshot(index) = choice else { return (Self.currentName, base) }
        let read: [SceneSnapshot?] = SceneSnapshotEntry.read(snapshots.entries).snapshots
        guard index >= 0, index < read.count, let snapshot = read[index] else { return nil }
        let settable: Set<ParameterID> = Set(snapshots.parameterIDs)
        let plan = SceneSnapshotRecallPlan(snapshot, registry: registry,
                                           settable: { (id: ParameterID) -> Bool in settable.contains(id) })
        var values: [ParameterID: ParameterValue] = base
        for item in plan.writes { values[item.id] = item.value }
        return (snapshot.name, values)
    }

    // MARK: - Switch (R3)

    /// Shows `side`: writes only the values that differ, at once. False when not comparing or refused (locked).
    @discardableResult
    func show(_ side: SceneCompareSide) -> Bool {
        guard var current = session else { return false }
        guard current.shown != side else { return true }   // the shown side: nothing to do
        if lock?.refusesEdit() == true {
            status = SceneLock.refusalMessage
            return false
        }
        current.shown = side
        session = current
        apply(current.values(side))
        report(current.spoken(side))
        return true
    }

    func toggle() {
        guard let current = session else { return }
        show(current.shown.other)
    }

    private func apply(_ values: [ParameterID: ParameterValue]) {
        guard let snapshots else { return }
        for id in snapshots.parameterIDs {
            guard let value = values[id], snapshots.read(id) != value else { continue }
            _ = snapshots.write(id, value)
        }
    }

    // MARK: - Leave (R5, R6, R11)

    /// Keeps `side` as the live scene, commits it once and records one undo step. False when refused (locked).
    @discardableResult
    func keep(_ side: SceneCompareSide) -> Bool {
        guard let current = session else { return false }
        if lock?.refusesEdit() == true {
            status = SceneLock.refusalMessage
            return false
        }
        apply(current.values(side))
        end(current)
        autosave?.commitNow()   // nothing pending when the side equals the pre-Compare scene
        history?.recordStep(label: "Keep " + current.name(side))
        report("Kept " + current.name(side))
        return true
    }

    /// Restores the pre-Compare scene and ends Compare; nothing is written when nothing else changed.
    func cancel() {
        guard let current = session else { return }
        restore(current.baseline)
        if lock?.isLocked != true { apply(current.baselineValues) }   // the targets refuse while locked
        end(current)
        report(Self.cancelledMessage)
    }

    /// A cue, Reopen or media replacement restarted the history: Compare ends without restoring (R11).
    func abandon() {
        guard let current = session else { return }
        end(current)
        report(Self.endedMessage)
    }

    private func end(_ current: SceneCompareSession) {
        session = nil
        isConfirmingFinish = false
        history?.resume()
        autosave?.resume(from: current.baseline)
    }

    private func refuse(_ message: String) -> String {
        report(message)
        return message
    }

    private func report(_ message: String) {
        status = message
        announce(message)
    }
}

// MARK: - Wiring (shared by the app and SceneCompareAcceptanceTests)

extension SceneCompareCoordinator {
    func connect(snapshots: SceneSnapshotCoordinator, autosave: SceneAutosaveCoordinator?, history: SceneHistoryCoordinator,
                 lock: SceneLock?, inputs: @escaping () -> SceneInputs?, announce: @escaping (String) -> Void) {
        self.snapshots = snapshots
        self.autosave = autosave
        self.history = history
        self.lock = lock
        self.inputs = inputs
        self.announce = announce
        restore = { [weak history] (state: SceneInputs) -> Void in history?.apply(state) }
        snapshots.compare = self
        snapshots.isComparing = { [weak self] () -> Bool in self?.isActive ?? false }
        history.onRestartWhileSuspended = { [weak self] () -> Void in self?.abandon() }
    }
}
