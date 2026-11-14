// CircularSpectrumGenerator.swift — the circular spectrum on Metal (VIS-001-R1 to R10, R17;
// research VIS-001-D2 to D4, D7, D8).
//
// Per frame: Reduce-flashing slew → CPU layout for the target's size → the strobe safety envelope's
// gain over 17 areas (FX-019; against the composited levels when `downstreamLuminance` is set,
// FX-001-R10) → tessellate
// into a preallocated vertex buffer → one render pass that clears to the background and draws flat,
// premultiplied triangles. The GPU only passes positions through.
//
// Shaders and vertex buffers: `FlatShapePass` (shared with VIS-002's linear spectrum; research
// VIS-002-D1): a runtime-compiled shader constant (ADR-0009 decision 3) and three vertex buffers,
// each sized for 128 bars, rewritten only once the GPU is done with them (otherwise the frame is
// skipped). No allocation in this file's per-frame code (Metal's own command objects are the
// system's). Not Sendable: one thread drives a generator.
#if canImport(Metal) && !VISUAL_NO_METAL
import Metal

public final class CircularSpectrumGenerator: SpectrumTextureGenerator {
    public static let supportedPixelFormats = FlatShapePass.supportedPixelFormats
    static let bufferCount = FlatShapePass.bufferCount

    public let device: MTLDevice
    public let pixelFormat: MTLPixelFormat
    /// Geometry of the last frame (tests and diagnostics).
    public let layout: CircularSpectrumLayout
    public let limiter = FlashSafetyLimiter()
    /// The Reduce-flashing gain of the last frame (1 when not limited).
    public private(set) var lastGain: Float = 1
    /// How stages after this generator change the frame's brightness (FX-001-R10: the bloom's
    /// `BloomLuminanceModel`). Nil (the default): the bars' own light; set, the envelope bounds the
    /// composited frame. Set it whenever those stages change.
    public var downstreamLuminance: (any FrameLuminanceTransfer)?

    private let shapes: FlatShapePass

    public var configuration: CircularSpectrumConfiguration {
        get { layout.configuration }
        set { layout.configuration = newValue }
    }

    public var barCount: SpectrumBarCount {
        get { layout.configuration.barCount }
        set { layout.configuration.barCount = newValue }
    }

    public init(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm_srgb,
                configuration: CircularSpectrumConfiguration = CircularSpectrumConfiguration()) throws(VisualGeneratorError) {
        self.device = device
        self.pixelFormat = pixelFormat
        layout = CircularSpectrumLayout(configuration: configuration)
        shapes = try FlatShapePass(device: device, pixelFormat: pixelFormat,
                                   maximumVertexCount: CircularSpectrumLayout.maximumVertexCount, label: "VIS-001 circular spectrum")
    }

    public func restartLoop() {
        limiter.reset()
    }

    public func encode(into target: MTLTexture, commandBuffer: MTLCommandBuffer,
                       bands: UnsafeBufferPointer<Float>, context: VisualFrameContext) -> Bool {
        guard target.pixelFormat == pixelFormat, let slot = shapes.freeSlot() else { return false }
        let shown = limiter.limitValues(bands, frameTime: context.frameDuration, enabled: context.reduceFlashing)
        layout.layout(values: shown, width: target.width, height: target.height)
        // FX-019: every frame goes through the strobe safety envelope (17 areas, both signals), with
        // the downstream stages' light when set (FX-001-R10).
        let gain: Float
        if let downstream = downstreamLuminance {
            gain = limiter.gain(for: layout, transfer: downstream, frameTime: context.frameDuration,
                                configuration: context.flashConfiguration)
        } else {
            gain = limiter.gain(for: layout, transfer: IdentityLuminanceTransfer(), frameTime: context.frameDuration,
                                configuration: context.flashConfiguration)
        }
        lastGain = gain
        let count = layout.tessellate(into: shapes.vertices(slot), capacity: CircularSpectrumLayout.maximumVertexCount, gain: gain)
        return shapes.draw(slot: slot, count: count, into: target, background: layout.configuration.background,
                           commandBuffer: commandBuffer)
    }
}
#endif
