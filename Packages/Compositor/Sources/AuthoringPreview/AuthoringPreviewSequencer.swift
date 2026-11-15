// AuthoringPreviewSequencer.swift — the preview's per-frame parameter trajectory (SHD-012-R1, R2, R3, R5, R8;
// contract P1, P2; research SHD-012-D1, D2, D5). Plain Swift; builds on Linux.
//
// Frame n (no real clock, no live audio):
//   1. REC-013's `OfflineAnalysisDriver` (the live ANL-016 analysis, stepped synchronously) analyses the fixture up to
//      `OfflineFrameClock.samplePosition(frame: n)` and returns the bands and the kick envelope;
//   2. MOD-002's `AudioFeatureModulator` advances every binding with those features at time t(n);
//   3. each bound parameter's effective value is stored into a copy of the base values with the material's own
//      clamping (what the GPU reads);
//   4. the material's `MaterialMotion` advances exactly as `ProceduralMaterialLayer.render` does: the frame duration
//      from a `LayerFrameClock` fed 1 s + t(n), the band level of the bands, the speed and reactivity slots (Float, as
//      the layer reads them).
// The state moves only in `step()`, so stepping frame by frame, in chunks or in one pass gives the same frames.
// Frames past the fixture's end read silence (the audio is padded with zeros). Not Sendable: one owner.
import AnalysisFeatures
import Compositor
import ParameterGraph
import ProceduralMaterials
import VisualBandFeed
import VisualGenerators

/// Why a preview could not start (nothing ran).
public enum AuthoringPreviewError: Error, Sendable, Equatable, CustomStringConvertible {
    /// A binding was refused (MOD-002 contract C2).
    case binding(AudioFeatureBindingError)
    /// The material's parameters do not form a valid registry.
    case registry(String)
    /// The fixture analysis could not be set up.
    case analysis(String)
    /// The GPU could not draw a frame (recorder only).
    case render(String)

    public var description: String {
        switch self {
        case let .binding(e): "the binding was refused: \(e)"
        case let .registry(s): "the material's parameters are invalid: \(s)"
        case let .analysis(s): "the fixture analysis failed: \(s)"
        case let .render(s): "a preview frame failed: \(s)"
        }
    }
}

/// What a preview run draws.
public struct AuthoringPreviewRequest: Sendable, Equatable {
    /// The manual (base) values; they carry the material definition.
    public var values: MaterialParameterValues
    /// MOD-002 bindings on the material's parameters, applied in list order (MOD-011).
    public var bindings: [AudioFeatureBinding]
    public var fixture: AuthoringPreviewFixture
    /// Frames to run; nil runs the whole fixture.
    public var frameCount: Int?

    public init(values: MaterialParameterValues, bindings: [AudioFeatureBinding] = [],
                fixture: AuthoringPreviewFixture = AuthoringPreviewFixture(), frameCount: Int? = nil) {
        self.values = values
        self.bindings = bindings
        self.fixture = fixture
        self.frameCount = frameCount
    }

    public var resolvedFrameCount: Int { max(frameCount ?? fixture.frameCount, 0) }

    /// The bound parameters, each once, in binding order.
    public var boundParameters: [ParameterID] {
        var seen: Set<ParameterID> = []
        var out: [ParameterID] = []
        for b in bindings where seen.insert(b.target).inserted { out.append(b.target) }
        return out
    }
}

/// One frame of a run.
public struct AuthoringPreviewFrame: Sendable, Equatable {
    public var index: Int
    /// Presentation time the layer sees: 1 s + n × 1e9 / fps (REC-002 and REC-013's start offset).
    public var presentationTimeNanoseconds: UInt64
    /// From `LayerFrameClock`: 0 on frame 0.
    public var frameDuration: Double
    /// The analysis bands this frame (the layer's audio context).
    public var bands: [Float]
    /// The kick envelope this frame.
    public var kick: Float
    /// The values the GPU reads this frame (bound parameters modulated).
    public var values: MaterialParameterValues
    /// `MaterialMotion` after this frame.
    public var phase: Double
    public var audioLevel: Double
}

/// The recorded trajectory of a run (exact Doubles).
public struct AuthoringPreviewTrajectory: Sendable, Equatable {
    /// Bound parameters, each once, in binding order.
    public var parameters: [ParameterID]
    /// `values[p][n]`: parameter p's effective value in frame n.
    public var values: [[Double]]
    public var phase: [Double]
    public var audioLevel: [Double]
    public var presentationTimeNanoseconds: [UInt64]

    public init(parameters: [ParameterID]) {
        self.parameters = parameters
        values = parameters.map { (_: ParameterID) -> [Double] in [] }
        phase = []
        audioLevel = []
        presentationTimeNanoseconds = []
    }

    public var frameCount: Int { phase.count }

    /// Appends one frame.
    public mutating func append(_ frame: AuthoringPreviewFrame) {
        for (i, id) in parameters.enumerated() { values[i].append(frame.values.double(id) ?? .nan) }
        phase.append(frame.phase)
        audioLevel.append(frame.audioLevel)
        presentationTimeNanoseconds.append(frame.presentationTimeNanoseconds)
    }

    /// One parameter's values, or nil when it is not bound.
    public func values(for id: ParameterID) -> [Double]? {
        parameters.firstIndex(of: id).map { (i: Int) -> [Double] in values[i] }
    }
}

public final class AuthoringPreviewSequencer {
    /// The live spectrum's default bar count (the analysis bands the material and the bindings see).
    public static let barCount: SpectrumBarCount = .b64
    public static let startNanoseconds: UInt64 = 1_000_000_000

    public let request: AuthoringPreviewRequest
    public let frameCount: Int
    private let clock: OfflineFrameClock
    private let driver: OfflineAnalysisDriver
    private let modulator: AudioFeatureModulator
    private let targets: [ParameterID]
    private let speedSlot: Int
    private let reactivitySlot: Int
    private var layerClock = LayerFrameClock()
    private var motion = MaterialMotion()
    private var next = 0

    public init(request: AuthoringPreviewRequest) throws(AuthoringPreviewError) {
        self.request = request
        frameCount = request.resolvedFrameCount
        clock = request.fixture.clock
        let definition: MaterialDefinition = request.values.definition
        let registry: ParameterRegistry
        do {
            registry = try ParameterRegistry(descriptors: definition.parameters)
        } catch {
            throw .registry(String(describing: error))
        }
        modulator = AudioFeatureModulator(registry: registry)
        do {
            try modulator.replaceBindings(request.bindings)
        } catch {
            throw .binding(error)
        }
        targets = request.boundParameters
        speedSlot = definition.slot(of: definition.speedParameter) ?? -1
        reactivitySlot = definition.slot(of: definition.reactivityParameter) ?? -1
        var audio: [Float] = request.fixture.audio()
        let needed: Int = clock.samplePosition(frame: frameCount) * 2
        if audio.count < needed { audio.append(contentsOf: [Float](repeating: 0, count: needed - audio.count)) }
        do {
            driver = try OfflineAnalysisDriver(interleaved: audio, barCount: Self.barCount)
        } catch {
            throw .analysis(String(describing: error))
        }
    }

    /// Frames already stepped.
    public var position: Int { next }

    /// The next frame, or nil after the last.
    public func step() -> AuthoringPreviewFrame? {
        guard next < frameCount else { return nil }
        let n: Int = next
        next += 1
        let t: UInt64 = clock.timeNanoseconds(frame: n)
        let analysis: OfflineAnalysisFrame = driver.advance(toSample: clock.samplePosition(frame: n))
        analysis.bands.withUnsafeBufferPointer { (bands: UnsafeBufferPointer<Float>) -> Void in
            modulator.advance(frame: AudioFeatureFrame(bands: bands, kick: analysis.kickEnvelope), timeNanoseconds: t)
        }
        var values: MaterialParameterValues = request.values
        for id in targets {
            guard let manual = request.values.value(for: id) else { continue }
            _ = try? values.set(modulator.value(for: id, manual: manual), for: id)
        }
        let presentation: UInt64 = Self.startNanoseconds + t
        let context: LayerFrameContext = layerClock.next(presentationTimeNanoseconds: presentation, outputWidth: 1, outputHeight: 1,
                                                         contentScale: 1, reduceFlashing: true)
        let level: Double = analysis.bands.withUnsafeBufferPointer { (bands: UnsafeBufferPointer<Float>) -> Double in
            MaterialMotion.bandLevel(bands)
        }
        motion.advance(frameDuration: context.frameDuration, bandLevel: level,
                       speed: Double(values.slot(speedSlot).x), reactivity: Double(values.slot(reactivitySlot).x))
        return AuthoringPreviewFrame(index: n, presentationTimeNanoseconds: context.presentationTimeNanoseconds,
                                     frameDuration: context.frameDuration, bands: analysis.bands, kick: analysis.kickEnvelope,
                                     values: values, phase: motion.phase, audioLevel: motion.audioLevel)
    }

    /// Up to `count` more frames.
    public func run(frames count: Int) -> [AuthoringPreviewFrame] {
        var out: [AuthoringPreviewFrame] = []
        out.reserveCapacity(max(min(count, frameCount - next), 0))
        while out.count < count, let frame = step() { out.append(frame) }
        return out
    }

    /// The trajectory of a whole run of `request`.
    public static func record(_ request: AuthoringPreviewRequest) throws(AuthoringPreviewError) -> AuthoringPreviewTrajectory {
        let sequencer = try AuthoringPreviewSequencer(request: request)
        var trajectory = AuthoringPreviewTrajectory(parameters: request.boundParameters)
        while let frame = sequencer.step() { trajectory.append(frame) }
        return trajectory
    }
}
