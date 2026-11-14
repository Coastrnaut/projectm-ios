// TempoCoordinator.swift — tap tempo in the app (SHOW-011; specs/027-show-011-tap-tempo,
// contracts/tempo-source.md "App").
//
// * Owns the `TempoSource` (PerformanceControl): Tap reads the monotonic clock the analysis bus uses
//   (`MonotonicClock`); Reset clears the manual tempo. Nothing is stored (SHOW-011-R16).
// * Readout and VoiceOver texts are static functions, so tests check them without a UI.
// * The estimate (research SHOW-011-D3): exactly one pipeline reads the analysis tap. While projectM
//   is shown this coordinator runs its own `TempoAnalyzer` on the tap; while the circular spectrum is
//   shown it reads a subscription on that visual's pipeline. AppCoordinator chooses in
//   resumeActiveVisual()/pauseActiveVisual(), and PERF-011 suspends it (PresentationBoundResource):
//   the analysis runs only while a visual runs, and the estimate is cleared when it stops.
// * The subscription is polled every 250 ms on the main actor (D5); never on the pipeline's worker.
// * DEBUG: `-uitestTapInterval <ms>` makes every tap advance a synthetic clock by that interval, so
//   the UI test's taps are exact (D6).
// * ANL-006 (specs/088-anl-006-tempo-confidence-indicator, contracts/tempo-confidence.md): a
//   `TempoConfidenceIndicator` gets every polled estimate with `stateClock` (the monotonic clock;
//   separate from the tap clock, which the DEBUG tap fake steps on every reading). `readout`
//   (manual, stable, uncertain or searching) drives the readout's texts, the Tap control's value
//   and the Reset announcement; `snapshot` (what consumers read) is unchanged. A new analysis
//   (another reader, or none) restarts the indicator from searching. DEBUG:
//   `-uitestTempoEstimate <bpm>:<confidence>[:<polls>:<confidence2>]` replaces each poll's estimate.
// Nothing here reaches projectM (Constitution VIII, ADR-0008 decision 5).
import AudioCore
import Observation
import PerformanceControl
import PerformanceControlAnalysis
import PresentationLifecycle
import UIKit

@MainActor
@Observable
final class TempoCoordinator: PresentationBoundResource {
    static let pollInterval: Duration = .milliseconds(250)

    /// What consumers and the readout show.
    private(set) var snapshot: TempoSnapshot = .none
    /// Accepted taps in the current sequence.
    private(set) var tapsInSequence = 0
    /// What the readout shows (ANL-006).
    private(set) var readout: TempoReadout = .searching

    @ObservationIgnored private var source = TempoSource()
    @ObservationIgnored private let clock: () -> UInt64
    @ObservationIgnored private let announce: (String) -> Void
    @ObservationIgnored private let stateClock: () -> UInt64
    @ObservationIgnored private var indicator = TempoConfidenceIndicator()
    #if DEBUG
    /// Replaces each poll's estimate (`-uitestTempoEstimate`); the argument is the poll number (1, 2…).
    @ObservationIgnored var estimateScript: ((Int) -> TempoEstimate?)?
    @ObservationIgnored private var scriptPolls = 0
    #endif

    private enum Request {
        case off
        case own(any NormalizedPCMReader)
        case external(TempoSubscriptionReader)
    }

    @ObservationIgnored private var request = Request.off
    @ObservationIgnored private(set) var isSuspended = false
    @ObservationIgnored private var analyzer: TempoAnalyzer?
    @ObservationIgnored private var activeReader: TempoSubscriptionReader?
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    init(clock: @escaping () -> UInt64 = { MonotonicClock.nowNanoseconds() },
         stateClock: @escaping () -> UInt64 = { MonotonicClock.nowNanoseconds() },
         announce: @escaping (String) -> Void = { UIAccessibility.post(notification: .announcement, argument: $0) }) {
        self.clock = clock
        self.stateClock = stateClock
        self.announce = announce
    }

    /// The analysis state (ANL-006); diagnostics and tests.
    var confidenceState: TempoConfidenceState { indicator.state }

    isolated deinit {
        pollTask?.cancel()
        analyzer?.stop()
    }

    var rules: TapTempoRules { source.rules }

    // MARK: - Tap and reset

    func tap() {
        let before = snapshot
        let outcome = source.tap(at: clock())
        publish()
        switch outcome {
        case .established(let bpm):
            announce(Self.setAnnouncement(bpm: bpm))
        case .refined(let bpm):
            if before.bpm.map(Self.wholeBPM) != Self.wholeBPM(bpm) { announce(Self.setAnnouncement(bpm: bpm)) }
        case .tooFast:
            announce("Tap slower")
        case .tooSlow:
            announce("Tap faster")
        case .counting:
            break
        }
    }

    func reset() {
        source.resetManual()
        publish()
        announce(Self.resetAnnouncement(readout))
    }

    /// The analysis's estimate (nil: none). Called by the poll; tests call it directly.
    func updateEstimate(_ estimate: TempoEstimate?) {
        source.updateEstimate(estimate)
        indicator.update(estimate, at: stateClock())
        publish()
    }

    private func publish() {
        let next = source.snapshot
        if next != snapshot { snapshot = next }
        let nextReadout = TempoReadout(snapshot: next, indicator: indicator)
        if nextReadout != readout { readout = nextReadout }
        if source.tapsInSequence != tapsInSequence { tapsInSequence = source.tapsInSequence }
    }

    // MARK: - Texts (contracts/tempo-confidence.md "App"; SHOW-011 contracts/tempo-source.md)

    static func wholeBPM(_ bpm: Double) -> Int { Int(bpm.rounded()) }

    /// "120 BPM", "≈120 BPM" or "— BPM" (searching: no number). The unit keeps the searching line
    /// measurable: a lone em dash failed the accessibility audit's contrast check as an element-less
    /// node whenever no tempo had been found yet (2026-11-14 regression).
    static func readoutText(_ readout: TempoReadout) -> String {
        switch readout {
        case .manual(let bpm), .stable(let bpm):
            let whole: Int = wholeBPM(bpm)
            return "\(whole) BPM"
        case .uncertain(let bpm):
            let whole: Int = wholeBPM(bpm)
            return "≈\(whole) BPM"
        case .searching:
            return "— BPM"
        }
    }

    /// "Manual", "Stable", "Uncertain" or "Searching".
    static func stateText(_ readout: TempoReadout) -> String {
        switch readout {
        case .manual: "Manual"
        case .stable: "Stable"
        case .uncertain: "Uncertain"
        case .searching: "Searching"
        }
    }

    /// "120 BPM, manual", "120 BPM, stable", "About 120 BPM, uncertain" or "Searching for tempo".
    static func accessibilityValue(_ readout: TempoReadout) -> String {
        switch readout {
        case .manual(let bpm):
            let whole: Int = wholeBPM(bpm)
            return "\(whole) BPM, manual"
        case .stable(let bpm):
            let whole: Int = wholeBPM(bpm)
            return "\(whole) BPM, stable"
        case .uncertain(let bpm):
            let whole: Int = wholeBPM(bpm)
            return "About \(whole) BPM, uncertain"
        case .searching:
            return "Searching for tempo"
        }
    }

    /// The Tap control's value: progress while a sequence builds toward its first tempo.
    static func tapValue(readout: TempoReadout, taps: Int, of needed: Int) -> String {
        if taps > 0, taps < needed { return "Tap \(taps) of \(needed)" }
        return accessibilityValue(readout)
    }

    var tapValue: String { Self.tapValue(readout: readout, taps: tapsInSequence, of: rules.tapsToEstablish) }

    static func setAnnouncement(bpm: Double) -> String { "Tempo set to \(wholeBPM(bpm)) BPM" }

    static func resetAnnouncement(_ readout: TempoReadout) -> String {
        let prefix: String = "Manual tempo cleared. "
        let detail: String
        switch readout {
        case .stable(let bpm):
            let whole: Int = wholeBPM(bpm)
            detail = "Detected tempo \(whole) BPM"
        case .uncertain(let bpm):
            let whole: Int = wholeBPM(bpm)
            detail = "Tempo uncertain, about \(whole) BPM"
        case .searching, .manual:
            detail = "Searching for tempo"
        }
        return prefix + detail
    }

    // MARK: - Estimate (research SHOW-011-D3, D5)

    /// projectM is shown: run this coordinator's own pipeline on the analysis tap.
    func runOwnAnalysis(on tap: (any NormalizedPCMReader)?) {
        request = tap.map { .own($0) } ?? .off
        apply()
    }

    /// The circular spectrum is shown: read its pipeline through `reader`.
    func follow(_ reader: TempoSubscriptionReader) {
        request = .external(reader)
        apply()
    }

    /// No visual runs: stop the analysis and forget the estimate.
    func stopAnalysis() {
        request = .off
        apply()
    }

    /// The own pipeline runs (tests and diagnostics).
    var ownAnalysisRunning: Bool { analyzer?.isRunning ?? false }
    var isPolling: Bool { pollTask != nil }

    var presentationResourceName: String { "Tap tempo analysis" }

    func suspendForPresentationLoss() {
        guard !isSuspended else { return }
        isSuspended = true
        apply()
    }

    func resumeForPresentation() {
        guard isSuspended else { return }
        isSuspended = false
        apply()
    }

    private func apply() {
        let effective = isSuspended ? .off : request
        var next: TempoSubscriptionReader?
        switch effective {
        case .off:
            analyzer?.stop()
        case .own(let tap):
            if analyzer == nil { analyzer = try? TempoAnalyzer() }
            analyzer?.start(reader: tap)
            next = analyzer?.reader
        case .external(let reader):
            analyzer?.stop()
            next = reader
        }
        if let old = activeReader, old !== next { old.clear() }
        if activeReader !== next { indicator.reset() }   // ANL-006: a new analysis starts searching
        activeReader = next
        if next == nil {
            pollTask?.cancel()
            pollTask = nil
            updateEstimate(nil)
        } else if pollTask == nil {
            pollTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    self?.pollOnce()
                    try? await Task.sleep(for: TempoCoordinator.pollInterval)
                }
            }
        }
    }

    private func pollOnce() {
        guard let activeReader else { return }
        let estimate: TempoEstimate? = activeReader.poll()
        #if DEBUG
        if let estimateScript {
            scriptPolls += 1
            updateEstimate(estimateScript(scriptPolls))
            return
        }
        #endif
        updateEstimate(estimate)
    }

    // MARK: - DEBUG clock (research SHOW-011-D6) and estimate script (research ANL-006-D7)

    #if DEBUG
    /// Parses `<bpm>:<confidence>[:<polls>:<confidence2>]`: the first confidence for `polls` polls,
    /// then the second (one phase when the last two are missing); nil when malformed.
    static func estimateScript(_ text: String) -> ((Int) -> TempoEstimate?)? {
        let parts: [Double] = text.split(separator: ":").compactMap { (part: Substring) -> Double? in Double(part) }
        guard parts.count == 2 || parts.count == 4 else { return nil }
        let bpm: Double = parts[0]
        let first: Double = parts[1]
        let polls: Int = parts.count == 4 ? Int(parts[2]) : Int.max
        let second: Double = parts.count == 4 ? parts[3] : first
        return { (poll: Int) -> TempoEstimate? in
            let confidence: Double = poll <= polls ? first : second
            return TempoEstimate(bpm: bpm, confidence: confidence, beatNanoseconds: nil)
        }
    }

    /// A clock that advances by `stepMilliseconds` on every reading.
    static func syntheticClock(stepMilliseconds: Double) -> () -> UInt64 {
        var now: UInt64 = 1_000_000_000
        let step = UInt64(max(stepMilliseconds, 0) * 1_000_000)
        return {
            now += step
            return now
        }
    }
    #endif
}
