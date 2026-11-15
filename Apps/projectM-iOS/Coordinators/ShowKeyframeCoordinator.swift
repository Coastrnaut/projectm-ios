// ShowKeyframeCoordinator.swift — SHOW-008 keyframe tracks in the app (specs/246-show-008-keyframe-tracks; R5 to R8;
// contract K5, K6; research SHOW-008-D4 to D6).
//
// * Targets: the MOD-001 registry parameters the native host's live path applies per frame (the four glow parameters,
//   with their ranges and step hints) and Visual Colour (a one-colour palette). A stored track for any other parameter
//   stays in the show, is listed as not available and drives nothing.
// * `sample()` reads SHOW-007's timeline position (the transport's `currentTime()`, from the driver's playhead and its
//   injected monotonic clock), evaluates ShowControl's pure `ShowKeyframeTracks.values(at:)`, clamps numbers to the
//   registry range and hands the result to `apply` only when it changed (a seek to a keyframe time applies once). At
//   Standby or off the timeline the output is empty: the manual values return.
// * A main-actor loop samples every 1/60 s while the show plays with tracks and every 250 ms otherwise (a frozen time
//   changes nothing, so nothing applies). The transport calls `sample()` right after a seek (`positionJumped`). Tests
//   call `sample()` themselves (`runsLoop` false).
// * Edits go through `ShowCoordinator.setKeyframeTracks` (refused while the scene is locked, saved at once) and then
//   resample. Numbers are clamped to the target's range when stored, so the output clamp never changes a keyframe.
import Foundation
import Observation
import ParameterGraph
import ShowControl
import VisualParameters

/// What the tracks drive now: glow numbers (by parameter) and the Visual Colour.
struct ShowTrackOutput: Equatable {
    var numbers: [ParameterID: Double] = [:]
    var color: ShowKeyframeColor? = nil

    var isEmpty: Bool { numbers.isEmpty && color == nil }

    /// R5: the track numbers with `live` (MIDI-003/OSC-003) values on top: the performer's hands win.
    func numbers(overlaidBy live: [ParameterID: Double]) -> [ParameterID: Double] {
        numbers.merging(live) { (_: Double, external: Double) -> Double in external }
    }
}

/// A parameter a keyframe track can drive in this version.
struct ShowKeyframeTarget: Identifiable, Equatable {
    enum Kind: Equatable {
        case number(range: ClosedRange<Double>, step: Double)
        case color
    }

    /// Visual Colour: not a registry parameter; the native visual's one-colour palette (SHOW-008-R7).
    static let visualColorID: ParameterID = "visual.palette.color"

    let id: ParameterID
    let name: String
    let kind: Kind

    var isColor: Bool { kind == .color }

    /// `value` clamped to the range (numbers); nil when its kind does not fit.
    func clamped(_ value: ShowKeyframeValue) -> ShowKeyframeValue? {
        switch (kind, value) {
        case let (.number(range, _), .number(v)): return .number(min(max(v, range.lowerBound), range.upperBound))
        case (.color, .color): return value
        default: return nil
        }
    }

    /// The glow parameters the live path applies (from the registry, in catalog order), then Visual Colour.
    static func available() -> [ShowKeyframeTarget] {
        var result: [ShowKeyframeTarget] = []
        for descriptor in VisualParameterCatalog.descriptors where liveIDs.contains(descriptor.id) {
            guard case let .continuous(minimum, maximum, _, step, _) = descriptor.kind, minimum <= maximum else { continue }
            let name: String = "Glow " + Self.shortName(descriptor.displayName)
            result.append(ShowKeyframeTarget(id: descriptor.id, name: name,
                                             kind: .number(range: minimum...maximum, step: step ?? (maximum - minimum) / 100)))
        }
        result.append(ShowKeyframeTarget(id: visualColorID, name: "Visual Colour", kind: .color))
        return result
    }

    /// The IDs the native host resolves per frame (MIDI-003's set).
    static let liveIDs: Set<ParameterID> = [VisualParameterIDs.bloomIntensity, VisualParameterIDs.bloomRadius,
                                            VisualParameterIDs.bloomThreshold, VisualParameterIDs.bloomKnee]

    /// "Radius (of the shorter side)" → "Radius".
    private static func shortName(_ name: String) -> String {
        guard let cut = name.firstIndex(of: "(") else { return name }
        return String(name[..<cut]).trimmingCharacters(in: .whitespaces)
    }
}

@MainActor
@Observable
final class ShowKeyframeCoordinator {
    static let playingInterval: Duration = .milliseconds(16)
    static let idleInterval: Duration = .milliseconds(250)

    let targets: [ShowKeyframeTarget]
    /// The output applied last.
    private(set) var output = ShowTrackOutput()
    /// How many outputs were applied (tests and DEBUG probes).
    private(set) var appliedCount = 0

    /// Receives each changed output (AppCoordinator: the host's external values and palette; a recorder in tests).
    @ObservationIgnored var apply: (ShowTrackOutput) -> Void = { (_: ShowTrackOutput) in }
    /// The value the output uses now for a target without keyframes (the manual glow value; white for colour).
    @ObservationIgnored var currentValue: (ShowKeyframeTarget) -> ShowKeyframeValue = { (target: ShowKeyframeTarget) -> ShowKeyframeValue in
        switch target.kind {
        case let .number(range, _): .number(range.lowerBound)
        case .color: .color(.white)
        }
    }
    @ObservationIgnored private weak var show: ShowCoordinator?
    @ObservationIgnored private weak var transport: ShowTransportCoordinator?
    @ObservationIgnored private let runsLoop: Bool
    @ObservationIgnored private var loop: Task<Void, Never>?

    init(show: ShowCoordinator, transport: ShowTransportCoordinator, targets: [ShowKeyframeTarget] = ShowKeyframeTarget.available(),
         runsLoop: Bool = true) {
        self.show = show
        self.transport = transport
        self.targets = targets
        self.runsLoop = runsLoop
        transport.positionJumped = { [weak self] () -> Void in self?.sample() }
        startLoop()
    }

    // MARK: Reading

    var tracks: ShowKeyframeTracks { show?.list.tracks ?? ShowKeyframeTracks() }
    var isEditLocked: Bool { show?.isEditLocked ?? false }

    func target(for id: ParameterID) -> ShowKeyframeTarget? { targets.first { (t: ShowKeyframeTarget) -> Bool in t.id == id } }

    /// Targets without a track yet (Add Track).
    var unusedTargets: [ShowKeyframeTarget] {
        let used: Set<ParameterID> = Set(tracks.tracks.map(\.parameter))
        return targets.filter { (t: ShowKeyframeTarget) -> Bool in !used.contains(t.id) }
    }

    /// The position (nil at Standby or off the timeline).
    var position: Duration? { transport?.currentTime() }

    /// Where Add Keyframe at Playhead puts a keyframe: the position in whole milliseconds, or 0:00.
    var playheadMilliseconds: Int { ShowKeyframeTrack.milliseconds(of: position ?? .zero) }

    /// The output at `time` (empty for nil).
    func evaluate(at time: Duration?) -> ShowTrackOutput {
        guard let time else { return ShowTrackOutput() }
        var result = ShowTrackOutput()
        for (id, value) in tracks.values(at: time) {
            guard let target = target(for: id), let clamped = target.clamped(value) else { continue }   // not available
            switch clamped {
            case let .number(v): result.numbers[id] = v
            case let .color(c): result.color = c
            }
        }
        return result
    }

    // MARK: Sampling (R6)

    /// Evaluates at the position now and applies the output when it changed.
    func sample() {
        let next: ShowTrackOutput = evaluate(at: position)
        guard next != output else { return }
        output = next
        appliedCount += 1
        apply(next)
    }

    private var isPlayingWithTracks: Bool { (transport?.isPlaying ?? false) && !tracks.isEmpty }

    private func startLoop() {
        guard runsLoop, loop == nil else { return }
        loop = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let wait: Duration = (self?.isPlayingWithTracks ?? false) ? Self.playingInterval : Self.idleInterval
                try? await Task.sleep(for: wait)
                guard !Task.isCancelled, let self else { return }
                self.sample()
            }
        }
    }

    // MARK: Edits (R8; each refused while locked)

    @discardableResult
    func addTrack(_ target: ShowKeyframeTarget) -> UUID? {
        let id = UUID()
        let done: Bool = commit { (t: inout ShowKeyframeTracks) throws(ShowKeyframeError) -> Void in try t.addTrack(parameter: target.id, id: id) }
        return done ? id : nil
    }

    @discardableResult
    func removeTrack(_ id: UUID) -> Bool {
        commit { (t: inout ShowKeyframeTracks) throws(ShowKeyframeError) -> Void in try t.removeTrack(id) }
    }

    /// Adds a keyframe at the playhead (replacing one at the same time) with the track's value there, or the current
    /// value for a track without keyframes; returns its time.
    @discardableResult
    func addKeyframeAtPlayhead(track id: UUID) -> Int? {
        guard let track = tracks.track(id), let target = target(for: track.parameter) else { return nil }
        let time: Int = playheadMilliseconds
        let raw: ShowKeyframeValue = track.value(at: .milliseconds(time)) ?? currentValue(target)
        guard let value = target.clamped(raw) else { return nil }
        // SHOW-009 clarify: a new keyframe is Linear; a replaced one keeps its mode.
        let mode: ShowKeyframeInterpolation = track.keyframes.first { (k: ShowKeyframe) -> Bool in k.time == time }?.interpolation ?? .linear
        let done: Bool = commit { (t: inout ShowKeyframeTracks) throws(ShowKeyframeError) -> Void in
            try t.edit(id) { (track: inout ShowKeyframeTrack) throws(ShowKeyframeError) -> Void in
                try track.setKeyframe(ShowKeyframe(time: time, value: value, interpolation: mode))
            }
        }
        return done ? time : nil
    }

    @discardableResult
    func setValue(_ value: ShowKeyframeValue, track id: UUID, time: Int) -> Bool {
        guard let parameter = tracks.track(id)?.parameter, let clamped = target(for: parameter)?.clamped(value) else { return false }
        return commit { (t: inout ShowKeyframeTracks) throws(ShowKeyframeError) -> Void in
            try t.edit(id) { (track: inout ShowKeyframeTrack) throws(ShowKeyframeError) -> Void in try track.setValue(clamped, at: time) }
        }
    }

    @discardableResult
    func setInterpolation(_ interpolation: ShowKeyframeInterpolation, track id: UUID, time: Int) -> Bool {
        commit { (t: inout ShowKeyframeTracks) throws(ShowKeyframeError) -> Void in
            try t.edit(id) { (track: inout ShowKeyframeTrack) throws(ShowKeyframeError) -> Void in
                try track.setInterpolation(interpolation, at: time)
            }
        }
    }

    @discardableResult
    func removeKeyframe(track id: UUID, time: Int) -> Bool {
        commit { (t: inout ShowKeyframeTracks) throws(ShowKeyframeError) -> Void in
            try t.edit(id) { (track: inout ShowKeyframeTrack) throws(ShowKeyframeError) -> Void in try track.removeKeyframe(at: time) }
        }
    }

    /// Runs `edit` on a copy, stores it through the show (lock, save) and resamples.
    private func commit(_ edit: (inout ShowKeyframeTracks) throws(ShowKeyframeError) -> Void) -> Bool {
        guard let show else { return false }
        var copy: ShowKeyframeTracks = show.list.tracks
        do { try edit(&copy) } catch { return false }
        guard show.setKeyframeTracks(copy) else { return false }
        sample()
        return true
    }

    // MARK: Text

    /// "0:30", or "0:30.250" when the time is not on a whole second.
    static func timeText(_ milliseconds: Int) -> String {
        let seconds: Int = milliseconds / 1000
        let rest: Int = milliseconds % 1000
        let clock: String = ShowCueDwell.clockText(seconds: seconds)
        guard rest != 0 else { return clock }
        let fraction: String = String(format: "%03d", rest)
        return clock + "." + fraction
    }

    static func valueText(_ value: ShowKeyframeValue) -> String {
        switch value {
        case let .number(v): return v.formatted(.number.precision(.fractionLength(2)))
        case let .color(c): return colorText(c)
        }
    }

    /// "#FF00AA" (alpha added when below 1: "#FF00AA, 50% opacity").
    static func colorText(_ c: ShowKeyframeColor) -> String {
        func byte(_ v: Double) -> Int { Int((v * 255).rounded()) }
        let hex: String = String(format: "#%02X%02X%02X", byte(c.red), byte(c.green), byte(c.blue))
        guard c.alpha < 1 else { return hex }
        let percent: Int = Int((c.alpha * 100).rounded())
        return hex + ", \(percent)% opacity"
    }

    /// "0:30, 0.90, Linear" (the row's text and VoiceOver label).
    static func rowText(_ keyframe: ShowKeyframe) -> String {
        timeText(keyframe.time) + ", " + valueText(keyframe.value) + ", " + keyframe.interpolation.displayName
    }
}
