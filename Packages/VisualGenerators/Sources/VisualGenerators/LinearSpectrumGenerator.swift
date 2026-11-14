// LinearSpectrumGenerator.swift — the linear spectrum on Metal (VIS-002-R1 to R10; research
// VIS-002-D1 to D4; contracts/linear-spectrum.md).
//
// Per frame, exactly as the circular spectrum (VIS-001, FX-001-R10, FX-019-R9): Reduce-flashing
// slew → CPU layout for the target's size, which also advances the peak caps by the frame time →
// the strobe safety envelope's gain over 17 areas (against the composited levels when
// `downstreamLuminance` is set) → tessellate into a free vertex buffer → `FlatShapePass` clears to
// the background and draws flat, premultiplied triangles. No allocation per frame. Not Sendable:
// one thread drives a generator.
#if canImport(Metal) && !VISUAL_NO_METAL
import Metal

public final class LinearSpectrumGenerator: SpectrumTextureGenerator {
    public static let supportedPixelFormats = FlatShapePass.supportedPixelFormats

    public let device: MTLDevice
    public let pixelFormat: MTLPixelFormat
    /// Geometry of the last frame (tests and diagnostics).
    public let layout: LinearSpectrumLayout
    public let limiter = FlashSafetyLimiter()
    /// The envelope's gain of the last frame (1 when not limited).
    public private(set) var lastGain: Float = 1
    /// How stages after this generator change the frame's brightness (FX-001-R10); nil: none.
    public var downstreamLuminance: (any FrameLuminanceTransfer)?

    private let shapes: FlatShapePass

    public var configuration: LinearSpectrumConfiguration {
        get { layout.configuration }
        set { layout.configuration = newValue }
    }

    public var barCount: SpectrumBarCount {
        get { layout.configuration.barCount }
        set { layout.configuration.barCount = newValue }
    }

    public init(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm_srgb,
                configuration: LinearSpectrumConfiguration = LinearSpectrumConfiguration()) throws(VisualGeneratorError) {
        self.device = device
        self.pixelFormat = pixelFormat
        layout = LinearSpectrumLayout(configuration: configuration)
        shapes = try FlatShapePass(device: device, pixelFormat: pixelFormat,
                                   maximumVertexCount: LinearSpectrumLayout.maximumVertexCount, label: "VIS-002 linear spectrum")
    }

    /// The host's loop restart: bars and caps start from the next frame's values; the envelope's
    /// history is kept (FX-019-R11).
    public func restartLoop() {
        limiter.reset()
        layout.resetPeaks()
    }

    public func encode(into target: MTLTexture, commandBuffer: MTLCommandBuffer,
                       bands: UnsafeBufferPointer<Float>, context: VisualFrameContext) -> Bool {
        guard target.pixelFormat == pixelFormat, let slot = shapes.freeSlot() else { return false }
        let shown = limiter.limitValues(bands, frameTime: context.frameDuration, enabled: context.reduceFlashing)
        layout.layout(values: shown, frameTime: context.frameDuration, width: target.width, height: target.height)
        let gain: Float
        if let downstream = downstreamLuminance {
            gain = limiter.gain(for: layout, transfer: downstream, frameTime: context.frameDuration,
                                configuration: context.flashConfiguration)
        } else {
            gain = limiter.gain(for: layout, transfer: IdentityLuminanceTransfer(), frameTime: context.frameDuration,
                                configuration: context.flashConfiguration)
        }
        lastGain = gain
        let count = layout.tessellate(into: shapes.vertices(slot), capacity: LinearSpectrumLayout.maximumVertexCount, gain: gain)
        return shapes.draw(slot: slot, count: count, into: target, background: layout.configuration.background,
                           commandBuffer: commandBuffer)
    }
}
#endif
