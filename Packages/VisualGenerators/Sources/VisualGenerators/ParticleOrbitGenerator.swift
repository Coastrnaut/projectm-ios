// ParticleOrbitGenerator.swift — the particle orbit on Metal (VIS-009-R1, R8; contracts/particle-orbit.md C2).
//
// Each frame the host calls `drive(base:bass:)` (the mapped bass, `ParticleOrbitRadiusDrive`) and
// `enqueueBeat(atNanoseconds:)` for each accepted beat, stamped with the frame time. The input vector of `encode` is
// unused. Per frame: the simulation advances to the frame context's time (fixed 1/240 s steps) → squares
// (`ParticleOrbitLayout`) → the strobe safety envelope's gain over 17 areas (against the composited levels when
// `downstreamLuminance` is set; FX-001-R10, FX-019-R9) → tessellate into a free vertex buffer → `FlatShapePass`.
// No allocation per frame. Not Sendable: one thread drives a generator.
#if canImport(Metal) && !VISUAL_NO_METAL
import FlashSafety
import Metal

public final class ParticleOrbitGenerator: SpectrumTextureGenerator {
    public static let supportedPixelFormats = FlatShapePass.supportedPixelFormats

    public let device: MTLDevice
    public let pixelFormat: MTLPixelFormat
    /// The orbit's state.
    public let simulation: ParticleOrbitSimulation
    /// Geometry of the last frame (tests and diagnostics).
    public let layout = ParticleOrbitLayout()
    public let limiter = FlashSafetyLimiter()
    /// The envelope's gain of the last frame (1 when not limited).
    public private(set) var lastGain: Float = 1
    /// Vertices drawn in the last frame (VIS-009-S3).
    public private(set) var lastVertexCount = 0
    /// How stages after this generator change the frame's brightness (FX-001-R10); nil: none.
    public var downstreamLuminance: (any FrameLuminanceTransfer)?
    /// Kept for the host (it carries the bar count between native visuals); does not affect drawing.
    public var barCount: SpectrumBarCount = .b64

    private let shapes: FlatShapePass
    /// VIS-010: streak length (Off: the frame is exactly the pre-trails one). Applies from the next frame.
    public var trails: ParticleTrailLength = .off
    /// VIS-010: the fixed texture pair, made on the first frame with trails on and kept (nil before).
    public private(set) var trailPass: ParticleTrailPass?

    /// Changes apply from the next frame.
    public var configuration: ParticleOrbitConfiguration {
        get { simulation.configuration }
        set { simulation.configuration = newValue }
    }

    public init(device: MTLDevice, pixelFormat: MTLPixelFormat = .bgra8Unorm_srgb,
                configuration: ParticleOrbitConfiguration = ParticleOrbitConfiguration()) throws(VisualGeneratorError) {
        self.device = device
        self.pixelFormat = pixelFormat
        simulation = ParticleOrbitSimulation(configuration: configuration)
        shapes = try FlatShapePass(device: device, pixelFormat: pixelFormat,
                                   maximumVertexCount: ParticleOrbitLayout.maximumVertexCount, label: "VIS-009 Particle orbit")
    }

    /// The host's loop restart: slots reseeded, radius at the base, no pulse or queued beat; the limiter starts over.
    public func restartLoop() {
        limiter.reset()
        simulation.reset()
        trailPass?.reset()   // VIS-010: storage kept
    }

    /// VIS-009-R3, R4: this frame's base radius (R) and bass (0…1).
    public func drive(base: Double, bass: Double) {
        simulation.setTarget(base: base, bass: bass)
    }

    /// A beat at `nanoseconds` (the frame clock); false when the queue is full.
    @discardableResult
    public func enqueueBeat(atNanoseconds nanoseconds: UInt64) -> Bool {
        simulation.enqueueBeat(atNanoseconds: nanoseconds)
    }

    /// `bands` is unused: the orbit follows `drive` and `enqueueBeat`.
    public func encode(into target: MTLTexture, commandBuffer: MTLCommandBuffer,
                       bands: UnsafeBufferPointer<Float>, context: VisualFrameContext) -> Bool {
        guard target.pixelFormat == pixelFormat, let slot = shapes.freeSlot() else { return false }
        simulation.advance(toNanoseconds: context.timeNanoseconds)
        layout.layout(simulation: simulation, width: target.width, height: target.height)
        if trails != .off, target.width > 0, target.height > 0 { return encodeTrails(slot: slot, target: target, commandBuffer: commandBuffer, context: context) }
        if trails == .off, let pass = trailPass, !pass.needsReset { pass.reset() }   // VIS-010: on again starts empty
        let gain: Float
        if let downstream = downstreamLuminance {
            gain = limiter.gain(for: layout, transfer: downstream, frameTime: context.frameDuration,
                                configuration: context.flashConfiguration)
        } else {
            gain = limiter.gain(for: layout, transfer: IdentityLuminanceTransfer(), frameTime: context.frameDuration,
                                configuration: context.flashConfiguration)
        }
        lastGain = gain
        let count = layout.tessellate(into: shapes.vertices(slot), capacity: ParticleOrbitLayout.maximumVertexCount, gain: gain)
        lastVertexCount = count
        return shapes.draw(slot: slot, count: count, into: target, background: layout.background,
                           commandBuffer: commandBuffer)
    }

    /// VIS-010: the frame with trails (contracts/particle-trails.md C2).
    private func encodeTrails(slot: Int, target: MTLTexture, commandBuffer: MTLCommandBuffer, context: VisualFrameContext) -> Bool {
        let (device, format, library) = (self.device, pixelFormat, shapes.library)
        let frame = ParticleTrailFrame.encode(
            pass: trailPass, make: { () throws(VisualGeneratorError) -> ParticleTrailPass in
                try ParticleTrailPass(device: device, library: library, targetFormat: format, label: "VIS-009 Particle orbit")
            }, store: { (made: ParticleTrailPass) -> Void in trailPass = made }, length: trails,
            reduceMotion: configuration.reduceMotion, layout: layout, background: layout.background, limiter: limiter,
            downstream: downstreamLuminance, shapes: shapes, slot: slot, target: target, commandBuffer: commandBuffer, context: context
        ) { (gain: Float) -> Int in
            layout.tessellate(into: shapes.vertices(slot), capacity: ParticleOrbitLayout.maximumVertexCount, gain: gain)
        }
        lastGain = frame.gain
        lastVertexCount = frame.count
        return frame.drawn
    }
}
#endif
