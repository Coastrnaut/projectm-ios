// SpectrumTextureGenerator.swift — what the native spectra share (VIS-002-R1, R9, R14; research
// VIS-002-D1; specs/025-vis-002-linear-spectrum/contracts/linear-spectrum.md).
//
// * `FlashAreaLevelSource`: a laid-out frame that can report its levels in the strobe safety
//   envelope's 17 areas (FX-019-R4), so `FlashSafetyLimiter.gain(for:…)` serves every visual.
// * `FlashRegionLayout` (internal): a frame made of flat-colored convex regions over a flat
//   background; `SpectrumFlashAreas` computes the 17 area levels of any such layout.
// * `SpectrumTextureGenerator`: what the app host needs from a spectrum generator, so one host
//   drives the circular (VIS-001) and the linear (VIS-002) spectrum.
#if canImport(Metal) && !VISUAL_NO_METAL
import Metal
#endif
import FlashSafety

/// A laid-out frame whose levels in FX-019's 17 areas can be computed for any gain (no allocation).
public protocol FlashAreaLevelSource: AnyObject {
    /// The frame's levels in the 17 areas (tiles 0…15 row-major from the top, then the whole frame)
    /// when drawn with `gain` and passed through `transfer`. Writes `FlashZones.count` values.
    func meanLevels<Transfer: FrameLuminanceTransfer>(gain: Float, transfer: Transfer,
                                                      into out: UnsafeMutableBufferPointer<FlashLevels>)
}

/// Flat-colored, non-overlapping convex regions over a flat background, in pixels (y down).
protocol FlashRegionLayout: AnyObject {
    var width: Int { get }
    var height: Int { get }
    /// Regions of the last layout (at most the areas' capacity).
    var flashRegionCount: Int { get }
    /// Premultiplied, linear.
    var flashBackground: LinearColor { get }
    /// Exact area of region `k` in pixels²; 0 when it is not drawn.
    func flashRegionArea(_ k: Int) -> Double
    /// Linear color of region `k` before any gain.
    func flashRegionColor(_ k: Int) -> LinearColor
    /// Calls `body` with each convex quad (a, b, c, d in order) region `k` is drawn as.
    func forEachFlashQuad(ofRegion k: Int,
                          _ body: (Double, Double, Double, Double, Double, Double, Double, Double) -> Void)
}

#if canImport(Metal) && !VISUAL_NO_METAL
/// A band-driven native spectrum the app host can drive (VIS-001 circular, VIS-002 linear).
public protocol SpectrumTextureGenerator: TextureGenerator {
    /// Reduce flashing and the strobe safety envelope (VIS-001-R10, FX-019).
    var limiter: FlashSafetyLimiter { get }
    /// The downstream stages' light (FX-001-R10); nil without any.
    var downstreamLuminance: (any FrameLuminanceTransfer)? { get set }
    var barCount: SpectrumBarCount { get set }
    /// The host's loop restart: the bar slew (and any peak state) starts from the next frame's
    /// values; the envelope history is kept (FX-019-R11).
    func restartLoop()
}
#endif
