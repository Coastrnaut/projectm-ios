// PerformanceReportBuilder.swift — PERF-012 (specs/209-perf-012-performance-report, R4-R9; research PERF-012-D4):
// turns the session's counters into a `PerformanceReport`.
//
// The inputs hold counters, fixed-set states and system metadata only: there is no field through which media, a file
// name, a path, a preset, scene, text overlay or recording name, an OSC address or user text could reach the report.
// `AppCoordinator.performanceReportInputs(exportedAt:)` gathers them; the export encodes the result locally.
import Compositor
import Diagnostics
import FrameTiming
import Foundation

/// The shown visual, as the report names it (PERF-012 Clarifications: the kind only, never what it shows).
enum PerformanceVisualKind: String, CaseIterable, Sendable {
    case projectM
    case native
    case camera
    case photo
    case video
    case text
    case none
}

struct PerformanceReportInputs {
    var exportedAt: Date
    var device: DiagnosticsSnapshot.Device
    var app: DiagnosticsSnapshot.App
    var sessionSeconds: Double
    var visual: PerformanceVisualKind
    var overlayShown: Bool
    var intervals: FrameIntervalHistogram
    var frameDrops: [(FrameDropOutput, FrameDropCounts)]
    var frameTimings: DiagnosticsSnapshot.FrameTimings?
    var current: PerformanceReport.StateSample
    var timeline: [PerformanceReport.StateSample]
    var truncated: Bool
    var pools: [TexturePoolCounters]
    var memory: PerformanceReport.Resources.Memory
}

enum PerformanceReportBuilder {
    static func build(_ inputs: PerformanceReportInputs) -> PerformanceReport {
        let drops: DiagnosticsSnapshot.FrameDrops? = inputs.frameDrops.isEmpty ? nil : AppCoordinator.exportFrameDrops(inputs.frameDrops)
        let session = PerformanceReport.Session(durationSeconds: inputs.sessionSeconds, visual: inputs.visual.rawValue,
                                                overlayShown: inputs.overlayShown)
        let states = PerformanceReport.States(current: inputs.current, timeline: inputs.timeline, truncated: inputs.truncated)
        let resources = PerformanceReport.Resources(texturePool: poolSection(inputs.pools), memory: inputs.memory)
        return PerformanceReport(exportedAt: inputs.exportedAt, device: inputs.device, app: inputs.app, session: session,
                                 frames: frames(inputs.intervals), frameDrops: drops, frameTimings: inputs.frameTimings,
                                 states: states, resources: resources)
    }

    /// PERF-012-R5: percentiles, max, counts; absent when nothing was measured.
    static func frames(_ h: FrameIntervalHistogram) -> PerformanceReport.Frames {
        let thresholds: [Double] = FrameIntervalHistogram.longFrameThresholdsMs
        let long: [PerformanceReport.Frames.LongFrames] = thresholds.indices.map { (i: Int) -> PerformanceReport.Frames.LongFrames in
            PerformanceReport.Frames.LongFrames(thresholdMs: thresholds[i], count: h.longFrames[i])
        }
        let maxMs: Double? = h.count > 0 ? h.maxMs : nil
        return PerformanceReport.Frames(sampleCount: h.count, measuredSeconds: h.measuredSeconds,
                                        resolutionMs: FrameIntervalHistogram.resolutionMs,
                                        p50Ms: h.percentile(0.5), p90Ms: h.percentile(0.9), p95Ms: h.percentile(0.95),
                                        p99Ms: h.percentile(0.99), maxMs: maxMs, longFrames: long)
    }

    /// PERF-004 counters summed over the pools; absent when no pool exists yet.
    static func poolSection(_ pools: [TexturePoolCounters]) -> PerformanceReport.Resources.TexturePool? {
        guard !pools.isEmpty else { return nil }
        var sum = TexturePoolCounters()
        for c in pools {
            sum.checkedOutTextures += c.checkedOutTextures
            sum.checkedOutBytes += c.checkedOutBytes
            sum.retiredTextures += c.retiredTextures
            sum.retiredBytes += c.retiredBytes
            sum.hits += c.hits
            sum.misses += c.misses
            sum.evictions += c.evictions
            sum.purges += c.purges
        }
        return PerformanceReport.Resources.TexturePool(pools: pools.count, liveTextures: sum.liveTextures, liveBytes: sum.liveBytes,
                                                       retiredTextures: sum.retiredTextures, retiredBytes: sum.retiredBytes,
                                                       hits: sum.hits, misses: sum.misses, evictions: sum.evictions,
                                                       purges: sum.purges)
    }
}
