// FrameStageTiming.swift — PERF-001 (specs/152-perf-001-stage-timings): what the visuals share for per-stage
// frame timings. Each frame loop records its stages only while a `FrameStageTimer` is attached (the
// performance overlay is shown); with none attached it does no timing work (PERF-001-R8).
//
// Stages per visual (PERF-001-R11): projectM `ANGLERenderer.frameStages` (audio, render, output, present;
// no GPU time: ANGLE submits the Metal work itself); the native spectrum and oscilloscope
// `NativeSpectrumHost.frameStages` (audio, render, encode, present); the compositor visuals (camera, photo,
// video, text) `compositorFrameStages` (audio, composite, output, encode, present). The Metal visuals add the
// whole frame's GPU time from their command buffers (`MetalGPUFrameTimes`). The wait for the next drawable
// belongs to no stage (frame pacing, not work).
import ANGLERendering
import Compositor
import FrameTiming

/// A visual whose frame loop can record its stages.
@MainActor
protocol FrameStageTimed: AnyObject {
    var stageTimer: FrameStageTimer? { get set }
}

extension ANGLERenderer: FrameStageTimed {}
extension NativeSpectrumHost: FrameStageTimed {}
extension CameraVisualHost: FrameStageTimed {}
extension PhotoVisualHost: FrameStageTimed {}
extension VideoVisualHost: FrameStageTimed {}
extension TextVisualHost: FrameStageTimed {}

/// The compositor visuals' stages, in frame order.
let compositorFrameStages: [FrameStage] = [.audio, .composite, .output, .encode, .present]

/// Configures a compositor visual for `timer` (or stops timing with nil): its pipeline, a fresh GPU poller and
/// the compositor's output-pass mark (contract C4).
@MainActor
func attachStageTimer(_ timer: FrameStageTimer?, compositor: Compositor, gpuTimes: MetalGPUFrameTimes) {
    gpuTimes.reset()
    guard let timer else {
        compositor.stageClock = nil
        return
    }
    timer.configure(pipeline: compositorFrameStages)
    compositor.stageClock = { () -> UInt64 in timer.now() }
}

extension FrameStageTimer {
    /// Splits the time since `start` at the compositor's output-pass mark into composite and output.
    func recordComposite(of compositor: Compositor, start: UInt64) {
        recordSplit(.composite, .output, start: start, mark: compositor.lastOutputPassStartNanoseconds, end: now())
    }
}
