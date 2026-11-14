// MandalaGenerator.swift — the mandala on Metal (VIS-007-R1, R8; contracts/mandala.md C2).
//
// Per frame: Reduce-flashing slew of the bands (VIS-001-R10) → layout at the frame context's time
// (`MandalaLayout`: band groups, sector 0, N rotated copies) → the strobe safety envelope's gain over 17 areas
// (against the composited levels when `downstreamLuminance` is set; FX-001-R10, FX-019-R9) → tessellate into a
// free vertex buffer → `FlatShapePass` clears to the background and draws flat, premultiplied triangles. No
// allocation per frame. Not Sendable: one thread drives a generator.
#if canImport(Metal) && !VISUAL_NO_METAL
import FlashSafety
import Metal

public final class MandalaGenerator: SpectrumTextureGenerator {
    public static let supportedPixelFormats = FlatShapePass.supportedPixelFormats

    public let device: MTLDevice
    public let pixelFormat: MTLPixelFormat
    /// Geometry of the last frame (tests and diagnostics).
    public let layout: MandalaLayout
    public let limiter = FlashSafetyLimiter()
    /// The envelope's gain of the last frame (1 when not limited).
    public private(set) var lastGain: Float = 1
    /// How stages after this generator change the frame's brightness (FX-001-R10); nil: none.
    public var downstreamLuminance: (any FrameLuminanceTransfer)?
    /// Kept for the host (it carries the bar count between native visuals); the mandala reads any band count.
    public var barCount: SpectrumBarCount = .b64

    private let shapes: FlatShapePass

    public var configuration: MandalaConfiguration {
        get { layout.configuration }
        set { layout.configuration = newValue }
    }

    public init(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm_srgb,
                configuration: MandalaConfiguration = MandalaConfiguration()) throws(VisualGeneratorError) {
        self.device = device
        self.pixelFormat = pixelFormat
        layout = MandalaLayout(configuration: configuration)
        shapes = try FlatShapePass(device: device, pixelFormat: pixelFormat,
                                   maximumVertexCount: MandalaLayout.maximumVertexCount, label: "VIS-007 Mandala")
    }

    /// The host's loop restart: the bands' slew starts from the next frame's values; the envelope's history
    /// (FX-019-R11) and the rotation anchor are kept, so the turn continues from the clock.
    public func restartLoop() {
        limiter.reset()
    }

    public func encode(into target: MTLTexture, commandBuffer: MTLCommandBuffer,
                       bands: UnsafeBufferPointer<Float>, context: VisualFrameContext) -> Bool {
        guard target.pixelFormat == pixelFormat, let slot = shapes.freeSlot() else { return false }
        let shown = limiter.limitValues(bands, frameTime: context.frameDuration, enabled: context.reduceFlashing)
        layout.layout(bands: shown, atNanoseconds: context.timeNanoseconds, width: target.width, height: target.height)
        let gain: Float
        if let downstream = downstreamLuminance {
            gain = limiter.gain(for: layout, transfer: downstream, frameTime: context.frameDuration,
                                configuration: context.flashConfiguration)
        } else {
            gain = limiter.gain(for: layout, transfer: IdentityLuminanceTransfer(), frameTime: context.frameDuration,
                                configuration: context.flashConfiguration)
        }
        lastGain = gain
        let count = layout.tessellate(into: shapes.vertices(slot), capacity: MandalaLayout.maximumVertexCount, gain: gain)
        return shapes.draw(slot: slot, count: count, into: target, background: layout.configuration.background,
                           commandBuffer: commandBuffer)
    }
}
#endif
