// FeatureAgeMeasuring.swift — PERF-013 (specs/216-perf-013-audio-render-sync, R1, R11; contracts/feature-age.md C1):
// what the visuals that consume analysis frames share for the feature age meter. While a `FeatureAgeMeter` is attached
// (the performance overlay is shown), each frame hands it the frame read this tick (nil when nothing new arrived), the
// read time and the display link's target time. projectM consumes no feature frames: it never conforms, and its overlay
// line reads "unavailable". Local measurement only: nothing is stored or sent, nothing reaches projectM.
import AudioCore
import FrameTiming
import QuartzCore
import VisualBandFeed

/// A visual whose frame loop consumes the analysis bus's newest frame each tick.
@MainActor
protocol FeatureAgeMeasured: AnyObject {
    var featureAge: FeatureAgeMeter? { get set }
}

extension NativeSpectrumHost: FeatureAgeMeasured {}
extension CameraVisualHost: FeatureAgeMeasured {}
extension PhotoVisualHost: FeatureAgeMeasured {}
extension VideoVisualHost: FeatureAgeMeasured {}
extension TextVisualHost: FeatureAgeMeasured {}

extension FeatureAgeMeter {
    /// One presented frame of `link`'s tick: `info` is what `readLatest` returned this tick. The read time is now
    /// (CLOCK_UPTIME_RAW, the display link's clock); the presentation time is the link's target. Allocation-free.
    @MainActor
    func frame(_ info: LiveBandFrameInfo?, link: CADisplayLink) {
        let stamp: FeatureFrameStamp? = info.map { (i: LiveBandFrameInfo) -> FeatureFrameStamp in
            FeatureFrameStamp(session: i.session, sequence: i.sequence, sessionSample: i.sessionSample,
                              busHostNanoseconds: i.timestampNanoseconds)
        }
        let target: Double = max(link.targetTimestamp, 0) * 1_000_000_000
        frame(stamp, arrivalNanoseconds: MonotonicClock.nowNanoseconds(), presentationNanoseconds: UInt64(target))
    }
}
