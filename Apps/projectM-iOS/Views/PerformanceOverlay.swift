// PerformanceOverlay.swift — frame rate and audio state over the visualization (task T103; FR-048).
// Shown only when the setting is on (off by default). Updates once a second, matching the
// renderer's 1-second metrics window. VIS-001: the metrics are the shown visual's (projectM's
// renderer or the circular spectrum). PERF-014-R14: a "render:" line with the shown visual's render
// health while anything was recorded (state, last reason, counts). AUD-012-R9: a "sanitized:" line
// with the number of samples the renderer boundary replaced, only when it is not zero (a count, never
// audio content). PERF-001-R9: per-stage frame timings (median/p95 ms per stage, the frame's GPU time) while
// the overlay is shown; asking for them each second also keeps the stage timer on the shown visual.
// PERF-002-R8: the budget lines follow the stage lines; "over budget:" lines are drawn in a highlight colour (the
// text itself says it, so colour is never the only cue) and stay inside the combined accessibility label, so
// VoiceOver reads them with the overlay. No announcement (research PERF-002-D5). PERF-007-R10: the "frames <output>"
// lines (presented, late, skipped per output) in their own text, `overlayFrameDrops`, inside the same combined label.
import CaptureKit
import CaptureUI
import FrameTiming
import Rendering
import SwiftUI

struct PerformanceOverlay: View {
    let metrics: () -> RenderMetrics
    let manager: CaptureManager
    /// PERF-014: nil while the shown visual's record is pristine.
    var renderHealth: () -> String? = { nil }
    /// PERF-001: the stage timer's lines (`FrameStageReport.lines`); empty when nothing is measured.
    var stageLines: () -> [String] = { [] }
    /// ANL-013: "stereo: r 0.98" (and "phase-inverted" while warned); nil without a native visual.
    var stereoLine: () -> String? = { nil }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let metrics = metrics()
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "%.0f fps", metrics.framesPerSecond))
                    .accessibilityIdentifier("overlayFPS")
                Text(String(format: "frame %.1f ms (max %.1f)", metrics.meanFrameTimeMs, metrics.maxFrameTimeMs))
                Text("audio: \(UIStrings.state(manager.state))")
                    .accessibilityIdentifier("overlayAudioState")
                if let sanitized = Self.sanitizedLine(manager.sanitizedSampleCount) {
                    Text(sanitized)
                        .accessibilityIdentifier("overlaySanitized")
                }
                if let render = renderHealth() {
                    Text("render: \(render)")
                        .accessibilityIdentifier("overlayRender")
                }
                if let stereo = stereoLine() {
                    Text(stereo)
                        .accessibilityIdentifier("overlayStereo")
                }
                stageSection(stageLines())
            }
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.white)
            .padding(6)
            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("performanceOverlay")
        }
        .allowsHitTesting(false)
    }

    /// PERF-001: one text line per stage line; PERF-002: the budget's flag lines highlighted below them.
    @ViewBuilder private func stageSection(_ lines: [String]) -> some View {
        let drops: (plain: [String], frames: [String]) = Self.splitFrameDrops(lines)
        let split: (plain: [String], flags: [String]) = Self.splitBudgetFlags(drops.plain)
        if !split.plain.isEmpty {
            Text(split.plain.joined(separator: "\n"))
                .accessibilityIdentifier("overlayStages")
        }
        if !split.flags.isEmpty {
            Text(split.flags.joined(separator: "\n"))
                .foregroundStyle(Color.orange)
                .fontWeight(.bold)
                .accessibilityIdentifier("overlayBudgetFlags")
        }
        if !drops.frames.isEmpty {
            Text(drops.frames.joined(separator: "\n"))
                .accessibilityIdentifier("overlayFrameDrops")
        }
    }

    /// PERF-007: separates the "frames …" lines (their own text) from the rest, keeping each group's order.
    static func splitFrameDrops(_ lines: [String]) -> (plain: [String], frames: [String]) {
        let frames: [String] = lines.filter { (line: String) -> Bool in line.hasPrefix(FrameDropCounts.linePrefix) }
        let plain: [String] = lines.filter { (line: String) -> Bool in !line.hasPrefix(FrameDropCounts.linePrefix) }
        return (plain, frames)
    }

    /// PERF-002: separates the "over budget:" lines (highlighted) from the rest, keeping each group's order.
    static func splitBudgetFlags(_ lines: [String]) -> (plain: [String], flags: [String]) {
        let flags: [String] = lines.filter { (line: String) -> Bool in line.hasPrefix(FrameBudgetVerdict.flagPrefix) }
        let plain: [String] = lines.filter { (line: String) -> Bool in !line.hasPrefix(FrameBudgetVerdict.flagPrefix) }
        return (plain, flags)
    }

    /// AUD-012-R9: "sanitized: 12 samples", or nil when nothing was replaced.
    static func sanitizedLine(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        let noun: String = count == 1 ? "sample" : "samples"
        return "sanitized: \(count) \(noun)"
    }
}
