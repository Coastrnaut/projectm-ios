// FrameStageTimer.swift — per-stage frame timings over a fixed window of recent frames (PERF-001-R1 to R7;
// specs/152-perf-001-stage-timings, contracts/frame-stage-timer.md C1, C2; research PERF-001-D2, D5, D6).
//
// * CPU time per stage from an injected monotonic nanosecond clock (`begin`/`end`), or a measured duration
//   (`record(_:cpuSeconds:)`). GPU time per stage (`record(_:gpuSeconds:)`) or for the whole frame
//   (`recordFrameGPU`), only from values the platform reported; never estimated.
// * Rejected, counted and never stored: NaN, ±∞, negative durations and an end before its begin (a clock
//   that went backwards).
// * Storage is preallocated when the timer is made: the frame path (`beginFrame`, `begin`, `end`, `record…`,
//   `endFrame`) mutates arrays in place and never allocates or locks. The timer belongs to one thread (the
//   frame thread; every frame loop of the app runs on the main thread) and is never touched by an audio
//   callback (T063). `report()` allocates and sorts; call it off the frame path (the overlay, once a second).
import Foundation

public final class FrameStageTimer {
    /// 120 frames: 2 s at 60 fps.
    public static let defaultCapacity = 120

    public let capacity: Int
    private let clock: () -> UInt64

    /// The stages this pipeline has, in frame order (`configure(pipeline:)`).
    public private(set) var pipeline: [FrameStage] = []
    private var pipelineMask: UInt16 = 0

    // The ring: per frame, a mask (bits 0-5 CPU measured, bits 8-13 GPU measured) and seconds per stage.
    private var cpu: [Double]
    private var gpu: [Double]
    private var masks: [UInt16]
    private var frameCount = 0
    private var nextFrame = 0
    // The whole frame's GPU times arrive frames later (command buffers complete asynchronously): own ring.
    private var frameGPU: [Double]
    private var frameGPUCount = 0
    private var nextFrameGPU = 0
    /// Samples rejected since the window started (PERF-001-R4).
    public private(set) var rejectedSamples = 0

    // The frame being measured.
    private var starts: [UInt64]
    private var begun: UInt16 = 0
    private var currentCPU: [Double]
    private var currentGPU: [Double]
    private var currentMask: UInt16 = 0

    public init(capacity: Int = FrameStageTimer.defaultCapacity, clock: @escaping () -> UInt64 = FrameStageTimer.systemClock) {
        let size = max(1, capacity)
        self.capacity = size
        self.clock = clock
        cpu = [Double](repeating: 0, count: size * FrameStage.count)
        gpu = [Double](repeating: 0, count: size * FrameStage.count)
        masks = [UInt16](repeating: 0, count: size)
        frameGPU = [Double](repeating: 0, count: size)
        starts = [UInt64](repeating: 0, count: FrameStage.count)
        currentCPU = [Double](repeating: 0, count: FrameStage.count)
        currentGPU = [Double](repeating: 0, count: FrameStage.count)
    }

    /// Monotonic uptime in nanoseconds (research PERF-001-D2).
    public static func systemClock() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

    /// The injected clock's current reading (for splits measured elsewhere, such as the compositor's mark).
    public func now() -> UInt64 { clock() }

    /// Sets the stages of the visual being measured and clears the window (a new visual, PERF-001-R2).
    public func configure(pipeline stages: [FrameStage]) {
        var seen: UInt16 = 0
        var ordered: [FrameStage] = []
        for stage in FrameStage.allCases where stages.contains(stage) && seen & stage.bit == 0 {
            seen |= stage.bit
            ordered.append(stage)
        }
        pipeline = ordered
        pipelineMask = seen
        reset()
    }

    /// Forgets every frame, the frame in progress and the rejected count.
    public func reset() {
        frameCount = 0
        nextFrame = 0
        frameGPUCount = 0
        nextFrameGPU = 0
        rejectedSamples = 0
        clearCurrent()
    }

    // MARK: - Frame path (no allocation, no lock)

    /// Starts a frame; anything begun and not ended in the previous frame is dropped.
    public func beginFrame() { clearCurrent() }

    public func begin(_ stage: FrameStage) {
        guard pipelineMask & stage.bit != 0 else { return }
        starts[stage.rawValue] = clock()
        begun |= stage.bit
    }

    /// Records the time since `begin(stage)`; nothing when the stage was not begun in this frame.
    public func end(_ stage: FrameStage) {
        guard begun & stage.bit != 0 else { return }
        let now = clock()
        begun &= ~stage.bit
        let start = starts[stage.rawValue]
        guard now >= start else {   // the clock went backwards: a negative delta
            rejectedSamples &+= 1
            return
        }
        accumulateCPU(stage, Double(now - start) / 1e9)
    }

    /// Records a CPU duration measured elsewhere. False (and counted) when rejected.
    @discardableResult
    public func record(_ stage: FrameStage, cpuSeconds seconds: Double) -> Bool {
        guard pipelineMask & stage.bit != 0 else { return false }
        guard Self.isValid(seconds) else {
            rejectedSamples &+= 1
            return false
        }
        accumulateCPU(stage, seconds)
        return true
    }

    /// Records a stage's GPU duration reported by the platform. False (and counted) when rejected.
    @discardableResult
    public func record(_ stage: FrameStage, gpuSeconds seconds: Double) -> Bool {
        guard pipelineMask & stage.bit != 0 else { return false }
        guard Self.isValid(seconds) else {
            rejectedSamples &+= 1
            return false
        }
        let gpuBit: UInt16 = stage.bit << 8
        currentGPU[stage.rawValue] = (currentMask & gpuBit != 0 ? currentGPU[stage.rawValue] : 0) + seconds
        currentMask |= gpuBit
        return true
    }

    /// Records the whole frame's GPU time (all stages in one command buffer). False (and counted) when rejected.
    @discardableResult
    public func recordFrameGPU(seconds: Double) -> Bool {
        guard Self.isValid(seconds) else {
            rejectedSamples &+= 1
            return false
        }
        frameGPU[nextFrameGPU] = seconds
        nextFrameGPU = (nextFrameGPU + 1) % capacity
        frameGPUCount = min(frameGPUCount + 1, capacity)
        return true
    }

    /// Commits the frame into the window, overwriting the oldest; a frame that measured nothing is not kept.
    public func endFrame() {
        defer { clearCurrent() }
        guard currentMask != 0 else { return }
        let slot = nextFrame
        let base = slot * FrameStage.count
        masks[slot] = currentMask
        for index in 0..<FrameStage.count {
            cpu[base + index] = currentCPU[index]
            gpu[base + index] = currentGPU[index]
        }
        nextFrame = (slot + 1) % capacity
        frameCount = min(frameCount + 1, capacity)
    }

    // MARK: - Report (allocates; off the frame path)

    public func report() -> FrameStageReport {
        var stages: [FrameStageReport.StageSummary] = []
        for stage in pipeline {
            let cpuSamples = samples(of: stage, bitShift: 0, from: cpu)
            let gpuSamples = samples(of: stage, bitShift: 8, from: gpu)
            if stage.isConditional && cpuSamples.isEmpty && gpuSamples.isEmpty { continue }   // PERF-001-R5
            stages.append(FrameStageReport.StageSummary(stage: stage, cpu: StageStatistic(seconds: cpuSamples),
                                                        gpu: StageStatistic(seconds: gpuSamples)))
        }
        let gpuFrames = Array(frameGPU.prefix(frameGPUCount))
        return FrameStageReport(frames: frameCount, stages: stages, frameGPU: StageStatistic(seconds: gpuFrames),
                                rejectedSamples: rejectedSamples)
    }

    // MARK: - Private

    private static func isValid(_ seconds: Double) -> Bool { seconds.isFinite && seconds >= 0 }

    private func accumulateCPU(_ stage: FrameStage, _ seconds: Double) {
        currentCPU[stage.rawValue] = (currentMask & stage.bit != 0 ? currentCPU[stage.rawValue] : 0) + seconds
        currentMask |= stage.bit
    }

    private func clearCurrent() {
        begun = 0
        currentMask = 0
    }

    private func samples(of stage: FrameStage, bitShift: UInt16, from values: [Double]) -> [Double] {
        let bit: UInt16 = stage.bit << bitShift
        var result: [Double] = []
        result.reserveCapacity(frameCount)
        for slot in 0..<frameCount where masks[slot] & bit != 0 {
            result.append(values[slot * FrameStage.count + stage.rawValue])
        }
        return result
    }
}
