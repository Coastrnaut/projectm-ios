// AppCoordinator+FeatureAge.swift — PERF-013 (specs/216-perf-013-audio-render-sync, R2, R7-R10; contracts/feature-age.md
// C2, C3): the age of the analysed audio features at frame presentation, while the performance overlay is shown.
//
// * One app-wide `FeatureAgeMeter` (its app-session histogram feeds the PERF-012 report). The attachment sets it on the
//   shown visual while the overlay is shown, like PERF-007's counters; attaching to another visual (or after the
//   overlay was off) begins a counting session, which also restarts the drift estimate: another visual has its own
//   analysis pipeline, whose session and sequence numbers start over. projectM consumes no feature frames: the line reads "unavailable".
// * The overlay asks for the line once a second (`frameStageLines()`); the same refresh emits the drift-verdict
//   signpost when the verdict changed since the last refresh (R10): never from the frame path.
// * Local, in memory only: no stored key, no network, nothing passed to projectM (R11).
import AudioCore
import Diagnostics
import FrameTiming

/// Which visual feeds the shared feature age meter (PERF-013-R11). At most one visual at a time.
@MainActor
final class FeatureAgeAttachment {
    let meter: FeatureAgeMeter
    private(set) weak var visual: (any FeatureAgeMeasured)?
    /// Counting sessions begun (tests).
    private(set) var sessionsBegun = 0
    /// The verdict at the last refresh (signpost on change).
    private var lastDetected = false
    /// Signposts emitted (tests).
    private(set) var verdictEvents: [String] = []
    private let emit: (String) -> Void

    init(meter: FeatureAgeMeter = FeatureAgeMeter(), emit: @escaping (String) -> Void = { (s: String) -> Void in DiagnosticsLog.audioSync(s) }) {
        self.meter = meter
        self.emit = emit
    }

    /// Attaches the meter to `target` while the overlay is shown; detaches otherwise. A nil target (projectM) detaches.
    func sync(overlayShown: Bool, target: (any FeatureAgeMeasured)?) {
        guard overlayShown, let target else {
            stop()
            return
        }
        guard visual !== target else { return }
        visual?.featureAge = nil
        meter.beginCountingSession()
        sessionsBegun += 1
        target.featureAge = meter
        visual = target
    }

    func stop() {
        visual?.featureAge = nil
        visual = nil
    }

    /// The overlay line (contract C2); also emits the verdict signpost on a change (C3).
    func line(offsetMilliseconds: Double) -> String {
        let summary: FeatureAgeSummary = meter.summary()
        noteVerdict(summary)
        guard visual != nil else { return Self.unavailableLine }
        return Self.line(summary, offsetMilliseconds: offsetMilliseconds)
    }

    private func noteVerdict(_ summary: FeatureAgeSummary) {
        guard summary.driftDetected != lastDetected else { return }
        lastDetected = summary.driftDetected
        let event: String = summary.driftDetected
            ? "drift detected " + Self.decimal(summary.driftPPM ?? 0) + " ppm"
            : "drift cleared"
        verdictEvents.append(event)
        emit(event)
    }

    static let unavailableLine = "audio age unavailable"

    /// "audio age 24.1 ms p95 31.0 ms[ offset 40 ms][, drift -512.3 ppm corrected]".
    static func line(_ summary: FeatureAgeSummary, offsetMilliseconds: Double) -> String {
        guard let smoothed = summary.smoothedMs, let p95 = summary.p95Ms else { return unavailableLine }
        var text: String = "audio age " + decimal(smoothed) + " ms p95 " + decimal(p95) + " ms"
        if offsetMilliseconds > 0 {
            let whole: Int = Int(offsetMilliseconds.rounded())
            text += " offset " + String(whole) + " ms"
        }
        if summary.driftDetected, let ppm = summary.driftPPM {
            text += ", drift " + decimal(ppm) + " ppm corrected"
        }
        return text
    }

    /// One decimal place, POSIX style ("24.1", "-512.3").
    static func decimal(_ value: Double) -> String {
        let tenths: Double = (value * 10).rounded()
        let negative: Bool = tenths < 0
        let magnitude: Int = Int(abs(tenths))
        let body: String = String(magnitude / 10) + "." + String(magnitude % 10)
        return negative ? "-" + body : body
    }
}

extension AppCoordinator {
    /// The shown visual as a feature-age measured path (the same choice as the stage timer's; projectM → nil).
    var activeFeatureAgeVisual: (any FeatureAgeMeasured)? { activeStageTimedVisual as? any FeatureAgeMeasured }

    /// The overlay's "audio age …" line (PERF-013-R8), after the frame-drop lines.
    func featureAgeLines() -> [String] {
        featureAges.sync(overlayShown: settings.showsPerformanceOverlay, target: activeFeatureAgeVisual)
        let offset: Double = latencyOffset.activeMode.map { (mode: AudioSourceMode) -> Double in latencyOffset.milliseconds(for: mode) } ?? 0
        return [featureAges.line(offsetMilliseconds: offset)]
    }
}
