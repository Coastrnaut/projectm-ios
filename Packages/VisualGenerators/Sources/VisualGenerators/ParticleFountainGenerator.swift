// ParticleFountainGenerator.swift — the particle fountain on Metal (VIS-008-R1, R8; contracts/particle-fountain.md
// C2).
//
// The host calls `enqueueOnset(atNanoseconds:strength:threshold:)` for each ANL-004 onset it drains, stamped with
// the frame time. The input vector of `encode` is unused. Per frame: the simulation advances to the frame
// context's time (fixed 1/240 s steps, `ParticleFountainSimulation`) → squares of the live particles
// (`ParticleFountainLayout`) → the strobe safety envelope's gain over 17 areas (against the composited levels
// when `downstreamLuminance` is set; FX-001-R10, FX-019-R9) → tessellate into a free vertex buffer →
// `FlatShapePass` clears to the background and draws flat, premultiplied triangles. No allocation per frame.
// Not Sendable: one thread drives a generator.
#if canImport(Metal) && !VISUAL_NO_METAL
import FlashSafety
import Metal

public final class ParticleFountainGenerator: SpectrumTextureGenerator {
    public static let supportedPixelFormats = FlatShapePass.supportedPixelFormats

    public let device: MTLDevice
    public let pixelFormat: MTLPixelFormat
    /// The particles and pending onsets.
    public let simulation: ParticleFountainSimulation
    /// Geometry of the last frame (tests and diagnostics).
    public let layout = ParticleFountainLayout()
    public let limiter = FlashSafetyLimiter()
    /// The envelope's gain of the last frame (1 when not limited).
    public private(set) var lastGain: Float = 1
    /// How stages after this generator change the frame's brightness (FX-001-R10); nil: none.
    public var downstreamLuminance: (any FrameLuminanceTransfer)?
    /// Kept for the host (it carries the bar count between native visuals); does not affect drawing.
    public var barCount: SpectrumBarCount = .b64

    private let shapes: FlatShapePass

    /// Changes apply to particles spawned afterwards (and the palette from the next frame).
    public var configuration: ParticleFountainConfiguration {
        get { simulation.configuration }
        set { simulation.configuration = newValue }
    }

    public init(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm_srgb,
                configuration: ParticleFountainConfiguration = ParticleFountainConfiguration()) throws(VisualGeneratorError) {
        self.device = device
        self.pixelFormat = pixelFormat
        simulation = ParticleFountainSimulation(configuration: configuration)
        shapes = try FlatShapePass(device: device, pixelFormat: pixelFormat,
                                   maximumVertexCount: ParticleFountainLayout.maximumVertexCount, label: "VIS-008 Particle fountain")
    }

    /// The host's loop restart: particles and pending onsets are cleared and the seed restored (no burst of stale
    /// particles); the limiter starts over as VIS-006's rings do.
    public func restartLoop() {
        limiter.reset()
        simulation.reset()
    }

    /// An onset at `nanoseconds` (the frame clock); false when the queue is full.
    @discardableResult
    public func enqueueOnset(atNanoseconds nanoseconds: UInt64, strength: Float, threshold: Float) -> Bool {
        simulation.enqueueOnset(atNanoseconds: nanoseconds, strength: strength, threshold: threshold)
    }

    /// `bands` is unused: the particles come from `enqueueOnset`.
    public func encode(into target: MTLTexture, commandBuffer: MTLCommandBuffer,
                       bands: UnsafeBufferPointer<Float>, context: VisualFrameContext) -> Bool {
        guard target.pixelFormat == pixelFormat, let slot = shapes.freeSlot() else { return false }
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
        let count = layout.tessellate(into: shapes.vertices(slot), capacity: ParticleFountainLayout.maximumVertexCount, gain: gain)
        return shapes.draw(slot: slot, count: count, into: target, background: layout.background,
                           commandBuffer: commandBuffer)
    }
}
#endif
