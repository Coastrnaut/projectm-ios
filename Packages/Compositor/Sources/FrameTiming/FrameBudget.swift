// FrameBudget.swift — the frame budget meter (PERF-002-R1 to R7, R11; specs/160-perf-002-gpu-budget,
// contracts/frame-budget-meter.md C1-C3; research PERF-002-D1 to D4).
//
// * `FrameDeadline`: the target frame rate (the lower of the display's maximum and the visual's cap; 60 fps
//   when neither is valid) and its period.
// * `FrameBudgetMeter.evaluate` judges a `FrameStageReport` against the deadline: per pass (a stage's CPU
//   figure, a stage's GPU figure where measured, the whole frame's GPU time) the p95 against a share of the
//   deadline, with hysteresis and a minimum sample count. Unavailable figures are shown as unavailable and
//   never flagged; nothing is estimated (PERF-002-D2: no per-pass GPU split exists, so a GPU-heavy pass shows
//   as "gpu frame").
// * Purely observational (PERF-002-R6): the meter sees only the report, never a renderer or the timer, and
//   runs off the frame path (once a second with the overlay). Its only state is a 13-bit flag mask.
import Foundation

/// The time one frame may take (contract C1).
public struct FrameDeadline: Sendable, Equatable {
    public static let fallbackFramesPerSecond: Double = 60

    public let framesPerSecond: Double

    /// The lower of the valid (finite, > 0) inputs; 60 fps when neither is valid.
    public init(displayMaximumFPS: Double?, frameRateCap: Double?) {
        let valid: [Double] = [displayMaximumFPS, frameRateCap].compactMap { (value: Double?) -> Double? in
            guard let value, value.isFinite, value > 0 else { return nil }
            return value
        }
        framesPerSecond = valid.min() ?? Self.fallbackFramesPerSecond
    }

    public init(framesPerSecond: Double) {
        self.init(displayMaximumFPS: framesPerSecond, frameRateCap: nil)
    }

    public var periodMs: Double { 1000 / framesPerSecond }
}

/// Threshold and clear level as shares of the deadline, and the samples needed to change a flag (PERF-002-R2, R11).
public struct FrameBudgetPolicy: Sendable, Equatable {
    public static let defaultThresholdShare: Double = 0.80
    public static let defaultClearShare: Double = 0.70
    public static let defaultMinimumSamples = 30

    public let thresholdShare: Double
    public let clearShare: Double
    public let minimumSamples: Int

    /// Clamps: threshold to (0, 1] (invalid → 0.80), clear level to (0, threshold] (invalid → min(0.70, threshold)),
    /// minimum samples to ≥ 1.
    public init(thresholdShare: Double = FrameBudgetPolicy.defaultThresholdShare,
                clearShare: Double = FrameBudgetPolicy.defaultClearShare,
                minimumSamples: Int = FrameBudgetPolicy.defaultMinimumSamples) {
        let threshold: Double = thresholdShare.isFinite && thresholdShare > 0 ? min(thresholdShare, 1) : Self.defaultThresholdShare
        let clear: Double = clearShare.isFinite && clearShare > 0 ? min(clearShare, threshold) : min(Self.defaultClearShare, threshold)
        self.thresholdShare = threshold
        self.clearShare = clear
        self.minimumSamples = max(1, minimumSamples)
    }

    public static let standard = FrameBudgetPolicy()
}

/// Where a figure was measured.
public enum BudgetDomain: String, Sendable, Equatable {
    case cpu
    case gpu
}

/// One judged figure: a stage in a domain, or the whole frame's GPU time.
public enum BudgetPass: Sendable, Hashable {
    case stage(FrameStage, BudgetDomain)
    case frameGPU

    /// "composite cpu", "render gpu", "gpu frame".
    public var label: String {
        switch self {
        case let .stage(stage, domain): return stage.label + " " + domain.rawValue
        case .frameGPU: return "gpu frame"
        }
    }

    /// The stage, or nil for the whole frame.
    public var stage: FrameStage? {
        guard case let .stage(stage, _) = self else { return nil }
        return stage
    }

    /// Bit in the meter's flag mask: cpu 0-5, gpu 6-11, frame GPU 12.
    var bit: UInt16 {
        switch self {
        case let .stage(stage, .cpu): return UInt16(1) << UInt16(stage.rawValue)
        case let .stage(stage, .gpu): return UInt16(1) << UInt16(FrameStage.count + stage.rawValue)
        case .frameGPU: return UInt16(1) << UInt16(2 * FrameStage.count)
        }
    }
}

/// A pass's figure and verdict.
public struct PassStatus: Sendable, Equatable {
    public var pass: BudgetPass
    /// The p95 in ms, or nil when unavailable.
    public var p95Ms: Double?
    public var samples: Int
    /// Over budget (never for an unavailable pass).
    public var isOver: Bool

    public var isAvailable: Bool { p95Ms != nil }
}

/// What the meter concluded for one report (data-model.md).
public struct FrameBudgetVerdict: Sendable, Equatable {
    public var deadline: FrameDeadline
    public var policy: FrameBudgetPolicy
    public var passes: [PassStatus]
    /// Sum of the measured stages' CPU p95, or nil when none was measured.
    public var cpuEstimateMs: Double?
    /// The whole frame's GPU p95, or nil when unavailable.
    public var gpuEstimateMs: Double?

    public var thresholdMs: Double { deadline.periodMs * policy.thresholdShare }
    public var clearMs: Double { deadline.periodMs * policy.clearShare }
    public var flagged: [BudgetPass] { passes.filter(\.isOver).map(\.pass) }

    public static let flagPrefix = "over budget:"

    /// The overlay's lines (contract C3).
    public var lines: [String] {
        let fps: Int = Int(deadline.framesPerSecond.rounded())
        let percent: Int = Int((policy.thresholdShare * 100).rounded())
        var result: [String] = []
        result.append("budget " + Self.ms(deadline.periodMs) + " ms @\(fps) fps, limit " + Self.ms(thresholdMs) + " ms (\(percent)%)")
        let cpu: String = cpuEstimateMs.map { (value: Double) -> String in "cpu " + Self.ms(value) + " ms" } ?? "cpu unavailable"
        let gpu: String = gpuEstimateMs.map { (value: Double) -> String in "gpu " + Self.ms(value) + " ms" } ?? "gpu unavailable"
        result.append("estimate " + cpu + ", " + gpu)
        for status in passes where status.isOver {
            guard let p95 = status.p95Ms else { continue }
            result.append(Self.flagPrefix + " " + status.pass.label + " " + Self.ms(p95) + " ms > " + Self.ms(thresholdMs) + " ms")
        }
        return result
    }

    static func ms(_ value: Double) -> String { String(format: "%.2f", value) }
}

/// Judges stage reports against the frame deadline, with hysteresis (contract C2). One per window; reset it
/// when the window restarts.
public final class FrameBudgetMeter {
    public let policy: FrameBudgetPolicy
    /// Over-budget passes (bits per `BudgetPass.bit`).
    public private(set) var flags: UInt16 = 0

    public init(policy: FrameBudgetPolicy = .standard) {
        self.policy = policy
    }

    /// Forgets every flag (a new visual, the overlay turned off).
    public func reset() { flags = 0 }

    public func evaluate(_ report: FrameStageReport, deadline: FrameDeadline) -> FrameBudgetVerdict {
        let threshold: Double = deadline.periodMs * policy.thresholdShare
        let clear: Double = deadline.periodMs * policy.clearShare
        var passes: [PassStatus] = []
        var cpuSum: Double = 0
        var cpuMeasured = false
        for summary in report.stages {
            if case let .measured(_, _, p95) = summary.cpu {
                cpuSum += p95
                cpuMeasured = true
            }
            passes.append(judge(.stage(summary.stage, .cpu), summary.cpu, threshold: threshold, clear: clear))
            if summary.gpu.isAvailable {
                passes.append(judge(.stage(summary.stage, .gpu), summary.gpu, threshold: threshold, clear: clear))
            } else {
                flags &= ~BudgetPass.stage(summary.stage, .gpu).bit
            }
        }
        // Stages no longer reported (encode after a recording) lose their flags.
        var reported: UInt16 = 0
        for status in passes { reported |= status.pass.bit }
        let stageBits: UInt16 = (UInt16(1) << UInt16(2 * FrameStage.count)) - 1
        flags &= ~(stageBits & ~reported)
        let frame: PassStatus = judge(.frameGPU, report.frameGPU, threshold: threshold, clear: clear)
        passes.append(frame)
        return FrameBudgetVerdict(deadline: deadline, policy: policy, passes: passes,
                                  cpuEstimateMs: cpuMeasured ? cpuSum : nil, gpuEstimateMs: frame.p95Ms)
    }

    private func judge(_ pass: BudgetPass, _ statistic: StageStatistic, threshold: Double, clear: Double) -> PassStatus {
        guard case let .measured(samples, _, p95) = statistic else {
            flags &= ~pass.bit   // unavailable: never flagged
            return PassStatus(pass: pass, p95Ms: nil, samples: 0, isOver: false)
        }
        if samples >= policy.minimumSamples {
            if p95 > threshold {
                flags |= pass.bit
            } else if p95 < clear {
                flags &= ~pass.bit
            }
        }
        return PassStatus(pass: pass, p95Ms: p95, samples: samples, isOver: flags & pass.bit != 0)
    }
}
