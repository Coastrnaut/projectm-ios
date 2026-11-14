// OscilloscopeGenerator.swift — the waveform oscilloscope on Metal (VIS-003-R1, R6 to R9; research
// VIS-003-D2, D3; contracts/waveform-oscilloscope.md C4).
//
// The input vector is the mono sample history (oldest first, as `WaveformFrameBuffer` delivers it),
// not bands. Per frame: trigger + layout for the target's size (`OscilloscopeLayout`) → the strobe
// safety envelope's gain over 17 areas (against the composited levels when `downstreamLuminance` is
// set; FX-001-R10, FX-019-R9) → tessellate into a free vertex buffer → `FlatShapePass` clears to the
// background and draws flat, premultiplied triangles. Reduce flashing has no per-value slew here (a
// waveform has no level to slew); the envelope's `.reduceFlashing` configuration bounds the light. No
// allocation per frame. Not Sendable: one thread drives a generator.
#if canImport(Metal) && !VISUAL_NO_METAL
import Metal

public final class OscilloscopeGenerator: SpectrumTextureGenerator {
    public static let supportedPixelFormats = FlatShapePass.supportedPixelFormats

    public let device: MTLDevice
    public let pixelFormat: MTLPixelFormat
    /// Geometry and trigger of the last frame (tests and diagnostics).
    public let layout: OscilloscopeLayout
    public let limiter = FlashSafetyLimiter()
    /// The envelope's gain of the last frame (1 when not limited).
    public private(set) var lastGain: Float = 1
    /// How stages after this generator change the frame's brightness (FX-001-R10); nil: none.
    public var downstreamLuminance: (any FrameLuminanceTransfer)?
    /// Kept for the host (it carries the bar count between native visuals); does not affect drawing.
    public var barCount: SpectrumBarCount = .b64

    private let shapes: FlatShapePass

    public var configuration: OscilloscopeConfiguration {
        get { layout.configuration }
        set { layout.configuration = newValue }
    }

    public init(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm_srgb,
                configuration: OscilloscopeConfiguration = OscilloscopeConfiguration()) throws(VisualGeneratorError) {
        self.device = device
        self.pixelFormat = pixelFormat
        layout = OscilloscopeLayout(configuration: configuration)
        shapes = try FlatShapePass(device: device, pixelFormat: pixelFormat,
                                   maximumVertexCount: OscilloscopeLayout.maximumVertexCount, label: "VIS-003 oscilloscope")
    }

    /// The host's loop restart: the trigger starts without a reference; the envelope's history is
    /// kept (FX-019-R11).
    public func restartLoop() {
        limiter.reset()
        layout.trigger.reset()
    }

    /// `bands` is the sample history (oldest first).
    public func encode(into target: MTLTexture, commandBuffer: MTLCommandBuffer,
                       bands samples: UnsafeBufferPointer<Float>, context: VisualFrameContext) -> Bool {
        guard target.pixelFormat == pixelFormat, let slot = shapes.freeSlot() else { return false }
        layout.layout(samples: samples, width: target.width, height: target.height)
        let gain: Float
        if let downstream = downstreamLuminance {
            gain = limiter.gain(for: layout, transfer: downstream, frameTime: context.frameDuration, enabled: context.reduceFlashing)
        } else {
            gain = limiter.gain(for: layout, transfer: IdentityLuminanceTransfer(), frameTime: context.frameDuration,
                                enabled: context.reduceFlashing)
        }
        lastGain = gain
        let count = layout.tessellate(into: shapes.vertices(slot), capacity: OscilloscopeLayout.maximumVertexCount, gain: gain)
        return shapes.draw(slot: slot, count: count, into: target, background: layout.configuration.background,
                           commandBuffer: commandBuffer)
    }
}
#endif
