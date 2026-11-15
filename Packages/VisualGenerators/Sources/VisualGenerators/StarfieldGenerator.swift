// StarfieldGenerator.swift — the starfield on Metal (VIS-016-R1, R6, R7; contract S6).
//
// Per frame: the low band group (VIS-007's thirds of the input bands, ANL-002) becomes the simulation's bass target →
// the simulation advances to the frame context's time (fixed 1/240 s steps) → squares of the drawn stars
// (`StarfieldLayout`, total light bounded) → the strobe safety envelope's gain over 17 areas (against the composited
// levels when `downstreamLuminance` is set; FX-001-R10, FX-019-R9) → tessellate into a free vertex buffer →
// `FlatShapePass` (the reviewed flat-shape shader; no new shader text, SHD-011). No allocation per frame. Not Sendable:
// one thread drives a generator.
#if canImport(Metal) && !VISUAL_NO_METAL
import FlashSafety
import Metal

public final class StarfieldGenerator: SpectrumTextureGenerator {
    public static let supportedPixelFormats = FlatShapePass.supportedPixelFormats

    public let device: MTLDevice
    public let pixelFormat: MTLPixelFormat
    /// The stars.
    public let simulation: StarfieldSimulation
    /// Geometry of the last frame (tests and diagnostics).
    public let layout = StarfieldLayout()
    public let limiter = FlashSafetyLimiter()
    /// The envelope's gain of the last frame (1 when not limited).
    public private(set) var lastGain: Float = 1
    /// Vertices drawn in the last frame.
    public private(set) var lastVertexCount = 0
    /// How stages after this generator change the frame's brightness (FX-001-R10); nil: none.
    public var downstreamLuminance: (any FrameLuminanceTransfer)?
    /// Kept for the host (it carries the bar count between native visuals); does not affect drawing.
    public var barCount: SpectrumBarCount = .b64

    private let shapes: FlatShapePass

    /// Density, speed, Reduce Motion and palette apply from the next frame; a new seed resets the stars.
    public var configuration: StarfieldConfiguration {
        get { simulation.configuration }
        set { simulation.configuration = newValue }
    }

    public init(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm_srgb,
                configuration: StarfieldConfiguration = StarfieldConfiguration()) throws(VisualGeneratorError) {
        self.device = device
        self.pixelFormat = pixelFormat
        simulation = StarfieldSimulation(configuration: configuration)
        shapes = try FlatShapePass(device: device, pixelFormat: pixelFormat,
                                   maximumVertexCount: StarfieldLayout.maximumVertexCount, label: "VIS-016 Starfield")
    }

    /// VIS-016-R4: the host's loop restart: every star back at its initial seeded position; the limiter's slew starts
    /// over (the envelope's history is kept, FX-019-R11).
    public func restartLoop() {
        limiter.reset()
        simulation.reset()
    }

    /// `bands` drive the bass boost (low group); empty bands read as silence.
    public func encode(into target: MTLTexture, commandBuffer: MTLCommandBuffer,
                       bands: UnsafeBufferPointer<Float>, context: VisualFrameContext) -> Bool {
        guard target.pixelFormat == pixelFormat, let slot = shapes.freeSlot() else { return false }
        simulation.setBass(MandalaBandGroups.from(bands).low)
        simulation.advance(toNanoseconds: context.timeNanoseconds)
        layout.layout(simulation: simulation, width: target.width, height: target.height)
        let gain: Float
        if let downstream = downstreamLuminance {
            gain = limiter.gain(for: layout, transfer: downstream, frameTime: context.frameDuration,
                                configuration: context.flashConfiguration)
        } else {
            gain = limiter.gain(for: layout, transfer: IdentityLuminanceTransfer(), frameTime: context.frameDuration,
                                configuration: context.flashConfiguration)
        }
        lastGain = gain
        let count = layout.tessellate(into: shapes.vertices(slot), capacity: StarfieldLayout.maximumVertexCount, gain: gain)
        lastVertexCount = count
        return shapes.draw(slot: slot, count: count, into: target, background: layout.background,
                           commandBuffer: commandBuffer)
    }
}
#endif
