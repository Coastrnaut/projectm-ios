// ShowTransportCoordinator.swift — SHOW-007 the show timeline's transport in the app (specs/243-show-007-timeline-transport;
// R2 to R10; contract T2 to T7; research SHOW-007-D2 to D7).
//
// * The timeline is ShowControl's `ShowTimeline`, rebuilt from the show on every read (≤ 256 cues). The position is the
//   active cue's start plus its elapsed time from the driver's playhead (SHOW-002's clock; nothing reads wall time).
// * `seek(to:)` plans with `ShowSeekPlan`: nothing, a countdown move inside the active cue, or one apply of the
//   destination through `ShowCoordinator.seek(to:)` (a cut, never quantized) followed by the countdown move. Cues in
//   between are never applied, driven or announced (the roadmap acceptance). Seeks post no announcement.
// * Scrubbing (`beginScrub`, `scrub(to:)`, `endScrub`) keeps only a preview time while dragging; release commits one
//   seek (`ShowScrub`). A VoiceOver swipe is one seek.
// * Play and Pause are SHOW-005's Hold (`setHold`, which announces it); Play at Standby first seeks to 0:00.
// * Loop (`settings.show.loop`, absent = off) is a device preference: in `AppSettings.allKeys` (UI-test reset, Settings
//   erase), excluded from backup. The driver reads it through `loops`.
// * SHOW-008: `positionJumped` runs after every seek that moved the position, so keyframe tracks are sampled at once.
// * SHOW-010: `beatGrid` places SHOW-011's tempo on this timeline for the row's ticks and readout.
import Foundation
import Observation
import ShowControl

@MainActor
@Observable
final class ShowTransportCoordinator {
    static let loopKey = "settings.show.loop"
    /// One VoiceOver swipe on the scrub slider (ACC-005 grid from 0:00).
    static let stepSeconds: Double = 5

    private(set) var loops: Bool
    private(set) var scrub = ShowScrub()
    /// Seeks that applied a cue (tests and DEBUG probes).
    private(set) var appliedSeeks = 0

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private weak var show: ShowCoordinator?
    @ObservationIgnored private weak var driver: ShowAutoAdvanceCoordinator?
    /// SHOW-005's Hold (AppCoordinator wires `setShowHold`, which announces; tests use the driver directly).
    @ObservationIgnored var setHold: (Bool) -> Void
    /// SHOW-008-R6: a seek moved the position (the keyframe coordinator samples its tracks once).
    @ObservationIgnored var positionJumped: () -> Void = { () -> Void in }
    /// SHOW-010: the beat grid on this timeline (AppCoordinator wires its tempo).
    @ObservationIgnored let beatGrid = ShowBeatGridCoordinator()

    init(show: ShowCoordinator, driver: ShowAutoAdvanceCoordinator, defaults: UserDefaults) {
        self.show = show
        self.driver = driver
        self.defaults = defaults
        loops = defaults.bool(forKey: Self.loopKey)
        setHold = { [weak driver] (held: Bool) -> Void in driver?.setOperatorHold(held) }
        driver.loops = { [weak self] () -> Bool in self?.loops ?? false }
        beatGrid.transport = self
    }

    // MARK: - Reading

    var timeline: ShowTimeline { show.map { (s: ShowCoordinator) -> ShowTimeline in ShowTimeline(list: s.list) } ?? ShowTimeline(list: ShowCueList()) }

    /// R8: the transport is shown only when the timeline has time on it.
    var isAvailable: Bool { timeline.duration > .zero }

    /// Hold is off and a cue is active (at Standby the button offers Play, which starts the show).
    var isPlaying: Bool { !(driver?.isOperatorHeld ?? true) && show?.list.activeCue != nil }

    /// The position now (nil at Standby or when the active cue is not on the timeline).
    func currentTime() -> Duration? {
        guard let show, let driver, let active = show.list.activeCue?.id else { return nil }
        let remaining: Duration? = driver.playhead.cueID == active ? driver.playhead.remaining(at: driver.clock.now()) : nil
        return timeline.time(ofCue: active, remaining: remaining)
    }

    /// The scrub preview while dragging, else the position.
    func displayedTime() -> Duration? { scrub.previewTime ?? currentTime() }

    /// "1:15 / 2:30", "Off timeline / 2:30", or the scrub preview "Cue 3 · Drop at 0:15".
    func positionText() -> String {
        let timeline: ShowTimeline = self.timeline
        let total: String = Self.clock(timeline.duration)
        if let preview = scrub.previewTime, let show, let point = timeline.locate(preview, looping: false),
           point.index < show.list.cues.count {
            let label: String = show.list.cues[point.index].label
            return "Cue \(point.index + 1) · \(label) at \(Self.clock(point.elapsed))"
        }
        guard let now = currentTime() else { return "Off timeline / \(total)" }
        return "\(Self.clock(now)) / \(total)"
    }

    static func clock(_ time: Duration) -> String { ShowCueDwell.clockText(seconds: Int(time.components.seconds)) }

    static func seconds(_ time: Duration) -> Double {
        let parts = time.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }

    // MARK: - Seeking (R2 to R5)

    /// Seeks to `time` (clamped to the timeline): nothing, a countdown move, or one apply of the destination cue.
    @discardableResult
    func seek(to time: Duration) -> ShowSeekAction {
        guard let show, let driver else { return .none }
        let active: UUID? = show.list.activeCue?.id
        let current: Duration? = driver.playhead.cueID == active && active != nil ? driver.playhead.remaining(at: driver.clock.now()) : nil
        let action: ShowSeekAction = ShowSeekPlan.plan(activeCueID: active, timeline: timeline, to: time, looping: false,
                                                       currentRemaining: current)
        switch action {
        case .none:
            break
        case let .reposition(cueID, remaining):
            driver.reposition(cueID: cueID, remaining: remaining)
        case let .apply(cueID, remaining):
            guard show.seek(to: cueID).moved else { return .none }
            appliedSeeks += 1
            driver.reposition(cueID: cueID, remaining: remaining)
        }
        if action != .none { positionJumped() }   // SHOW-008
        return action
    }

    func seek(toSeconds seconds: Double) { seek(to: .milliseconds(Int64((max(0, seconds) * 1000).rounded()))) }

    func beginScrub() { scrub.begin() }

    /// Moves the preview only (R4).
    func scrub(toSeconds seconds: Double) { scrub.move(to: .milliseconds(Int64((max(0, seconds) * 1000).rounded()))) }

    /// Commits the drag's one seek (R4).
    func endScrub() {
        if let time = scrub.end() { seek(to: time) }
    }

    // MARK: - Play, Pause, Loop (R6, R7)

    func play() {
        if show?.list.activeCue == nil { seek(to: .zero) }
        setHold(false)
    }

    func pause() { setHold(true) }

    func togglePlay() { if isPlaying { pause() } else { play() } }

    func setLoops(_ on: Bool) {
        guard on != loops else { return }
        loops = on
        if on { defaults.set(true, forKey: Self.loopKey) } else { defaults.removeObject(forKey: Self.loopKey) }
        driver?.loopChanged()
    }
}
