// AppCoordinator+PerformanceReport.swift — PERF-012 (specs/209-perf-012-performance-report): gathers the session's
// counters for the performance report (R4-R8) and encodes it on the user's Export (R1-R3, R10).
//
// Gathered: the shown visual's kind; every frame interval measured since launch (`frameDrops.intervals`, fed while
// the performance overlay is shown); the PERF-007 counts and PERF-001 stage timings of the current overlay session;
// the state timeline and memory peak (`performanceRecorder`); the PERF-004 pool counters; device and app metadata.
// Nothing else of the session is read, so no media, name, path, text or address can reach the file (R9).
import Compositor
import Diagnostics
import FrameRecording
import FrameTiming
import Foundation

extension AppCoordinator {
    /// The shown visual's kind (the same order of precedence as `activeStageTimedVisual`).
    var performanceVisualKind: PerformanceVisualKind {
        guard screen == .visualizer else { return .none }
        if showsCameraVisual { return .camera }
        if showsPhotoVisual { return .photo }
        if showsVideoVisual { return .video }
        if showsTextVisual { return .text }
        if showsNativeVisual { return .native }
        return .projectM
    }

    func performanceReportInputs(exportedAt: Date) -> PerformanceReportInputs {
        Self.gatherPerformanceReportInputs(exportedAt: exportedAt, recorder: performanceRecorder, frameDrops: frameDrops,
                                           frameStages: frameStages, recording: videoRecording.frameDropStatistics,
                                           visual: performanceVisualKind, overlayShown: settings.showsPerformanceOverlay,
                                           pools: SharedTexturePool.allCounters)
    }

    /// Everything the report reads (the app and PerformanceReportAppTests use this one path).
    static func gatherPerformanceReportInputs(exportedAt: Date, recorder: PerformanceStateRecorder, frameDrops: FrameDropAttachment,
                                              frameStages: FrameStageAttachment,
                                              recording: (statistics: RecordingStatistics, live: Bool)?,
                                              visual: PerformanceVisualKind, overlayShown: Bool,
                                              pools: [TexturePoolCounters],
                                              footprint: Int? = ProcessMemory.footprintBytes(),
                                              available: Int? = ProcessMemory.availableBytes()) -> PerformanceReportInputs {
        recorder.sample()
        recorder.sampleMemory(footprint: footprint)
        let memory = PerformanceReport.Resources.Memory(footprintBytes: footprint, peakFootprintBytes: recorder.peakFootprintBytes,
                                                        availableBytes: available)
        let timings: DiagnosticsSnapshot.FrameTimings? = frameStages.timer.map { (timer: FrameStageTimer) -> DiagnosticsSnapshot.FrameTimings in
            exportTimings(timer.report())
        }
        return PerformanceReportInputs(exportedAt: exportedAt, device: DiagnosticsEnvironment.device(), app: DiagnosticsEnvironment.app(),
                                       sessionSeconds: recorder.elapsedSeconds, visual: visual, overlayShown: overlayShown,
                                       intervals: frameDrops.intervals.snapshot(),
                                       frameDrops: frameDrops.reportEntries(recording: recording), frameTimings: timings,
                                       current: recorder.currentSample(), timeline: recorder.timeline,
                                       truncated: recorder.truncated, pools: pools, memory: memory)
    }

    /// The report as the exported JSON; one signpost event per export (PERF-012-R10).
    func performanceReportData(exportedAt: Date) throws -> Data {
        let report: PerformanceReport = PerformanceReportBuilder.build(performanceReportInputs(exportedAt: exportedAt))
        let data: Data = try DiagnosticsExporter.encode(report)
        DiagnosticsLog.performanceReport(report.signpostSummary)
        return data
    }
}

extension FrameDropAttachment {
    /// PERF-012-R6: the attached display's counts and the recording's (as the overlay lines); empty while detached.
    func reportEntries(recording: (statistics: RecordingStatistics, live: Bool)?) -> [(FrameDropOutput, FrameDropCounts)] {
        guard let output, let counter = counter(for: output) else { return [] }
        var entries: [(FrameDropOutput, FrameDropCounts)] = [(output, counter.counts())]
        if let counts = recordingCounts(recording) { entries.append((.recording, counts)) }
        return entries
    }
}
