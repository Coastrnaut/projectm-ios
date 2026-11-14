// BeatRingGenerator.swift — the beat rings on Metal (VIS-006-R1, R5, R8; contracts/beat-rings.md C2).
//
// The host calls `emitRing(atNanoseconds:flashConfiguration:)` for each beat it accepts (VIS-006-R2), stamped
// with the frame time; the rate cap follows the frame's envelope (VIS-006-R5). The input vector of `encode` is
// unused. Per frame: layout of the field's live rings at the frame context's time (`BeatRingLayout`) → the
// strobe safety envelope's gain over 17 areas (against the composited levels when `downstreamLuminance` is
// set; FX-001-R10, FX-019-R9) → tessellate into a free vertex buffer → `FlatShapePass` clears to the
// background and draws flat, premultiplied triangles. No allocation per frame. Not Sendable: one thread
// drives a generator.
#if canImport(Metal) && !VISUAL_NO_METAL
import FlashSafety
import Metal

public final class BeatRingGenerator: SpectrumTextureGenerator {
    public static let supportedPixelFormats = FlatShapePass.supportedPixelFormats

    public let device: MTLDevice
    public let pixelFormat: MTLPixelFormat
    /// The rings' birth times.
    public let field = BeatRingField()
    /// Geometry of the last frame (tests and diagnostics).
    public let layout: BeatRingLayout
    public let limiter = FlashSafetyLimiter()
    /// The envelope's gain of the last frame (1 when not limited).
    public private(set) var lastGain: Float = 1
    /// How stages after this generator change the frame's brightness (FX-001-R10); nil: none.
    public var downstreamLuminance: (any FrameLuminanceTransfer)?
    /// Kept for the host (it carries the bar count between native visuals); does not affect drawing.
    public var barCount: SpectrumBarCount = .b64

    private let shapes: FlatShapePass

    public var configuration: BeatRingConfiguration {
        get { layout.configuration }
        set { layout.configuration = newValue }
    }

    public init(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm_srgb,
                configuration: BeatRingConfiguration = BeatRingConfiguration()) throws(VisualGeneratorError) {
        self.device = device
        self.pixelFormat = pixelFormat
        layout = BeatRingLayout(configuration: configuration)
        shapes = try FlatShapePass(device: device, pixelFormat: pixelFormat,
                                   maximumVertexCount: BeatRingLayout.maximumVertexCount, label: "VIS-006 Beat rings")
    }

    /// The host's loop restart: live rings are cleared (no burst of stale rings); the envelope's history is
    /// kept (FX-019-R11).
    public func restartLoop() {
        limiter.reset()
        field.reset()
    }

    /// A ring born at `nanoseconds` (the frame clock) unless the rate cap for `flashConfiguration` refuses it.
    @discardableResult
    public func emitRing(atNanoseconds nanoseconds: UInt64, flashConfiguration: FlashEnvelopeConfiguration) -> Bool {
        field.emit(atNanoseconds: nanoseconds, minimumInterval: BeatRingConfiguration.minimumInterval(for: flashConfiguration))
    }

    /// `bands` is unused: the rings come from `emitRing`.
    public func encode(into target: MTLTexture, commandBuffer: MTLCommandBuffer,
                       bands: UnsafeBufferPointer<Float>, context: VisualFrameContext) -> Bool {
        guard target.pixelFormat == pixelFormat, let slot = shapes.freeSlot() else { return false }
        layout.layout(field: field, atNanoseconds: context.timeNanoseconds, width: target.width, height: target.height)
        let gain: Float
        if let downstream = downstreamLuminance {
            gain = limiter.gain(for: layout, transfer: downstream, frameTime: context.frameDuration,
                                configuration: context.flashConfiguration)
        } else {
            gain = limiter.gain(for: layout, transfer: IdentityLuminanceTransfer(), frameTime: context.frameDuration,
                                configuration: context.flashConfiguration)
        }
        lastGain = gain
        let count = layout.tessellate(into: shapes.vertices(slot), capacity: BeatRingLayout.maximumVertexCount, gain: gain)
        return shapes.draw(slot: slot, count: count, into: target, background: layout.configuration.background,
                           commandBuffer: commandBuffer)
    }
}
#endif
