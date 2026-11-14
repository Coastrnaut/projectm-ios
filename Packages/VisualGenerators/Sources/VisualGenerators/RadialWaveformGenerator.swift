// RadialWaveformGenerator.swift — the radial waveform on Metal (VIS-005-R1, R8; contracts/radial-waveform.md C2).
//
// The input vector is VIS-003's mono sample history (oldest first, as `WaveformTap.output` delivers it), not
// bands. Per frame: layout for the target's size with the frame context's duration (`RadialWaveformLayout`:
// seam taper, auto gain) → the strobe safety envelope's gain over 17 areas (against the composited levels when
// `downstreamLuminance` is set; FX-001-R10, FX-019-R9) → tessellate into a free vertex buffer →
// `FlatShapePass` clears to the background and draws flat, premultiplied triangles. No allocation per frame.
// Not Sendable: one thread drives a generator.
#if canImport(Metal) && !VISUAL_NO_METAL
import Metal

public final class RadialWaveformGenerator: SpectrumTextureGenerator {
    public static let supportedPixelFormats = FlatShapePass.supportedPixelFormats

    public let device: MTLDevice
    public let pixelFormat: MTLPixelFormat
    /// Geometry and gain of the last frame (tests and diagnostics).
    public let layout: RadialWaveformLayout
    public let limiter = FlashSafetyLimiter()
    /// The envelope's gain of the last frame (1 when not limited).
    public private(set) var lastGain: Float = 1
    /// How stages after this generator change the frame's brightness (FX-001-R10); nil: none.
    public var downstreamLuminance: (any FrameLuminanceTransfer)?
    /// Kept for the host (it carries the bar count between native visuals); does not affect drawing.
    public var barCount: SpectrumBarCount = .b64

    private let shapes: FlatShapePass

    public var configuration: RadialWaveformConfiguration {
        get { layout.configuration }
        set { layout.configuration = newValue }
    }

    public init(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm_srgb,
                configuration: RadialWaveformConfiguration = RadialWaveformConfiguration()) throws(VisualGeneratorError) {
        self.device = device
        self.pixelFormat = pixelFormat
        layout = RadialWaveformLayout(configuration: configuration)
        shapes = try FlatShapePass(device: device, pixelFormat: pixelFormat,
                                   maximumVertexCount: RadialWaveformLayout.maximumVertexCount, label: "VIS-005 Radial waveform")
    }

    /// The host's loop restart: the gain starts afresh; the envelope's history is kept (FX-019-R11).
    public func restartLoop() {
        limiter.reset()
        layout.reset()
    }

    /// `bands` is the mono sample history (oldest first).
    public func encode(into target: MTLTexture, commandBuffer: MTLCommandBuffer,
                       bands history: UnsafeBufferPointer<Float>, context: VisualFrameContext) -> Bool {
        guard target.pixelFormat == pixelFormat, let slot = shapes.freeSlot() else { return false }
        layout.layout(samples: history, frameDuration: context.frameDuration, width: target.width, height: target.height)
        let gain: Float
        if let downstream = downstreamLuminance {
            gain = limiter.gain(for: layout, transfer: downstream, frameTime: context.frameDuration,
                                configuration: context.flashConfiguration)
        } else {
            gain = limiter.gain(for: layout, transfer: IdentityLuminanceTransfer(), frameTime: context.frameDuration,
                                configuration: context.flashConfiguration)
        }
        lastGain = gain
        let count = layout.tessellate(into: shapes.vertices(slot), capacity: RadialWaveformLayout.maximumVertexCount, gain: gain)
        return shapes.draw(slot: slot, count: count, into: target, background: layout.configuration.background,
                           commandBuffer: commandBuffer)
    }
}
#endif
