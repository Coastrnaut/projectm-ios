// AppCoordinator+FrameStages.swift — PERF-001 (specs/152-perf-001-stage-timings): per-stage frame timings
// while the performance overlay is shown.
//
// * One shared `FrameStageTimer` is attached to the shown visual only while the overlay is shown
//   (PERF-001-R8). The overlay asks for its lines once a second (`frameStageLines()`), which also follows
//   a visual change: attaching to another visual configures its pipeline and clears the window (R2).
// * Turning the overlay off (or leaving the visualizer) detaches the timer from every visual and drops it.
// * `exportTimings` converts a report to the diagnostics format (R10) for the automation runner.
import ANGLERendering
import Diagnostics
import FrameTiming

/// Which visual holds the shared stage timer (PERF-001-R8). At most one visual at a time.
@MainActor
final class FrameStageAttachment {
    private(set) var timer: FrameStageTimer?
    private(set) weak var visual: (any FrameStageTimed)?
    private let makeTimer: () -> FrameStageTimer

    init(makeTimer: @escaping () -> FrameStageTimer = { FrameStageTimer() }) {
        self.makeTimer = makeTimer
    }

    /// Attaches the timer to `target` while the overlay is shown; detaches everything otherwise.
    func sync(overlayShown: Bool, target: (any FrameStageTimed)?) {
        guard overlayShown, let target else {
            stop()
            return
        }
        let shared: FrameStageTimer = timer ?? makeTimer()
        timer = shared
        guard visual !== target else { return }
        visual?.stageTimer = nil
        target.stageTimer = shared   // configures the visual's pipeline and clears the window
        visual = target
    }

    /// No visual measures anything any more.
    func stop() {
        visual?.stageTimer = nil
        visual = nil
        timer = nil
    }
}

extension AppCoordinator {
    /// The shown visual's stage-timed frame loop (the same choice as `activeVisualMetrics`).
    var activeStageTimedVisual: (any FrameStageTimed)? {
        guard screen == .visualizer else { return nil }
        if showsCameraVisual { return cameraVisual }
        if showsPhotoVisual { return photoVisual }
        if showsVideoVisual { return videoVisual }
        if showsTextVisual { return textVisual }
        if showsNativeVisual { return nativeVisual }
        return renderer as? ANGLERenderer
    }

    /// The overlay's stage lines (PERF-001-R9); empty while the overlay is off or no visual is shown.
    func frameStageLines() -> [String] {
        frameStages.sync(overlayShown: settings.showsPerformanceOverlay, target: activeStageTimedVisual)
        return frameStages.timer?.report().lines ?? []
    }

    /// The overlay disappeared: no visual measures anything any more.
    func stopFrameStageTiming() { frameStages.stop() }

    nonisolated static func exportTimings(_ report: FrameStageReport) -> DiagnosticsSnapshot.FrameTimings {
        let stages: [DiagnosticsSnapshot.FrameTimings.Stage] = report.stages.map {
            (summary: FrameStageReport.StageSummary) -> DiagnosticsSnapshot.FrameTimings.Stage in
            let cpu = summary.cpu.exportValues
            let gpu = summary.gpu.exportValues
            return DiagnosticsSnapshot.FrameTimings.Stage(name: summary.label, samples: cpu.samples, cpuMedianMs: cpu.median,
                                                         cpuP95Ms: cpu.p95, gpuMedianMs: gpu.median, gpuP95Ms: gpu.p95)
        }
        let frameGPU = report.frameGPU.exportValues
        return DiagnosticsSnapshot.FrameTimings(windowFrames: report.frames, rejectedSamples: report.rejectedSamples,
                                                frameGPUMedianMs: frameGPU.median, frameGPUP95Ms: frameGPU.p95, stages: stages)
    }
}

private extension StageStatistic {
    var exportValues: (samples: Int, median: Double?, p95: Double?) {
        guard case let .measured(samples, median, p95) = self else { return (0, nil, nil) }
        return (samples, median, p95)
    }
}
