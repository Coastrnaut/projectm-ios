// ParameterQuantizer.swift — MOD-017: discrete parameter changes on beat, bar or cue boundaries in the app
// (specs/206-mod-017-quantized-changes; R1 to R10; research MOD-017-D3 to D8; contract Q2).
//
// * Owns PerformanceControl's `QuantizedChangeQueue` and the mode (`settings.modulation.quantize`, absent = Off).
//   Owned by `AppSettings` (like SCN-015's lock), so every holder of the settings reaches the same queue.
// * The beat grid is SHOW-011's tempo snapshot and the clock the monotonic analysis clock, both injected
//   (`connect`), so tests drive `tick(at:)` with synthetic times and turn the wake-ups off.
// * One wake-up task sleeps until the earliest boundary while anything timed is queued (D6); none otherwise.
// * Applying goes through SCN-015's guarded Settings target: a lock at the boundary refuses (and announces) and
//   the change is dropped (D7). Announcements go to the `.parameter` lane (ACC-004) through `announce`.
// * `ParameterInspectorTargets.quantizedTarget(for:settings:)` routes discrete edits (inspector, shelf, macros)
//   here; continuous parameters and every recall path stay immediate (D8).
import AudioCore
import Foundation
import Observation
import ParameterGraph
import PerformanceControl

@MainActor
@Observable
final class ParameterQuantizer {
    static let key = "settings.modulation.quantize"
    static let clearedAnnouncement = "Queued changes cleared"

    private(set) var queue = QuantizedChangeQueue<ParameterID, ParameterValue>()
    /// Changes applied at a boundary (tests and DEBUG probes).
    private(set) var appliedAtBoundary = 0

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored var clock: () -> UInt64 = { () -> UInt64 in MonotonicClock.nowNanoseconds() }
    @ObservationIgnored var tempo: () -> TempoSnapshot = { () -> TempoSnapshot in .none }
    @ObservationIgnored var hasCues: () -> Bool = { () -> Bool in false }
    @ObservationIgnored var isLocked: () -> Bool = { () -> Bool in false }
    @ObservationIgnored var announce: (String) -> Void = { (_: String) -> Void in }
    /// The guarded write of a queued change at its boundary.
    @ObservationIgnored var apply: (ParameterID, ParameterValue) -> Void = { (_: ParameterID, _: ParameterValue) -> Void in }
    /// False in tests: they call `tick(at:)` themselves.
    @ObservationIgnored var schedulesWakeUps = true
    @ObservationIgnored private var wakeTask: Task<Void, Never>?

    init(defaults: UserDefaults) {
        self.defaults = defaults
        let stored: QuantizeMode = defaults.string(forKey: Self.key).flatMap(QuantizeMode.init(rawValue:)) ?? .off
        queue = QuantizedChangeQueue(mode: stored)
    }

    isolated deinit { wakeTask?.cancel() }

    // MARK: - Mode (R1, R8)

    var mode: QuantizeMode {
        get { queue.mode }
        set { setMode(newValue) }
    }

    private func setMode(_ newMode: QuantizeMode) {
        let dropped: Int = queue.setMode(newMode)
        if newMode == .off { defaults.removeObject(forKey: Self.key) } else { defaults.set(newMode.rawValue, forKey: Self.key) }
        if dropped > 0 { announce(Self.clearedAnnouncement) }
        reschedule()
    }

    static func title(_ mode: QuantizeMode) -> String {
        switch mode {
        case .off: return "Off"
        case .beat: return "Beat"
        case .bar: return "Bar"
        case .cue: return "Cue"
        }
    }

    // MARK: - Requests (R4, R6)

    func pendingValue(for id: ParameterID) -> ParameterValue? { queue.pendingValue(for: id) }

    func isQueued(_ id: ParameterID) -> Bool { queue.boundary(for: id) != nil }

    /// A discrete edit of `id`. `current` is the applied value; `applyNow` writes it at once when nothing waits.
    func request(_ id: ParameterID, value: ParameterValue, current: ParameterValue,
                 applyNow: (ParameterValue) -> Void) {
        let result: QuantizeRequestResult = queue.request(id, value: value, current: current, at: clock(),
                                                          tempo: tempo(), hasCues: hasCues())
        let name: String = Self.name(id)
        switch result {
        case let .applyNow(reason):
            applyNow(value)
            if let suffix = Self.fallbackSuffix(reason) { announce(name + " " + Self.spoken(value, id: id) + suffix) }
        case .queued:
            announce(name + " queued for the next " + boundaryWord)
        case .cancelled:
            announce(name + " change cancelled")
        case .unchanged:
            break
        }
        reschedule()
    }

    // MARK: - Boundaries (R5, R7, R8)

    /// Applies every change whose beat or bar boundary is at or before `time`.
    func tick(at time: UInt64) {
        applyChanges(queue.takeDue(at: time))
        reschedule()
    }

    /// The show applied a cue's scene: Cue mode applies the queue on top of it, Beat/Bar mode clears it.
    func cueApplied() {
        let step: (apply: [QueuedChange<ParameterID, ParameterValue>], dropped: Int) = queue.cueStepped()
        applyChanges(step.apply)
        if step.dropped > 0 { announce(Self.clearedAnnouncement) }
        reschedule()
    }

    private func applyChanges(_ changes: [QueuedChange<ParameterID, ParameterValue>]) {
        for change in changes {
            if isLocked() {   // SCN-015: the guarded write refuses and announces; the change is dropped
                apply(change.key, change.value)
                continue
            }
            apply(change.key, change.value)
            appliedAtBoundary += 1
            announce(Self.name(change.key) + " " + Self.spoken(change.value, id: change.key) + ", applied")
        }
    }

    private func reschedule() {
        wakeTask?.cancel()
        wakeTask = nil
        guard schedulesWakeUps, let deadline = queue.nextDeadline else { return }
        let now: UInt64 = clock()
        let delay: UInt64 = deadline > now ? deadline - now : 0
        wakeTask = Task { @MainActor [weak self] () -> Void in
            try? await Task.sleep(for: .nanoseconds(Int64(clamping: delay)))
            guard !Task.isCancelled, let self else { return }
            self.tick(at: self.clock())   // early wake-ups apply nothing and reschedule
        }
    }

    // MARK: - Texts (R9)

    /// "beat", "bar" or "cue" (the mode's boundary).
    var boundaryWord: String {
        switch queue.mode {
        case .bar: return "bar"
        case .cue: return "cue"
        case .beat, .off: return "beat"
        }
    }

    /// "Queued for the next beat" while `id` waits; nil otherwise.
    func queuedText(for id: ParameterID) -> String? {
        isQueued(id) ? "Queued for the next " + boundaryWord : nil
    }

    static func fallbackSuffix(_ reason: QuantizeImmediateReason) -> String? {
        switch reason {
        case .off: return nil
        case .noTempo: return ", applied now, no tempo"
        case .noCue: return ", applied now, no cues"
        }
    }

    /// "Glow Enabled" (group and name, as the macro rows show them).
    static func name(_ id: ParameterID) -> String {
        guard let descriptor = ParameterInspectorCatalog.descriptor(id) else { return id.rawValue }
        return descriptor.group.displayName + " " + descriptor.displayName
    }

    static func spoken(_ value: ParameterValue, id: ParameterID) -> String {
        guard let descriptor = ParameterInspectorCatalog.descriptor(id) else { return value.description }
        return ParameterValueText.spoken(value, descriptor: descriptor)
    }
}

// MARK: - Wiring (shared by the app and ParameterQuantizerAcceptanceTests)

extension ParameterQuantizer {
    func connect(settings: AppSettings, tempo: @escaping () -> TempoSnapshot, hasCues: @escaping () -> Bool,
                 announce: @escaping (String) -> Void) {
        self.tempo = tempo
        self.hasCues = hasCues
        self.announce = announce
        let lock: SceneLock = settings.sceneLock
        isLocked = { () -> Bool in lock.isLocked }
        apply = { [weak settings] (id: ParameterID, value: ParameterValue) -> Void in
            guard let settings else { return }
            ParameterInspectorTargets.target(for: id, settings: settings)?.set(value)   // SCN-015-guarded
        }
    }
}

extension ParameterInspectorTargets {
    /// MOD-017: `target(for:settings:)` for continuous parameters; for discrete ones (boolean, enum, integer or fixed
    /// choices) `get` reads the queued value if any and `set` goes through the quantizer. A locked scene refuses at
    /// once (SCN-015).
    static func quantizedTarget(for id: ParameterID, settings: AppSettings) -> ParameterInspectorTarget? {
        guard let target = target(for: id, settings: settings) else { return nil }
        guard isDiscrete(id, target: target) else { return target }
        let quantizer: ParameterQuantizer = settings.parameterQuantizer
        let lock: SceneLock = settings.sceneLock
        return ParameterInspectorTarget(
            get: { () -> ParameterValue in quantizer.pendingValue(for: id) ?? target.get() },
            set: { (value: ParameterValue) -> Void in
                if lock.isLocked {
                    target.set(value)   // refused and announced by the lock
                    return
                }
                quantizer.request(id, value: value, current: target.get(), applyNow: { (v: ParameterValue) -> Void in target.set(v) })
            },
            choices: target.choices)
    }

    static func isDiscrete(_ id: ParameterID, target: ParameterInspectorTarget) -> Bool {
        if target.choices != nil { return true }
        guard let kind = ParameterInspectorCatalog.descriptor(id)?.kind else { return false }
        switch kind {
        case .boolean, .enumeration, .integer: return true
        case .continuous, .color: return false
        }
    }
}
