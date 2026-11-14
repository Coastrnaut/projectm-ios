// AppCoordinator+FrameStages.swift — PERF-001 (specs/152-perf-001-stage-timings): per-stage frame timings
// while the performance overlay is shown.
//
// * One shared `FrameStageTimer` is attached to the shown visual only while the overlay is shown
//   (PERF-001-R8). The overlay asks for its lines once a second (`frameStageLines()`), which also follows
//   a visual change: attaching to another visual configures its pipeline and clears the window (R2).
// * Turning the overlay off (or leaving the visualizer) detaches the timer from every visual and drops it.
// * `exportTimings` converts a report to the diagnostics format (R10) for the automation runner.
// PERF-002 (specs/160-perf-002-gpu-budget): the attachment also holds the frame budget meter, reset with the
// window. The overlay's lines end with the verdict's budget, estimate and "over budget:" lines; the deadline is
// the lower of the screen's maximum refresh rate and the quality governor's cap (research PERF-002-D1). The meter
// reads only the report, once a second, so it never blocks or alters a frame (PERF-002-R6). DEBUG:
// `-uitestSlowStage <stage>:<ms>` replaces one stage's CPU figure in that report (contract C5), never the rendering.
// PERF-003 (specs/173-perf-003-adaptive-quality): while a native visual is shown, the verdict is its effect ladder's
// budget signal (any flag → over; the overlay off → unavailable), its frame-rate cap is the deadline's cap, and the
// lines end with its `effect quality …` line. The automation export carries the level.
// PERF-007 (specs/192-perf-007-frame-drop-telemetry): the "frames …" lines follow (AppCoordinator+FrameDrops.swift).
import ANGLERendering
import Diagnostics
import FrameTiming
import Rendering
import UIKit
import VisualEffects

/// Which visual holds the shared stage timer (PERF-001-R8). At most one visual at a time.
@MainActor
final class FrameStageAttachment {
    private(set) var timer: FrameStageTimer?
    private(set) weak var visual: (any FrameStageTimed)?
    /// PERF-002: judges the window; forgets its flags whenever the window restarts or timing stops.
    let budget = FrameBudgetMeter()
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
        budget.reset()
    }

    /// No visual measures anything any more.
    func stop() {
        visual?.stageTimer = nil
        visual = nil
        timer = nil
        budget.reset()
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

    /// The overlay's stage lines (PERF-001-R9) followed by the budget lines (PERF-002-R8); empty while the overlay
    /// is off or no visual is shown.
    func frameStageLines() -> [String] {
        frameStages.sync(overlayShown: settings.showsPerformanceOverlay, target: activeStageTimedVisual)
        guard let timer = frameStages.timer else {
            frameDrops.stop()
            return []
        }
        let drops: [String] = frameDropLines()   // PERF-007: after the stage and budget lines
        let report: FrameStageReport = Self.injectingSlowStage(timer.report())
        let native: NativeSpectrumHost? = showsNativeVisual ? nativeVisual : nil
        let cap: Int? = native?.qualitySettings.maxFramesPerSecond
        let verdict: FrameBudgetVerdict = frameStages.budget.evaluate(report, deadline: Self.frameDeadline(cap: cap))
        guard let native else { return report.lines + verdict.lines + drops }
        native.effectBudget = verdict.flagged.isEmpty ? .within : .over   // PERF-003-R3
        return report.lines + verdict.lines + [native.effectQualityLine] + drops
    }

    /// PERF-002-R1: the lower of the screen's maximum refresh rate and the frame-rate cap every visual's display
    /// link uses (FR-049).
    /// PERF-003: `cap` is the shown visual's own cap when it has one (the native host defers the serious-state cap).
    static func frameDeadline(cap: Int? = nil) -> FrameDeadline {
        let scene: UIWindowScene? = UIApplication.shared.connectedScenes.compactMap { (scene: UIScene) -> UIWindowScene? in
            scene as? UIWindowScene
        }.first
        let screenMaximum: Double? = scene.map { (scene: UIWindowScene) -> Double in Double(scene.screen.maximumFramesPerSecond) }
        let frameRateCap: Int = cap ?? QualityGovernor.current().maxFramesPerSecond
        return FrameDeadline(displayMaximumFPS: screenMaximum, frameRateCap: Double(frameRateCap))
    }

    /// The report as shown: unchanged, except in DEBUG with `-uitestSlowStage`.
    nonisolated static func injectingSlowStage(_ report: FrameStageReport) -> FrameStageReport {
        #if DEBUG
        guard let slow = SlowStageInjection.launch else { return report }
        return slow.apply(to: report)
        #else
        return report
        #endif
    }

    /// The overlay disappeared: no visual measures anything any more.
    func stopFrameStageTiming() {
        frameStages.stop()
        frameDrops.stop()   // PERF-007: the next attach begins a new session
        nativeVisual?.effectBudget = .unavailable   // PERF-003-R3: no verdict without the overlay
    }

    /// PERF-002-R9: the verdict in the diagnostics format.
    nonisolated static func exportBudget(_ verdict: FrameBudgetVerdict) -> DiagnosticsSnapshot.FrameTimings.Budget {
        DiagnosticsSnapshot.FrameTimings.Budget(
            framesPerSecond: verdict.deadline.framesPerSecond, deadlineMs: verdict.deadline.periodMs,
            thresholdShare: verdict.policy.thresholdShare, clearShare: verdict.policy.clearShare,
            thresholdMs: verdict.thresholdMs, cpuEstimateMs: verdict.cpuEstimateMs, gpuEstimateMs: verdict.gpuEstimateMs,
            flaggedPasses: verdict.flagged.map(\.label))
    }

    /// PERF-003-R10: a ladder's level and reason in the diagnostics format.
    nonisolated static func exportEffectQuality(level: EffectQualityLevel, reason: EffectQualityReason?) -> DiagnosticsSnapshot.FrameTimings.EffectQuality {
        DiagnosticsSnapshot.FrameTimings.EffectQuality(level: level.label, reason: reason?.rawValue)
    }

    nonisolated static func exportTimings(_ report: FrameStageReport, budget: FrameBudgetVerdict? = nil,
                                          effectQuality: DiagnosticsSnapshot.FrameTimings.EffectQuality? = nil) -> DiagnosticsSnapshot.FrameTimings {
        let stages: [DiagnosticsSnapshot.FrameTimings.Stage] = report.stages.map {
            (summary: FrameStageReport.StageSummary) -> DiagnosticsSnapshot.FrameTimings.Stage in
            let cpu = summary.cpu.exportValues
            let gpu = summary.gpu.exportValues
            return DiagnosticsSnapshot.FrameTimings.Stage(name: summary.label, samples: cpu.samples, cpuMedianMs: cpu.median,
                                                         cpuP95Ms: cpu.p95, gpuMedianMs: gpu.median, gpuP95Ms: gpu.p95)
        }
        let frameGPU = report.frameGPU.exportValues
        return DiagnosticsSnapshot.FrameTimings(windowFrames: report.frames, rejectedSamples: report.rejectedSamples,
                                                frameGPUMedianMs: frameGPU.median, frameGPUP95Ms: frameGPU.p95, stages: stages,
                                                budget: budget.map(exportBudget), effectQuality: effectQuality)
    }
}

#if DEBUG
/// PERF-002 contract C5: `-uitestSlowStage <stage>:<ms>` replaces that stage's CPU figure in the shown report
/// (median and p95 = ms, the stage's real sample count). Nothing when the stage is absent or has no samples.
struct SlowStageInjection: Equatable {
    static let argument = "-uitestSlowStage"

    let stage: FrameStage
    let milliseconds: Double

    /// "composite:14.2" → composite, 14.2 ms; nil for an unknown stage or a non-finite or negative time.
    static func parse(_ text: String) -> SlowStageInjection? {
        let parts: [Substring] = text.split(separator: ":")
        guard parts.count == 2,
              let stage = FrameStage.allCases.first(where: { (stage: FrameStage) -> Bool in stage.label == String(parts[0]) }),
              let ms = Double(String(parts[1])), ms.isFinite, ms >= 0 else { return nil }
        return SlowStageInjection(stage: stage, milliseconds: ms)
    }

    nonisolated static var launch: SlowStageInjection? {
        let arguments: [String] = ProcessInfo.processInfo.arguments
        guard let i = arguments.firstIndex(of: argument), i + 1 < arguments.count else { return nil }
        return parse(arguments[i + 1])
    }

    func apply(to report: FrameStageReport) -> FrameStageReport {
        var result = report
        for index in result.stages.indices where result.stages[index].stage == stage {
            guard case let .measured(samples, _, _) = result.stages[index].cpu else { continue }
            result.stages[index].cpu = .measured(samples: samples, medianMs: milliseconds, p95Ms: milliseconds)
        }
        return result
    }
}
#endif

private extension StageStatistic {
    var exportValues: (samples: Int, median: Double?, p95: Double?) {
        guard case let .measured(samples, median, p95) = self else { return (0, nil, nil) }
        return (samples, median, p95)
    }
}
