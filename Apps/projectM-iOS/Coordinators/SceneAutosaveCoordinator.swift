// SceneAutosaveCoordinator.swift — keeps the current scene committed on disk (SCN-002-R2 to R4, R7 to
// R10, R12; research SCN-002-D3, D7; contracts/scene-autosave.md A4-A6).
//
// * Launch: `restore` loads the committed scene (main, else backup, else nothing; never blocks on a bad
//   file) and returns the values the app applies before anything is shown. A restore is not an edit.
// * Edits: `startTracking` observes the app's `SceneInputs` (Observation). A change of the visual
//   commits at once; any other change is debounced (1 s quiet, 5 s maximum latency). Settings closing
//   (`commitNow`), the background (inside a background task) and terminate (synchronous) commit a
//   pending edit at once.
// * A commit captures the document on the main actor (a few struct copies), then encodes and writes
//   it on one serial utility queue, never on the frame loop. `committedRevision` is the newest edit
//   revision on disk; the DEBUG probe shows it.
// * Events (fallbacks, failed writes, dropped content) are logged with private values and kept in
//   `events`. A failed write leaves the previous files; the edit stays pending and the next edit or
//   trigger retries it.
import Diagnostics
import Foundation
import Observation
import ParameterGraph
import SceneFormat
import UIKit

@MainActor
@Observable
final class SceneAutosaveCoordinator {
    private(set) var editRevision = 0
    private(set) var committedRevision = 0
    private(set) var restoredSource: SceneAutosaveSource = .none
    private(set) var events: [SceneAutosaveEvent] = []

    var isPending: Bool { editRevision > committedRevision }

    /// The bindings the app binds to a native spectrum when it is created: the restored ones, then the
    /// last captured live ones (contract A5).
    var bindings: [AudioFeatureBinding] { carry.bindings }

    /// SCN-010: the content the current scene carries (the history captures its states over it).
    var carrySnapshot: SceneAutosaveCarry { carry }

    /// DEBUG probe value (contract A6).
    var probe: String {
        "restored=\(restoredSource.rawValue) committed=\(committedRevision) pending=\(isPending ? 1 : 0) events=\(events.count)"
    }

    @ObservationIgnored let store: SceneAutosaveStore
    @ObservationIgnored let registry: ParameterRegistry
    @ObservationIgnored private let clock: () -> Double
    @ObservationIgnored private let schedulesTimer: Bool
    @ObservationIgnored private let queue = DispatchQueue(label: "org.projectmios.scene-autosave", qos: .utility)
    @ObservationIgnored private var debouncer: SceneAutosaveDebouncer
    @ObservationIgnored private var carry = SceneAutosaveCarry.fresh()
    @ObservationIgnored private var lastInputs: SceneInputs?
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    /// Written on the queue, read after `drain()`: the newest revision written.
    @ObservationIgnored private let written = WrittenRevision()

    /// The app's current inputs (read on the main actor).
    @ObservationIgnored var inputs: () -> SceneInputs = { fatalError("SceneAutosaveCoordinator.inputs not set") }
    /// The native spectrum's live bindings, or nil when it does not exist.
    @ObservationIgnored var liveBindings: () -> [AudioFeatureBinding]? = { nil }

    init(store: SceneAutosaveStore, registry: ParameterRegistry, debouncer: SceneAutosaveDebouncer = SceneAutosaveDebouncer(),
         clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }, schedulesTimer: Bool = true) {
        self.store = store
        self.registry = registry
        self.debouncer = debouncer
        self.clock = clock
        self.schedulesTimer = schedulesTimer
    }

    /// The app's coordinator: the default folder, the app registry, and DEBUG launch arguments
    /// `-uitestSceneAutosaveQuiet <s>` / `-uitestSceneAutosaveMaxLatency <s>` (contract A6).
    static func makeDefault(defaults: UserDefaults) -> SceneAutosaveCoordinator? {
        guard let directory = try? SceneAutosaveStore.defaultDirectory(), let registry = try? SceneArchiveService.appRegistry() else {
            DiagnosticsLog.app.error("scene autosave unavailable")
            return nil
        }
        var quiet = SceneAutosaveDebouncer.defaultQuiet
        var latency = SceneAutosaveDebouncer.defaultMaximumLatency
        #if DEBUG
        if let value = defaults.string(forKey: "uitestSceneAutosaveQuiet").flatMap(Double.init) { quiet = value }
        if let value = defaults.string(forKey: "uitestSceneAutosaveMaxLatency").flatMap(Double.init) { latency = value }
        #endif
        return SceneAutosaveCoordinator(store: SceneAutosaveStore(directory: directory), registry: registry,
                                        debouncer: SceneAutosaveDebouncer(quiet: quiet, maximumLatency: latency))
    }

    // MARK: - Restore (launch)

    /// Loads the committed scene; nil when nothing valid exists (the current settings stay).
    func restore(assets availability: (any SceneAssetAvailability)?) -> SceneRestoredValues? {
        let load = store.load(registry: registry, assets: availability)
        restoredSource = load.source
        record(load.events)
        guard let document = load.document, let result = load.result else { return nil }
        carry = SceneAutosaveCarry(document: document, live: result.state)
        return SceneAutosaveCapture.restoredValues(document, live: result.state, registry: registry)
    }

    // MARK: - Held restore (PERF-010; research PERF-010-D3)

    /// After an abnormal exit: reads the committed scene without adopting it (the carry stays fresh,
    /// nothing is applied). nil when nothing valid exists. Fallback events are recorded as in `restore`.
    func holdCommittedScene(assets availability: (any SceneAssetAvailability)?) -> SceneAutosaveHeldScene? {
        let load = store.load(registry: registry, assets: availability)
        record(load.events)
        guard let document = load.document, let result = load.result else { return nil }
        return SceneAutosaveHeldScene(document: document, live: result.state, source: load.source)
    }

    /// The user chose Reopen: adopts the held scene as `restore` would have at launch and returns the
    /// values the app applies (the next commit records them).
    func reopen(_ held: SceneAutosaveHeldScene) -> SceneRestoredValues {
        restoredSource = held.source
        carry = SceneAutosaveCarry(document: held.document, live: held.live)
        return SceneAutosaveCapture.restoredValues(held.document, live: held.live, registry: registry)
    }

    /// The user chose Start fresh: commits the shown (fresh) scene at once, replacing the held one.
    func commitFreshScene() {
        noteEdit()
        commitNow()
    }

    // MARK: - Tracking and triggers

    /// Starts observing the inputs (after the restored values were applied) and the app lifecycle.
    func startTracking(observeLifecycle: Bool = true) {
        track()
        guard observeLifecycle, observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil,
                                            queue: .main) { [weak self] (_: Notification) in
            MainActor.assumeIsolated { self?.appEnteredBackground() }
        })
        observers.append(center.addObserver(forName: UIApplication.willTerminateNotification, object: nil,
                                            queue: .main) { [weak self] (_: Notification) in
            MainActor.assumeIsolated { self?.flushSynchronously() }
        })
    }

    private func track() {
        lastInputs = withObservationTracking { inputs() } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.inputsChanged() }
        }
    }

    /// An observed input changed (also called directly by tests).
    func inputsChanged() {
        let previous = lastInputs
        track()
        guard let previous, let current = lastInputs, current != previous else { return }
        noteEdit()
        if current.visual != previous.visual { commitNow() }   // A4: a visual change commits at once
    }

    /// Records an edit and arms the debounce timer.
    func noteEdit() {
        editRevision += 1
        let deadline = debouncer.edit(at: clock())
        guard schedulesTimer else { return }
        timer?.cancel()
        let delay = max(0, deadline - clock())
        timer = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.tick()
        }
    }

    /// Commits when the pending edit is due (the timer, or tests with a fake clock).
    func tick() {
        guard debouncer.isPending else { return }
        if debouncer.isDue(at: clock()) { commit(synchronously: false) } else if let deadline = debouncer.deadline, schedulesTimer {
            let delay = max(0, deadline - clock())
            timer = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self?.tick()
            }
        }
    }

    /// Catches up with an input change whose observation callback has not run yet (a trigger can
    /// arrive first, for example Settings closing right after a tap).
    private func catchUp() {
        guard let previous = lastInputs else { return }
        let current = inputs()
        guard current != previous else { return }
        lastInputs = current
        noteEdit()
    }

    /// Settings closed or the visual changed: commit a pending edit at once (asynchronous write).
    func commitNow() {
        catchUp()
        guard isPending else { return }
        commit(synchronously: false)
    }

    /// Terminate: commit a pending edit and wait for the write.
    func flushSynchronously() {
        catchUp()
        if isPending { commit(synchronously: true) } else { drain() }
    }

    private func appEnteredBackground() {
        catchUp()
        guard isPending else { return }
        if backgroundTask == .invalid {
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "SCN-002 commit scene") { [weak self] in
                MainActor.assumeIsolated { self?.endBackgroundTask() }
            }
        }
        commit(synchronously: false) { [weak self] in self?.endBackgroundTask() }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    // MARK: - Commit

    private func commit(synchronously: Bool, completion: (@MainActor @Sendable () -> Void)? = nil) {
        timer?.cancel()
        timer = nil
        debouncer.reset()
        let revision = editRevision
        if let live = liveBindings() { carry.bindings = live }   // what a recreated native spectrum gets
        let captured = SceneAutosaveCapture.document(inputs(), carry: carry, liveBindings: nil)
        record(captured.events)
        let document = captured.document
        let store = store
        let written = written
        let work: @Sendable () -> Void = {
            do throws(SceneAutosaveWriteError) {
                try store.save(document.encoded())
                written.update(revision)
            } catch {
                written.failed(error.step)
            }
            written.kept(store.takeKeptOriginals())   // SCN-013 backups of migrated originals
        }
        if synchronously {
            queue.sync(execute: work)
            collect()
            completion?()
        } else {
            queue.async { [weak self] in
                work()
                Task { @MainActor [weak self] in
                    self?.collect()
                    completion?()
                }
            }
        }
    }

    /// Publishes what the write queue finished: the committed revision and failed steps.
    private func collect() {
        let (revision, failures, kept) = written.take()
        record(kept.map { (name: String) -> SceneAutosaveEvent in .keptOriginal(name) })
        record(failures.map { (step: SceneAutosaveStep) -> SceneAutosaveEvent in .writeFailed(step.rawValue) })
        committedRevision = max(committedRevision, revision)
    }

    /// Waits for queued writes and publishes their results (terminate and tests).
    func drain() {
        queue.sync {}
        collect()
    }

    private func record(_ new: [SceneAutosaveEvent]) {
        guard !new.isEmpty else { return }
        events += new
        for event in new { DiagnosticsLog.app.info("scene autosave \(event.description, privacy: .private)") }
    }
}

/// A committed scene read at launch but not applied until the user chooses Reopen (PERF-010).
struct SceneAutosaveHeldScene: Sendable {
    let document: SceneDocument
    let live: SceneLiveState
    let source: SceneAutosaveSource
}

/// The newest revision written and the failed steps not yet reported (set on the write queue, taken
/// on the main actor).
private final class WrittenRevision: @unchecked Sendable {
    private let lock = NSLock()
    private var revision = 0
    private var failures: [SceneAutosaveStep] = []
    private var keptNames: [String] = []

    func update(_ new: Int) { lock.withLock { revision = max(revision, new) } }

    func failed(_ step: SceneAutosaveStep) { lock.withLock { failures.append(step) } }

    func kept(_ names: [String]) { lock.withLock { keptNames += names } }

    func take() -> (revision: Int, failures: [SceneAutosaveStep], kept: [String]) {
        lock.withLock {
            let taken = failures
            let names = keptNames
            failures = []
            keptNames = []
            return (revision, taken, names)
        }
    }
}
