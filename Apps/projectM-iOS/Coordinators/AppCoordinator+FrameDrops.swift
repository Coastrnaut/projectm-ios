// AppCoordinator+FrameDrops.swift — PERF-007 (specs/192-perf-007-frame-drop-telemetry): frames presented, late and
// skipped per output while the performance overlay is shown.
//
// * One counter for the device display and one for the external display. The shown visual counts into the one for
//   the display it is on (OUT-001: one visual, one display at a time). Attaching begins a new session (counts zeroed):
//   the overlay turned on, the visualizer entered, the visual changed, or the visual moved between displays
//   (`ExternalDisplayCoordinator.onVisualOutputChange`, inside `place()`; registered at the first sync) (PERF-007-R6, research PERF-007-D3).
// * The recording's counts are REC-003/REC-006 statistics (frames written, dropped slots): the running recording's,
//   else the last finished one's if it ran while the overlay was shown.
// * Lines go after the stage and budget lines (`frameStageLines()`); the export is for the automation runner.
// * Local, in memory only: no stored key, no network (PERF-007-R12, R13).
import Diagnostics
import FrameRecording
import FrameTiming

/// Which visual counts into which output's counter (PERF-007-R6).
@MainActor
final class FrameDropAttachment {
    let device = FrameDropCounter()
    let external = FrameDropCounter()
    private(set) weak var visual: (any FrameDropCounted)?
    /// The output being counted; nil while nothing is attached.
    private(set) var output: FrameDropOutput?
    /// Sessions begun (tests).
    private(set) var sessionsBegun = 0
    /// A finished recording's line is shown only if a recording ran while counting was on.
    private var showsFinishedRecording = false

    func counter(for output: FrameDropOutput) -> FrameDropCounter? {
        switch output {
        case .device: return device
        case .external: return external
        case .recording: return nil
        }
    }

    /// Attaches the counter of the target's display while the overlay is shown; detaches everything otherwise.
    func sync(overlayShown: Bool, target: (any FrameDropCounted)?, external isExternal: Bool) {
        guard overlayShown, let target else {
            stop()
            return
        }
        let wanted: FrameDropOutput = isExternal ? .external : .device
        guard visual !== target || output != wanted else { return }
        visual?.frameDrops = nil
        guard let counter = counter(for: wanted) else { return }
        counter.beginSession(measuresPresentation: target.measuresPresentation)
        sessionsBegun += 1
        target.frameDrops = counter
        visual = target
        output = wanted
    }

    func stop() {
        visual?.frameDrops = nil
        visual = nil
        output = nil
        showsFinishedRecording = false
    }

    /// The display's line, then the recording's (contract C2); empty while nothing is attached.
    func lines(recording: (statistics: RecordingStatistics, live: Bool)?) -> [String] {
        guard let output, let counter = counter(for: output) else { return [] }
        var result: [String] = [counter.counts().line(for: output)]
        if let counts = recordingCounts(recording) { result.append(counts.line(for: .recording)) }
        return result
    }

    /// The recording's counts if it belongs to this counting session.
    func recordingCounts(_ recording: (statistics: RecordingStatistics, live: Bool)?) -> FrameDropCounts? {
        guard let recording else { return nil }
        if recording.live { showsFinishedRecording = true }
        guard recording.live || showsFinishedRecording else { return nil }
        return FrameDropCounts.recording(written: recording.statistics.written, droppedSlots: recording.statistics.droppedSlots)
    }
}

extension AppCoordinator {
    /// The shown visual as a frame drop counted path (the same choice as the stage timer's).
    var activeFrameDropVisual: (any FrameDropCounted)? { activeStageTimedVisual as? any FrameDropCounted }

    /// Attaches or moves the counters (each overlay refresh, and at once when the visual changes display).
    func syncFrameDrops() {
        if settings.showsPerformanceOverlay, externalDisplay.onVisualOutputChange == nil {
            externalDisplay.onVisualOutputChange = { [weak self] () -> Void in self?.syncFrameDrops() }   // PERF-007-R6
        }
        frameDrops.sync(overlayShown: settings.showsPerformanceOverlay, target: activeFrameDropVisual,
                        external: externalDisplay.showsVisualExternally)
    }

    /// The overlay's "frames …" lines (PERF-007-R10).
    func frameDropLines() -> [String] {
        syncFrameDrops()
        return frameDrops.lines(recording: videoRecording.frameDropStatistics)
    }

    /// PERF-007-R11: counts in the diagnostics format.
    nonisolated static func exportFrameDrops(_ entries: [(FrameDropOutput, FrameDropCounts)]) -> DiagnosticsSnapshot.FrameDrops {
        DiagnosticsSnapshot.FrameDrops(outputs: entries.map {
            (entry: (FrameDropOutput, FrameDropCounts)) -> DiagnosticsSnapshot.FrameDrops.Output in
            let counts: FrameDropCounts = entry.1
            return DiagnosticsSnapshot.FrameDrops.Output(output: entry.0.rawValue, submitted: counts.submitted, skipped: counts.skipped,
                                                         presented: counts.presented, late: counts.late,
                                                         discarded: counts.discarded, stale: counts.stale)
        })
    }
}
