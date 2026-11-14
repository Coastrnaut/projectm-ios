// CompositeFlashGuard.swift — FX-019's strobe safety envelope on the finished composite
// (CMP-001-R10; ADR-0013 decision 6; research CMP-001-D4).
//
// One compute dispatch per frame, one threadgroup of 16 threads, no CPU read-back:
//   1. Measure: thread k reads 16 × 16 samples of tile k of the 4 × 4 grid (row 0 at the top, as
//      FlashZones; CFlashLimiter's sample pattern) of the linear premultiplied composite (= over
//      black), each through FX-002's output tone map (what the screen shows), and computes the tile's mean WCAG relative luminance and redness max(R − G − B, 0).
//   2. Thread 0: the whole frame is the mean of the tiles; it then runs FlashEnvelope's rule on the
//      34 tracks (17 areas × 2 signals): advance the ages by the clamped frame time, compute each
//      ceiling, take the closed-form gain min(ceiling / level) (levels scale linearly with the gain),
//      commit the shown values (gain × level) through the hysteresis detector, and write the gain.
// The state is float32 in a private buffer (the GL port packs 16-bit values), so the gain matches
// `FlashEnvelope.gain(inputs:…)` closely; keep the rule in step with FlashEnvelope.swift and
// FlashLimiter.c. The output pass multiplies RGB by the gain. The history survives pauses; `reset()`
// forgets it from the next frame (a new scene, FX-019-R11). Not Sendable: one thread drives it.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import FlashSafety
import Metal

final class CompositeFlashGuard {
    /// Track: last, low, high, direction (0 none, 1 rising, 2 falling), initialized, 6 ages.
    static let floatsPerTrack = 11
    static let trackCount = FlashZones.count * 2

    /// Matches `GuardParams` in the shader (ten 4-byte fields, no padding).
    struct Parameters {
        var frameTime: Float
        var window: Float
        var luminanceThreshold: Float
        var rednessThreshold: Float
        var gateMargin: Float
        var riseRatePerSecond: Float   // < 0: no rate limit
        var transitionBudget: Float
        var resetState: UInt32
        var unused0: UInt32 = 0
        var unused1: UInt32 = 0
    }

    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct GuardParams {
        float dt; float window; float lumThreshold; float redThreshold; float margin; float rise; float budget;
        uint resetState; uint unused0; uint unused1;
    };

    struct Track { float last; float low; float high; float dir; float init; float ages[6]; };

    constant float windowTolerance = 0.002;   // FlashEnvelope.windowTolerance

    // FX-002 (ADR-0047): the output tone map, so the guard measures the colour the output pass shows.
    \(CompositorShaders.toneMapSource)

    kernel void cmp_flash_guard(texture2d<float, access::read> scene [[texture(0)]],
                                device Track *tracks [[buffer(0)]],
                                device float *gainOut [[buffer(1)]],
                                constant GuardParams &p [[buffer(2)]],
                                uint tid [[thread_index_in_threadgroup]]) {
        threadgroup float levels[34];
        uint2 size = uint2(scene.get_width(), scene.get_height());
        if (tid < 16) {
            float2 tile = float2(float(tid % 4), float(tid / 4));
            float y = 0.0, r = 0.0;
            for (int j = 0; j < 16; j++) {
                for (int i = 0; i < 16; i++) {
                    float2 f = (tile + (float2(float(i), float(j)) + 0.5) / 16.0) / 4.0;
                    uint2 q = min(uint2(f * float2(size)), size - 1);
                    float3 c = cmp_tone_map(scene.read(q)).rgb;   // FX-002: as shown (0…1, never NaN)
                    y += dot(c, float3(0.2126, 0.7152, 0.0722));
                    r += max(c.r - c.g - c.b, 0.0);
                }
            }
            levels[tid * 2] = y / 256.0;
            levels[tid * 2 + 1] = r / 256.0;
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
        if (tid != 0) return;

        float sy = 0.0, sr = 0.0;
        for (int k = 0; k < 16; k++) { sy += levels[k * 2]; sr += levels[k * 2 + 1]; }
        levels[32] = sy / 16.0;
        levels[33] = sr / 16.0;

        // Steps 1-2: advance the clock, ceilings, gain.
        float g = 1.0;
        for (int t = 0; t < 34; t++) {
            Track tr = tracks[t];
            if (p.resetState != 0) { tr.init = 0.0; }
            for (int k = 0; k < 6; k++) { tr.ages[k] = (tr.init > 0.5) ? min(tr.ages[k] + p.dt, 2.0) : 2.0; }
            tracks[t] = tr;
            if (tr.init < 0.5) continue;
            float ceiling = INFINITY;
            if (p.rise >= 0.0) ceiling = tr.last + p.rise * p.dt;
            if (tr.dir != 1.0) {
                int n = 0;
                for (int k = 0; k < 6; k++) { if (tr.ages[k] < p.window + windowTolerance) n++; }
                if (float(n) > p.budget - 2.0) {
                    float threshold = (t % 2 == 0) ? p.lumThreshold : p.redThreshold;
                    ceiling = min(ceiling, tr.low + threshold - p.margin);
                }
            }
            float v = levels[t];
            if (v > ceiling) g = min(g, max(ceiling, 0.0) / v);
        }
        g = clamp(g, 0.0, 1.0);

        // Step 4: commit the shown values.
        for (int t = 0; t < 34; t++) {
            Track tr = tracks[t];
            float v = g * levels[t];
            float threshold = (t % 2 == 0) ? p.lumThreshold : p.redThreshold;
            bool transition = false;
            if (tr.init < 0.5) {
                tr.init = 1.0; tr.last = v; tr.low = v; tr.high = v; tr.dir = 0.0;
                for (int k = 0; k < 6; k++) tr.ages[k] = 2.0;
            } else {
                if (tr.dir == 0.0) {
                    if (v >= tr.low + threshold) { tr.dir = 1.0; tr.high = v; transition = true; }
                    else if (v <= tr.high - threshold) { tr.dir = 2.0; tr.low = v; transition = true; }
                    else { tr.low = min(tr.low, v); tr.high = max(tr.high, v); }
                } else if (tr.dir == 1.0) {
                    if (v > tr.high) tr.high = v;
                    else if (v <= tr.high - threshold) { tr.dir = 2.0; tr.low = v; transition = true; }
                } else {
                    if (v < tr.low) tr.low = v;
                    else if (v >= tr.low + threshold) { tr.dir = 1.0; tr.high = v; transition = true; }
                }
                tr.last = v;
                if (transition) {
                    int oldest = 0;
                    for (int k = 1; k < 6; k++) { if (tr.ages[k] > tr.ages[oldest]) oldest = k; }
                    tr.ages[oldest] = 0.0;
                }
            }
            tracks[t] = tr;
        }
        gainOut[0] = g;
    }
    """

    let gainBuffer: MTLBuffer
    private let stateBuffer: MTLBuffer
    private let pipeline: MTLComputePipelineState
    private var needsReset = true

    init(device: MTLDevice) throws(CompositorError) {
        var one: Float = 1
        guard let gain = device.makeBuffer(bytes: &one, length: MemoryLayout<Float>.size, options: .storageModeShared),
              let state = device.makeBuffer(length: Self.trackCount * Self.floatsPerTrack * MemoryLayout<Float>.size,
                                            options: .storageModePrivate) else {
            throw .pipelineUnavailable("flash guard buffers")
        }
        gain.label = "CMP-001 flash guard gain"
        state.label = "CMP-001 flash guard state"
        gainBuffer = gain
        stateBuffer = state
        let library = try CompositorShaders.library(device: device, source: Self.source)
        let function = try CompositorShaders.function(library, "cmp_flash_guard")
        do {
            pipeline = try device.makeComputePipelineState(function: function)
        } catch {
            throw .pipelineUnavailable("flash guard: \(error.localizedDescription)")
        }
        precondition(MemoryLayout<Parameters>.size == 40, "GuardParams layout")
    }

    /// The gain of the last completed frame.
    var lastGain: Float { gainBuffer.contents().load(as: Float.self) }

    /// The next frame starts without history (a new scene).
    func reset() { needsReset = true }

    /// Encodes the measurement and envelope for `composite`; the output pass reads `gainBuffer`.
    func encode(composite: MTLTexture, commandBuffer: MTLCommandBuffer, frameDuration: Double, reduceFlashing: Bool,
                flashLimits: FlashEnvelopeConfiguration? = nil) -> Bool {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return false }
        // ACC-012-R5: the sensory safety profile's envelope when set; else today's Reduce flashing choice.
        let c = flashLimits ?? FlashEnvelopeConfiguration.forReduceFlashing(reduceFlashing)
        var parameters = Parameters(frameTime: Float(c.clampedFrameTime(frameDuration)), window: Float(c.window),
                                    luminanceThreshold: Float(c.luminanceThreshold), rednessThreshold: Float(c.rednessThreshold),
                                    gateMargin: Float(c.gateMargin), riseRatePerSecond: Float(c.riseRatePerSecond ?? -1),
                                    transitionBudget: Float(c.transitionBudget), resetState: needsReset ? 1 : 0)
        needsReset = false
        encoder.label = "CMP-001 flash guard"
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(composite, index: 0)
        encoder.setBuffer(stateBuffer, offset: 0, index: 0)
        encoder.setBuffer(gainBuffer, offset: 0, index: 1)
        encoder.setBytes(&parameters, length: MemoryLayout<Parameters>.size, index: 2)
        encoder.dispatchThreadgroups(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 16, height: 1, depth: 1))
        encoder.endEncoding()
        return true
    }
}
#endif
