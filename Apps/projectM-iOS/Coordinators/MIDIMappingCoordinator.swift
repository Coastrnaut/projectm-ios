// MIDIMappingCoordinator.swift — MIDI learn and the mapping list (MIDI-003-R1-R12; specs/128-midi-003-midi-learn,
// contracts/midi-learn.md L2; research MIDI-003-D2, D4-D9).
//
// * Learn: `startLearning(_:)` arms a `MIDILearnSession`; the first eligible control change in a batch binds it
//   (one binding per message, MIDI-003-R2, R3) and learn mode ends. Cancel, a 30 s timeout (an injected
//   scheduler, so it fires in silence), or the input stopping (listening off, background) end it with no binding.
// * The list: one binding per control and per parameter (rebinding replaces, MIDI-003-R5), at most 64, stored
//   globally as text lines under `settings.midi.mappings` (kind, channel, number and parameter ID only:
//   MIDI-003-R4, R9). One-step Undo while the mappings screen is open (research MIDI-003-D8).
// * Values: later messages on bound controls set live values (linear over the range, newest per batch), pushed
//   through `applyValues` to the native host, where MOD-002 and ACC-012's clamp follow (research MIDI-003-D6).
//   Live values are memory only: never stored, never in a scene or the undo history (MIDI-003-R8).
// * The input client "mappings" is registered only while learning or while bindings exist (MIDI-003-R12).
// * Announcements (learning started, mapped, timed out) go through the injected `.midi` announcer; values are
//   never announced (MIDI-003-R11). Nothing here names a MIDI endpoint: `MIDIEvent` has no source.
// * MIDI-004 (specs/140-midi-004-cc-scaling, contract C4): each mapping's curve and Invert are set from its options
//   screen (`selectPreset`, `setInverted`): saved at once in the same line (`;curve=`, `;invert=1`), announced on
//   the `.midi` lane, no Undo entry, and applied from the control's next message (no jump while nobody touches it).
import Foundation
import Observation
import ParameterGraph
import PerformanceControl
import VisualEffects
import VisualParameters

/// One row of MIDI Mappings (contract L2).
struct MIDIMappingRow: Identifiable, Equatable {
    let parameter: ParameterID
    /// "Glow intensity"
    let name: String
    /// "CC 7 · Ch 1"; nil when not mapped.
    let control: String?
    let isLearning: Bool
    /// MIDI-004: "Ease in, inverted"; nil when not mapped.
    var curveSummary: String? = nil
    /// MIDI-004-R5: the stored curve could not be read; Linear is used.
    var curveUnreadable: Bool = false

    var id: String { parameter.rawValue }

    /// "Glow intensity, CC 7, channel 1" / "Glow intensity, not mapped"
    var accessibilityLabel: String {
        guard let control else { return name + ", not mapped" }
        return name + ", " + control.replacingOccurrences(of: " · Ch ", with: ", channel ")
    }
}

@MainActor
@Observable
final class MIDIMappingCoordinator {
    typealias Scheduler = @MainActor (UInt64, @escaping @MainActor () -> Void) -> (@MainActor () -> Void)

    static let mappingsKey = "settings.midi.mappings"   // MIDI-003-R9 (global; backup and Settings erase)
    static let clientName: String = "mappings"
    static let offText: String = "Turn on Listen for MIDI devices to learn a control."
    static let idleText: String = "Tap Learn, then move a control on your MIDI device."
    static let timedOutText: String = "MIDI learn timed out. Nothing was mapped."
    static let cancelledText: String = "MIDI learn cancelled."
    static let stoppedText: String = "Learning stopped: Listen for MIDI devices is off."
    static let fullText: String = "No more mappings fit (64). Delete one first."

    private(set) var bindings = MIDIBindingList()
    private(set) var learningTarget: ParameterID?
    private(set) var liveValues: [ParameterID: Double] = [:]
    private(set) var canUndo = false
    private(set) var lastMessage: String?

    /// Called with every live value after each change (the app pushes them to the native host).
    @ObservationIgnored var applyValues: @MainActor ([ParameterID: Double]) -> Void = { (_: [ParameterID: Double]) -> Void in }

    @ObservationIgnored let learnable: [ParameterDescriptor]
    @ObservationIgnored private let registry: ParameterRegistry
    @ObservationIgnored private let input: MIDIInputCoordinator
    @ObservationIgnored private let discovery: MIDIDiscoveryCoordinator
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let announce: @MainActor (String) -> Void
    @ObservationIgnored private let clock: @MainActor () -> UInt64
    @ObservationIgnored private let scheduler: Scheduler
    @ObservationIgnored private var session = MIDILearnSession<ParameterID>()
    @ObservationIgnored private var cancelTimeout: (@MainActor () -> Void)?
    @ObservationIgnored private var undoList: MIDIBindingList?
    @ObservationIgnored private var isClientRegistered = false

    init(registry: ParameterRegistry, applied: Set<ParameterID>, input: MIDIInputCoordinator,
         discovery: MIDIDiscoveryCoordinator, defaults: UserDefaults,
         announce: @escaping @MainActor (String) -> Void = { (_: String) -> Void in },
         clock: @escaping @MainActor () -> UInt64 = { () -> UInt64 in DispatchTime.now().uptimeNanoseconds },
         scheduler: @escaping Scheduler = MIDIMappingCoordinator.taskScheduler) {
        self.registry = registry
        self.input = input
        self.discovery = discovery
        self.defaults = defaults
        self.announce = announce
        self.clock = clock
        self.scheduler = scheduler
        learnable = MIDILearnCatalog.learnable(in: registry, applied: applied)
        let allowed: Set<ParameterID> = Set(learnable.map { (descriptor: ParameterDescriptor) -> ParameterID in descriptor.id })
        let lines: [String] = defaults.stringArray(forKey: Self.mappingsKey) ?? []
        bindings = MIDIBindingList(storageLines: lines, allowedTargets: allowed)
        input.addStateObserver { [weak self] () -> Void in self?.inputStateChanged() }
        updateClient()
    }

    /// The parameters the app's per-frame resolution applies (the glow; research MIDI-003-D6).
    static var appliedIDs: Set<ParameterID> { BloomParameters.midiControlledIDs }

    /// The visual catalog (validated in CI by `VisualParameterCatalogTests`).
    static func visualRegistry() -> ParameterRegistry {
        guard let registry = try? VisualParameterCatalog.makeRegistry() else {
            preconditionFailure("VisualParameterCatalog is invalid")
        }
        return registry
    }

    /// A `Task.sleep` timer; the returned closure cancels it.
    static func taskScheduler(_ nanoseconds: UInt64, _ work: @escaping @MainActor () -> Void) -> (@MainActor () -> Void) {
        let task = Task { @MainActor () -> Void in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            work()
        }
        return { () -> Void in task.cancel() }
    }

    // MARK: Texts and rows

    var canLearn: Bool { discovery.state.isListening }
    var isLearning: Bool { learningTarget != nil }

    var rows: [MIDIMappingRow] {
        learnable.map { (descriptor: ParameterDescriptor) -> MIDIMappingRow in
            let binding: MIDIControlBinding? = bindings.binding(for: descriptor.id)
            let control: String? = binding.map { (binding: MIDIControlBinding) -> String in Self.controlText(binding.key) }
            return MIDIMappingRow(parameter: descriptor.id, name: Self.name(descriptor), control: control,
                                  isLearning: learningTarget == descriptor.id, curveSummary: binding?.options.summary,
                                  curveUnreadable: binding?.options.hasUnreadableCurve ?? false)
        }
    }

    var statusText: String {
        if let learningTarget { return "Move a control on your MIDI device to map " + name(of: learningTarget) + "…" }
        if !canLearn { return lastMessage == Self.stoppedText ? Self.stoppedText : Self.offText }
        return lastMessage ?? Self.idleText
    }

    /// "Glow intensity" from group "Glow" and name "Intensity"; a parenthesized unit note ("Radius (of the shorter
    /// side)") is left out.
    static func name(_ descriptor: ParameterDescriptor) -> String {
        let group: String = descriptor.group.displayName
        let full: String = descriptor.displayName
        let own: String = full.range(of: " (").map { (range: Range<String.Index>) -> String in String(full[..<range.lowerBound]) } ?? full
        guard let first = own.first else { return group }
        let lowered: String = String(first).lowercased() + String(own.dropFirst())
        return group + " " + lowered
    }

    func name(of id: ParameterID) -> String {
        registry.descriptor(for: id).map { (descriptor: ParameterDescriptor) -> String in Self.name(descriptor) } ?? id.rawValue
    }

    /// "CC 7 · Ch 1" (channels shown 1–16).
    static func controlText(_ key: MIDIControlKey) -> String {
        let channel: Int = Int(key.channel) + 1
        return "CC " + String(key.number) + " · Ch " + String(channel)
    }

    /// "CC 7 on channel 1"
    static func spokenControl(_ key: MIDIControlKey) -> String {
        let channel: Int = Int(key.channel) + 1
        return "CC " + String(key.number) + " on channel " + String(channel)
    }

    // MARK: Screen lifecycle

    func open() {
        undoList = nil
        canUndo = false
        lastMessage = nil
    }

    /// Leaving the screen cancels learning and forgets Undo (MIDI-003 spec Clarifications).
    func close() {
        if session.isLearning { _ = session.cancel() }
        endLearning()
        undoList = nil
        canUndo = false
        updateClient()
    }

    // MARK: Learning

    func startLearning(_ target: ParameterID) {
        guard canLearn, learnable.contains(where: { (descriptor: ParameterDescriptor) -> Bool in descriptor.id == target }) else { return }
        session.start(target: target, now: clock())
        learningTarget = target
        lastMessage = nil
        cancelTimeout?()
        cancelTimeout = scheduler(MIDILearnSession<ParameterID>.timeoutNanoseconds) { [weak self] () -> Void in self?.timeoutFired() }
        announce("Move a control on your MIDI device to map " + name(of: target) + ".")
        updateClient()
    }

    func cancelLearning() {
        guard session.cancel() != nil else { return }
        lastMessage = Self.cancelledText
        endLearning()
        updateClient()
    }

    private func timeoutFired() {
        guard session.expire(now: clock()) != nil else { return }
        finishTimedOut()
    }

    private func finishTimedOut() {
        lastMessage = Self.timedOutText
        endLearning()
        announce(Self.timedOutText)
        updateClient()
    }

    private func endLearning() {
        learningTarget = nil
        cancelTimeout?()
        cancelTimeout = nil
    }

    private func inputStateChanged() {
        guard session.isLearning, !input.isReceiving else { return }
        _ = session.cancel()
        lastMessage = Self.stoppedText
        endLearning()
        updateClient()
    }

    // MARK: Editing

    func deleteMapping(_ target: ParameterID) {
        let before: MIDIBindingList = bindings
        guard bindings.remove(target: target) != nil else { return }
        rememberUndo(before)
        listChanged()
    }

    // MARK: Curve and inversion (MIDI-004, contract C4.1)

    static let unreadableCurveText: String = "Curve not readable; using Linear."

    /// The mapping's options; nil when `target` is not mapped.
    func options(for target: ParameterID) -> MIDIMappingOptions? {
        bindings.binding(for: target)?.options
    }

    func selectPreset(_ preset: MIDICurvePreset, for target: ParameterID) {
        guard var options = options(for: target) else { return }
        options.setCurve(preset.curve)
        guard updateOptions(options, for: target) else { return }
        announce(name(of: target) + " curve: " + preset.title + ".")
    }

    func setInverted(_ inverted: Bool, for target: ParameterID) {
        guard var options = options(for: target) else { return }
        options.inverted = inverted
        guard updateOptions(options, for: target) else { return }
        announce(name(of: target) + (inverted ? " inverted." : " not inverted."))
    }

    /// Saves changed options; false when nothing changed. Live values wait for the next message.
    private func updateOptions(_ options: MIDIMappingOptions, for target: ParameterID) -> Bool {
        guard self.options(for: target) != options else { return false }
        bindings.setOptions(options, for: target)
        save()
        return true
    }

    func undo() {
        guard let previous = undoList else { return }
        undoList = nil
        canUndo = false
        bindings = previous
        listChanged()
    }

    private func rememberUndo(_ list: MIDIBindingList) {
        undoList = list
        canUndo = true
    }

    private func listChanged() {
        save()
        let bound: Set<ParameterID> = Set(bindings.bindings.map { (binding: MIDIControlBinding) -> ParameterID in binding.target })
        let kept: [ParameterID: Double] = liveValues.filter { (entry: (key: ParameterID, value: Double)) -> Bool in bound.contains(entry.key) }
        if kept != liveValues {
            liveValues = kept
            applyValues(kept)
        }
        updateClient()
    }

    private func save() {
        if bindings.isEmpty {
            defaults.removeObject(forKey: Self.mappingsKey)
        } else {
            defaults.set(bindings.storageLines, forKey: Self.mappingsKey)
        }
    }

    // MARK: Receiving

    /// The input client's handler (one display tick's batch).
    func receive(_ batch: [MIDIEvent]) {
        guard !batch.isEmpty else { return }
        var updates: [ParameterID: Double] = [:]
        var rest: ArraySlice<MIDIEvent> = batch[...]
        if session.isLearning, let outcome = session.handle(batch, now: clock()) {
            switch outcome {
            case let .bound(key, target, eventIndex):
                let before: [MIDIEvent] = Array(batch[..<eventIndex])
                updates = MIDIBindingValues.values(for: before, bindings: bindings, registry: registry)   // old bindings
                rest = batch[(eventIndex + 1)...]
                bind(key, to: target)
            case .timedOut:
                finishTimedOut()
            case .cancelled:
                break
            }
        }
        let later: [ParameterID: Double] = MIDIBindingValues.values(for: Array(rest), bindings: bindings, registry: registry)
        updates.merge(later) { (_: Double, newer: Double) -> Double in newer }
        guard !updates.isEmpty else { return }
        var merged: [ParameterID: Double] = liveValues
        merged.merge(updates) { (_: Double, newer: Double) -> Double in newer }
        let bound: Set<ParameterID> = Set(bindings.bindings.map { (binding: MIDIControlBinding) -> ParameterID in binding.target })
        merged = merged.filter { (entry: (key: ParameterID, value: Double)) -> Bool in bound.contains(entry.key) }
        guard merged != liveValues else { return }
        liveValues = merged
        applyValues(merged)
    }

    private func bind(_ key: MIDIControlKey, to target: ParameterID) {
        let before: MIDIBindingList = bindings
        let outcome: MIDIBindOutcome = bindings.bind(key, to: target)
        endLearning()
        let mapped: String = name(of: target) + " mapped to " + Self.spokenControl(key)
        switch outcome {
        case .full:
            lastMessage = Self.fullText
            announce(Self.fullText)
            updateClient()
            return
        case let .moved(from), let .movedAndReplaced(from, _):
            lastMessage = mapped + " (moved from " + name(of: from) + ")."
        case .added, .replaced:
            lastMessage = mapped + "."
        }
        if before != bindings { rememberUndo(before) }
        announce(lastMessage ?? mapped)
        listChanged()
    }

    // MARK: Input client (MIDI-003-R12)

    private var needsInput: Bool { session.isLearning || !bindings.isEmpty }

    private func updateClient() {
        if needsInput && !isClientRegistered {
            isClientRegistered = true
            input.addClient(Self.clientName) { [weak self] (batch: [MIDIEvent]) -> Void in self?.receive(batch) }
        } else if !needsInput && isClientRegistered {
            isClientRegistered = false
            input.removeClient(Self.clientName)
        }
    }

    /// Whether the input client is registered (tests).
    var isInputClientRegistered: Bool { isClientRegistered }
}

// MARK: - The glow parameters a MIDI control can drive (MIDI-003-R1, research MIDI-003-D6)

extension BloomParameters {
    /// The catalog IDs `NativeSpectrumHost.resolveEffectiveGlow` resolves per frame.
    static let midiControlledIDs: Set<ParameterID> = [VisualParameterIDs.bloomIntensity, VisualParameterIDs.bloomRadius,
                                                      VisualParameterIDs.bloomThreshold, VisualParameterIDs.bloomKnee]

    /// These parameters with each present external value in place of the manual one (each clamped to its range;
    /// non-finite values ignored). Other IDs are ignored; an empty map returns `self`.
    func applying(_ values: [ParameterID: Double]) -> BloomParameters {
        guard !values.isEmpty else { return self }
        var result: BloomParameters = self
        if let value = Self.external(values[VisualParameterIDs.bloomIntensity], Self.intensityRange) { result.intensity = value }
        if let value = Self.external(values[VisualParameterIDs.bloomRadius], Self.radiusRange) { result.radius = value }
        if let value = Self.external(values[VisualParameterIDs.bloomThreshold], Self.thresholdRange) { result.threshold = value }
        if let value = Self.external(values[VisualParameterIDs.bloomKnee], Self.kneeRange) { result.knee = value }
        return result
    }

    private static func external(_ value: Double?, _ range: ClosedRange<Float>) -> Float? {
        guard let value, value.isFinite else { return nil }
        let single: Float = Float(value)
        return min(max(single, range.lowerBound), range.upperBound)
    }
}
