// FrameStageReport.swift — what the timer reports (PERF-001-R2, R3, R9; contracts/frame-stage-timer.md C2, C3).
import Foundation

/// A stage's figure over the window: unavailable, or measured (milliseconds, finite, ≥ 0). Never 0 or NaN
/// in place of a missing value (PERF-001-R3).
public enum StageStatistic: Sendable, Equatable {
    case unavailable
    case measured(samples: Int, medianMs: Double, p95Ms: Double)

    /// Median (mean of the two middle values for an even count) and nearest-rank p95 (sorted index
    /// ⌈0.95·n⌉ − 1) of durations in seconds; unavailable without samples.
    public init(seconds samples: [Double]) {
        guard !samples.isEmpty else {
            self = .unavailable
            return
        }
        let sorted = samples.sorted()
        let n = sorted.count
        let median: Double = n % 2 == 1 ? sorted[n / 2] : (sorted[n / 2 - 1] + sorted[n / 2]) / 2
        let rank: Int = Int((0.95 * Double(n)).rounded(.up))
        let p95: Double = sorted[min(n - 1, max(0, rank - 1))]
        self = .measured(samples: n, medianMs: median * 1000, p95Ms: p95 * 1000)
    }

    public var isAvailable: Bool { self != .unavailable }

    /// "0.05/0.09" (median/p95 ms), or nil when unavailable.
    var text: String? {
        guard case let .measured(_, median, p95) = self else { return nil }
        return String(format: "%.2f/%.2f", median, p95)
    }
}

public struct FrameStageReport: Sendable, Equatable {
    public struct StageSummary: Sendable, Equatable {
        public var stage: FrameStage
        public var cpu: StageStatistic
        public var gpu: StageStatistic
        public var label: String { stage.label }

        public init(stage: FrameStage, cpu: StageStatistic, gpu: StageStatistic) {
            self.stage = stage
            self.cpu = cpu
            self.gpu = gpu
        }
    }

    /// Frames in the window (≤ capacity).
    public var frames: Int
    /// The pipeline's stages in frame order; a conditional stage only when measured.
    public var stages: [StageSummary]
    /// The whole frame's GPU time (one command buffer for all stages), or unavailable.
    public var frameGPU: StageStatistic
    public var rejectedSamples: Int

    public init(frames: Int, stages: [StageSummary], frameGPU: StageStatistic, rejectedSamples: Int) {
        self.frames = frames
        self.stages = stages
        self.frameGPU = frameGPU
        self.rejectedSamples = rejectedSamples
    }

    public var labels: [String] { stages.map(\.label) }

    public static let header = "stages ms (median/p95)"

    /// The overlay's lines (contract C3).
    public var lines: [String] {
        var result: [String] = [Self.header]
        for summary in stages {
            var line: String = summary.label + " " + (summary.cpu.text ?? "–")
            if let gpuText = summary.gpu.text { line += " gpu " + gpuText }
            result.append(line)
        }
        result.append(frameGPU.text.map { (text: String) -> String in "gpu " + text } ?? "gpu unavailable")
        if rejectedSamples > 0 { result.append("rejected \(rejectedSamples)") }
        return result
    }
}
