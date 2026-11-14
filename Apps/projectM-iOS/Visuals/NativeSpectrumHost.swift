// NativeSpectrumHost.swift — the native spectra on screen: the circular spectrum (VIS-001-R12 to R16,
// R18; research VIS-001-D8; ADR-0009) and the linear spectrum (VIS-002-R10 to R13; research
// VIS-002-D5). Formerly CircularSpectrumHost.swift.
//
// * One host, one frame loop, one analyzer and one glow chain for both visuals: the generator is
//   `any SpectrumTextureGenerator`. `apply(style:)` swaps the generator when the kind changes (the
//   new one's pipeline is built here on the main thread, outside the frame callback; a failure
//   throws and the caller falls back to projectM) and only updates the configuration when the
//   linear spectrum's orientation or spacing changes. The bar count carries over.
//
// * A `CAMetalLayer` view (`bgra8Unorm_srgb`, opaque). Its drawable size follows the view's bounds
//   × display scale × QualityGovernor's render scale at every layout, so rotation and iPad sizes need
//   nothing else: the generator lays out for whatever size it gets (VIS-001-R5).
// * A `CADisplayLink` on the main run loop at QualityGovernor's frame-rate range (FR-049, as
//   ANGLERenderer). Each frame takes the newest band vector from `LiveBandAnalyzer` without waiting,
//   encodes it with the generator into the next drawable and presents it.
// * `LiveBandAnalyzer` pulls the capture manager's analysis tap on its own queue (VIS-001-R14); it
//   runs only while the frame loop runs.
// * pause()/resume() (FR-046; also used while projectM is shown) and PERF-011 suspension are
//   independent, like ANGLERenderer: the loop runs only when neither applies. Suspension stops the
//   display link and the analyzer before it returns and drops nothing else; resuming restarts the
//   Reduce-flashing limiter from the next frame (no ramp from a stale picture).
// * Glow (FX-001, ADR-0010): a `BloomEffect` in an `EffectChain` built with the host. While the glow
//   is pass-through (off or intensity 0) the generator draws straight into the drawable, exactly as
//   VIS-001; otherwise it draws into the chain's image and the bloom composites into the drawable.
//   The generator's `downstreamLuminance` is the bloom's luminance model, so Reduce flashing bounds
//   the composited frame (FX-001-R10). If the bloom cannot be built (or its textures cannot be
//   created later) the visual keeps rendering without it and `glowUnavailable` is set (FX-001-R13).
//   The view's accessibility value names the glow state.
// * Per frame, this file's code allocates nothing: the band scratch is preallocated; the chain's
//   textures are created only when the drawable size changes; Metal's command buffer and drawable
//   are the system's.
// * Audio feature bindings (MOD-002; research MOD-002-D6, D8): the host owns an
//   `AudioFeatureModulator` over the visual catalog. With no binding nothing below changes. With a
//   binding, each frame advances it with the frame's bands and display time and resolves the
//   effective glow from the manual `glow` (which modulation never writes): the bloom gets the
//   effective intensity (an intensity-only change updates its uniforms, no plan rebuild) and the
//   generator's downstream luminance is a `ModulatedGlowLuminance` reference whose model follows
//   the effective glow, so Reduce flashing (FX-019) bounds the frame actually shown. No allocation
//   per frame. Unbinding returns to the manual glow at once.
// * Oscilloscope (VIS-003; research VIS-003-D1): the host hands the analyzer a `WaveformTap` around
//   the analysis tap (a pass-through: the analyzer's bands are unchanged) that also keeps the newest
//   4,096 mono samples. While the oscilloscope is shown, each frame copies the newest history into a
//   preallocated scratch and passes it to the generator instead of the bands; modulation still advances
//   with the bands. The oscilloscope's line and window change only its configuration.
// * Lissajous (VIS-004; research VIS-004-D1): the same tap also keeps the newest 2,048 stereo frames; while
//   the Lissajous is shown each frame copies them (interleaved) into the same scratch and passes them to the
//   generator. Its plot and persistence change only its configuration; the persistence half-life is the
//   ACC-012-capped one (`LissajousConfiguration.persistenceHalfLife(enabled:clamp:)`), re-applied whenever
//   the style or `safetyClamp` changes.
// * Radial waveform (VIS-005): draws the same mono history as the oscilloscope, wrapped around a ring; its
//   ring size and amplitude change only its configuration (no new generator).
// * Beat rings (VIS-006; research VIS-006-D1, D2): while beat rings are shown the host holds a second
//   subscription on its analyzer's bus; each frame drains it (`nextEvent`, a value copy, no allocation) through
//   `BeatRingTrigger` (confident ANL-005 beats, the ANL-007 kick as the fallback) and emits a ring stamped with
//   the frame's time under the frame's envelope (the rate cap). Leaving the style unsubscribes; a loop start
//   discards events that queued while stopped. The ring life changes only its configuration.
// * Mandala (VIS-007): draws the smoothed bands as N rotated petals; symmetry, mirror and petal style change only
//   its configuration. `reduceMotion` (the system setting, from the coordinator) halves its turn (VIS-007-R5).
// * Particle fountain (VIS-008): the same bus subscription as beat rings while it is shown; each drained ANL-004 onset
//   (`ParticleFountainTrigger`) is enqueued stamped with the frame's time, and the generator steps its seeded
//   simulation to the frame. Gravity changes only its configuration (later bursts); `reduceMotion` halves its bursts
//   and slows them (VIS-008-R9). A loop start discards queued events and restarts the simulation.
// * Particle orbit (VIS-009): the same bus subscription; each event `BeatRingTrigger` accepts queues a centre pulse
//   stamped with the frame's time. After the modulation step each frame, `driveParticleOrbit` hands the generator
//   its base radius and bass through `ParticleOrbitRadiusDrive` (unbound: the Radius setting and the kick envelope;
//   bound: the modulator's value and no bass). Radius changes only its configuration; `reduceMotion` slows it (R9).
// * REC-001 (research REC-001-D1): `captureFrame` turns the layer's `framebufferOnly` off until the
//   next readable drawable is drawn, blits that drawable (the frame as shown: glow and Reduce
//   flashing included) into a shared buffer and delivers 8-bit sRGB BGRA on the main actor; then
//   `framebufferOnly` returns to true. Stopping the loop cancels a pending capture.
// * Spectral smoothing (ANL-003-R2, R3, R5; research ANL-003-D1): each frame the newest raw bands
//   go through a `BandSmoother` (attack/release from `smoothing`, the real interval between display
//   link timestamps, the bus frame's session as its generation) and the spectra draw the result;
//   MOD-002 modulation keeps the raw bands. Instant (the default) is a bit-exact copy. Starting the
//   loop and changing the bar count reset it, so nothing ramps from a stale picture. Preallocated;
//   nothing allocates per frame.
// * Adaptive effect quality (PERF-003; NativeSpectrumHost+EffectQuality.swift): one `EffectQualityLadder` started with
//   the loop and stepped each frame with the display-link time, the thermal state, Low Power and PERF-002's budget
//   signal. Its level goes to the bloom (Reduced: fewer taps, coarser glow; Minimal: no glow pass) and its fade weight
//   multiplies the glow intensity after the ACC-012 clamp, so the FX-019 limiter models the glow actually drawn. With
//   the glow switched on the governor defers the serious-state frame-rate cap to the ladder (PERF-003-R7).
import AnalysisFeatures
import AudioCore
import FlashSafety
import FrameCapture
import FrameTiming
import Metal
import ParameterGraph
import PerformanceControlAnalysis
import PresentationLifecycle
import QuartzCore
import Rendering
import UIKit
import VisualBandFeed
import VisualEffects
import VisualGenerators
import VisualParameters

@MainActor
final class NativeSpectrumHost: PresentationBoundResource {
    let view: NativeSpectrumLayerView
    private var generator: any SpectrumTextureGenerator
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    /// Which native spectrum is drawn (VIS-002-D5).
    private(set) var style: NativeSpectrumStyle
    private let analyzer: LiveBandAnalyzer
    private let reader: (any NormalizedPCMReader)?
    /// VIS-003: the analyzer reads through this tap; it keeps the newest samples for the oscilloscope.
    private let waveform: WaveformTap?
    private let bands: UnsafeMutablePointer<Float>
    /// VIS-003: the newest sample history (zeros until the first one arrives).
    private let samples: UnsafeMutablePointer<Float>
    private var bandCount = 0
    /// ANL-003: the smoother, the newest frame's session and the previous display-link timestamp.
    private let smoother = BandSmoother()
    private var bandSession: UInt64 = 0
    /// ANL-007: the newest frame's kick envelope, fed to the bindings (MOD-002's Kick source).
    private var kickEnvelope: Float = 0
    /// ANL-010: the newest frame's normalized spectral centroid, fed to the bindings (MOD-002's
    /// Centroid source).
    private var centroid: Float = 0
    /// ANL-014: the newest frame's loudness envelope, fed to the bindings (MOD-002's Loudness source).
    private var loudness: Float = 0
    /// ANL-008: the newest frame's mid transient value, fed to the bindings (MOD-002's Mid transient source).
    private var midTransient: Float = 0
    /// ANL-009: the newest frame's high transient value, fed to the bindings (MOD-002's High transient source).
    private var highTransient: Float = 0
    /// ANL-011: the newest frame's normalized rolloff, fed to the bindings (MOD-002's Rolloff source).
    private var rolloff: Float = 0
    /// ANL-012: the newest frame's spectral flatness, fed to the bindings (MOD-002's Flatness source).
    private var flatness: Float = 0
    /// ANL-013: the newest frame's stereo correlation (−1…1), fed to the bindings (MOD-002's Correlation source).
    private(set) var correlation: Float = 0
    /// ANL-015: the newest frame's section-change envelope (0…1), fed to the bindings (MOD-002's Section change source).
    private var sectionChange: Float = 0
    /// ANL-013: the newest frame's phase-inversion warning; changes go to `onPhaseWarningChange`.
    private(set) var phaseInverted = false
    /// ANL-013: called on the main actor when the warning is raised or cleared (cleared on start and stop).
    var onPhaseWarningChange: (@MainActor (Bool) -> Void)?
    private var lastLinkTimestamp: CFTimeInterval?
    private var displayLink: CADisplayLink?
    private var paused = true
    private(set) var isSuspended = false
    private var meter = FrameRateMeter()
    /// PERF-007: the output's frame drop counter while the performance overlay is shown (nil: no counting work).
    var frameDrops: FrameDropCounter?
    /// PERF-001: the stage timer while the performance overlay is shown (nil: no timing work), and the
    /// frames' command buffers until their GPU times are known.
    var stageTimer: FrameStageTimer? {
        didSet {
            stageTimer?.configure(pipeline: Self.frameStages)
            gpuTimes.reset()
        }
    }
    static let frameStages: [FrameStage] = [.audio, .render, .encode, .present]
    private let gpuTimes = MetalGPUFrameTimes()
    private var quality = QualityGovernor.current()
    /// FR-049 / PERF-003-R7: the frame-rate cap and render scale this loop uses.
    var qualitySettings: QualitySettings { quality }
    /// PERF-003: the effect quality ladder and its inputs (NativeSpectrumHost+EffectQuality.swift).
    let effectLadder = EffectQualityLadder()
    /// PERF-002's verdict while the performance overlay runs (any flag → over); `.unavailable` otherwise.
    var effectBudget: EffectBudgetSignal = .unavailable
    /// Tests and DEBUG `-uitestThermalState` replace the device's thermal state; tests replace Low Power.
    var thermalOverride: EffectThermalState? = NativeSpectrumHost.launchThermalOverride
    var lowPowerOverride: Bool?
    /// The inputs as last read (`refreshQuality()`).
    var effectThermal: EffectThermalState = .nominal
    var effectLowPower = false
    private var observers: [NSObjectProtocol] = []

    /// Frame rate and frame time for the FR-048 overlay.
    private(set) var metrics = RenderMetrics.zero
    private(set) var presentedFrameCount = 0
    /// FR-072: the app's Reduce flashing setting (ACC-012: the effective one, `SafetyClamp.reducesFlashing`).
    var reduceFlashing = false

    /// ACC-012-R4: the sensory safety clamp. Applied where each frame's glow is resolved (after MOD-002
    /// modulation, before the bloom and the generator's luminance model) and to the frame context's flash
    /// envelope. `.standard` changes nothing (ADR-0049).
    var safetyClamp: SafetyClamp = .standard {
        didSet {
            guard safetyClamp != oldValue else { return }
            resolveEffectiveGlow()
            applyLissajousPersistence()   // VIS-004-R9
        }
    }

    /// MIDI-003-R7, R8: live values of MIDI-mapped glow parameters (`BloomParameters.midiControlledIDs`). They
    /// replace the manual glow fields before MOD-002 modulation and the ACC-012 clamp; empty is the FX-001 path.
    var externalValues: [ParameterID: Double] = [:] {
        didSet { if externalValues != oldValue { resolveEffectiveGlow() } }
    }

    /// FX-001: the bloom and the chain that runs it; nil when the glow is unavailable.
    let bloom: BloomEffect?
    private var chain: EffectChain?
    /// The glow could not be built on this device (FX-001-R13); the visual renders without it.
    private(set) var glowUnavailable: Bool

    /// The glow settings; applied from the next frame (no shader rebuild, FX-001-R12).
    var glow = BloomParameters() {
        didSet { applyGlow() }
    }

    /// ACC-003-R13: the bars' palette (VIS-001's spectrum, or the colour-blind-safe ramp); applied to the
    /// current generator and to every generator a style change builds.
    var palette: VisualPalette = .spectrum {
        didSet { if palette != oldValue { applyPalette() } }
    }

    /// The palette the current generator draws with (tests).
    var generatorPalette: VisualPalette? {
        (generator as? CircularSpectrumGenerator)?.configuration.palette
            ?? (generator as? LinearSpectrumGenerator)?.configuration.palette
            ?? (generator as? OscilloscopeGenerator)?.configuration.palette
            ?? (generator as? LissajousGenerator)?.configuration.palette
            ?? (generator as? RadialWaveformGenerator)?.configuration.palette
            ?? (generator as? BeatRingGenerator)?.configuration.palette
            ?? (generator as? MandalaGenerator)?.configuration.palette
            ?? (generator as? ParticleFountainGenerator)?.configuration.palette
            ?? (generator as? ParticleOrbitGenerator)?.configuration.palette
    }

    private func applyPalette() {
        if let circular = generator as? CircularSpectrumGenerator {
            var configuration = circular.configuration
            configuration.palette = palette
            circular.configuration = configuration
        } else if let linear = generator as? LinearSpectrumGenerator {
            var configuration = linear.configuration
            configuration.palette = palette
            linear.configuration = configuration
        } else if let scope = generator as? OscilloscopeGenerator {
            var configuration = scope.configuration
            configuration.palette = palette
            scope.configuration = configuration
        } else if let lissajous = generator as? LissajousGenerator {
            var configuration = lissajous.configuration
            configuration.palette = palette
            lissajous.configuration = configuration
        } else if let radial = generator as? RadialWaveformGenerator {
            var configuration = radial.configuration
            configuration.palette = palette
            radial.configuration = configuration
        } else if let rings = generator as? BeatRingGenerator {
            var configuration = rings.configuration
            configuration.palette = palette
            rings.configuration = configuration
        } else if let mandala = generator as? MandalaGenerator {
            var configuration = mandala.configuration
            configuration.palette = palette
            mandala.configuration = configuration
        } else if let fountain = generator as? ParticleFountainGenerator {
            var configuration = fountain.configuration
            configuration.palette = palette
            fountain.configuration = configuration
        } else if let orbit = generator as? ParticleOrbitGenerator {
            var configuration = orbit.configuration
            configuration.palette = palette
            orbit.configuration = configuration
        }
    }

    /// VIS-009: the particle orbit's generator (tests; nil for another visual).
    var particleOrbitGenerator: ParticleOrbitGenerator? { generator as? ParticleOrbitGenerator }

    /// VIS-008: the particle fountain's generator (tests; nil for another visual).
    var particleFountainGenerator: ParticleFountainGenerator? { generator as? ParticleFountainGenerator }

    /// VIS-007: the mandala's generator (tests; nil for another visual).
    var mandalaGenerator: MandalaGenerator? { generator as? MandalaGenerator }

    /// VIS-007-R5, ACC-001: the system Reduce Motion; halves the mandala's turn (applied to every generator a style
    /// change builds).
    var reduceMotion = false {
        didSet { if reduceMotion != oldValue { applyReduceMotion() } }
    }

    private func applyReduceMotion() {
        if let fountain = generator as? ParticleFountainGenerator, fountain.configuration.reduceMotion != reduceMotion {
            var configuration = fountain.configuration   // VIS-008-R9: later bursts
            configuration.reduceMotion = reduceMotion
            fountain.configuration = configuration
        }
        if let orbit = generator as? ParticleOrbitGenerator, orbit.configuration.reduceMotion != reduceMotion {
            var configuration = orbit.configuration   // VIS-009-R9: half speed, smaller pulse, slower radius
            configuration.reduceMotion = reduceMotion
            orbit.configuration = configuration
        }
        guard let mandala = generator as? MandalaGenerator, mandala.configuration.reduceMotion != reduceMotion else { return }
        var configuration = mandala.configuration
        configuration.reduceMotion = reduceMotion   // the layout re-anchors, so the angle stays continuous
        mandala.configuration = configuration
    }

    /// VIS-005: the radial waveform's generator (tests; nil for another visual).
    var radialWaveformGenerator: RadialWaveformGenerator? { generator as? RadialWaveformGenerator }

    /// VIS-006: the beat rings' generator (tests; nil for another visual).
    var beatRingGenerator: BeatRingGenerator? { generator as? BeatRingGenerator }
    /// VIS-006: the bus subscription drained for beat rings (nil unless they are shown).
    private(set) var beatEvents: AnalysisSubscription?
    private var beatTrigger = BeatRingTrigger()

    /// VIS-006, VIS-008: subscribes while beat rings or the particle fountain are shown, unsubscribes otherwise.
    private func updateBeatSubscription() {
        if style.drainsAnalysisEvents {
            guard beatEvents == nil else { return }
            beatEvents = try? analyzer.subscribe()
            beatTrigger = BeatRingTrigger()
        } else if let subscription = beatEvents {
            analyzer.unsubscribe(subscription)
            beatEvents = nil
        }
    }

    /// VIS-006: emits a ring for each accepted event since the last frame, stamped with the frame's time.
    /// VIS-008: enqueues each onset into the particle fountain, stamped likewise.
    /// VIS-009: queues a centre pulse for each event the beat trigger accepts, stamped likewise.
    func drainBeatEvents(context: VisualFrameContext) {
        guard let subscription = beatEvents else { return }
        if let fountain = generator as? ParticleFountainGenerator {
            while let event = subscription.nextEvent() {
                guard let onset = ParticleFountainTrigger.onset(event) else { continue }
                fountain.enqueueOnset(atNanoseconds: context.timeNanoseconds, strength: onset.strength, threshold: onset.threshold)
            }
            return
        }
        if let orbit = generator as? ParticleOrbitGenerator {
            while let event = subscription.nextEvent() {
                if beatTrigger.shouldEmit(event) { orbit.enqueueBeat(atNanoseconds: context.timeNanoseconds) }
            }
            return
        }
        guard let rings = generator as? BeatRingGenerator else { return }
        while let event = subscription.nextEvent() {
            if beatTrigger.shouldEmit(event) {
                rings.emitRing(atNanoseconds: context.timeNanoseconds, flashConfiguration: context.flashConfiguration)
            }
        }
    }

    /// VIS-006: forgets events that queued while the loop was stopped.
    private func discardBeatEvents() {
        guard let subscription = beatEvents else { return }
        while subscription.nextEvent() != nil {}
        beatTrigger = BeatRingTrigger()
    }

    /// VIS-004-R9: the Lissajous's persistence half-life under the safety clamp (0 = off).
    private func applyLissajousPersistence() {
        guard case let .lissajous(_, persistence) = style, let lissajous = generator as? LissajousGenerator else { return }
        let halfLife: Double = LissajousConfiguration.persistenceHalfLife(enabled: persistence, clamp: safetyClamp)
        guard lissajous.configuration.persistenceHalfLife != halfLife else { return }
        var configuration = lissajous.configuration
        configuration.persistenceHalfLife = halfLife
        lissajous.configuration = configuration
    }

    /// VIS-004: the Lissajous's effective persistence half-life (tests; nil for another visual).
    var lissajousPersistenceHalfLife: Double? { (generator as? LissajousGenerator)?.configuration.persistenceHalfLife }

    /// The bloom runs (available and the effective glow not pass-through).
    var glowActive: Bool { chain != nil && !effectiveGlow.isPassThrough }

    /// MOD-002: the glow actually rendered, `glow` with any bound intensity applied.
    private(set) var effectiveGlow = BloomParameters()
    /// MOD-002: audio feature bindings over the visual catalog (nil only if the catalog failed to
    /// validate, which `VisualParameterCatalogTests` rules out in CI).
    private let modulator: AudioFeatureModulator? = (try? VisualParameterCatalog.makeRegistry()).map(AudioFeatureModulator.init(registry:))
    /// MOD-006: the current scene's threshold triggers, stepped with the same frame as the bindings.
    private let triggerBank = ThresholdTriggerBank()
    /// MOD-006: performs a fired trigger's action (the app connects MIDI-006's performer).
    var onTrigger: (@MainActor (ThresholdTriggerAction) -> Void)?
    /// MOD-007: the current scene's oscillators and the per-frame values the bindings read (`audio.lfo.<index>`).
    private let lfoBank = LFOBank()
    private let lfoValues = UnsafeMutableBufferPointer<Double>.allocate(capacity: LFOBank.maximumOscillators)
    /// MOD-015: every band's fast, medium and slow envelope (`audio.bandEnvelope.<profile>.<band>`), advanced with the
    /// bindings on the frame clock; preallocated, so a frame allocates nothing.
    private let bandEnvelopeBank = BandEnvelopeBank()
    /// MOD-009: the BPM tempo-synced oscillators follow (nil: their stored rate); read once per frame while one exists.
    var lfoTempoBPM: (@MainActor () -> Double?)?
    /// MOD-002: the luminance model the generator sees while the glow intensity is bound.
    private let glowLuminance = ModulatedGlowLuminance()
    /// REC-001: the handler waiting for the next readable frame.
    private var pendingCapture: (@MainActor (CapturedPixels?) -> Void)?
    /// REC-003: the attached video recording; the drawables stay readable while it is set.
    var videoRecording: VideoRecordingTap? {
        didSet { view.metalLayer.framebufferOnly = videoRecording == nil && pendingCapture == nil }
    }
    /// REC-003: the device the recording's pixel buffers are made for.
    var recordingDevice: MTLDevice { device }

    /// ANL-003: attack and release of the drawn bands (Instant by default); from the next frame.
    var smoothing: SmoothingTimes {
        get { smoother.times }
        set { smoother.times = newValue }
    }

    var barCount: SpectrumBarCount {
        get { generator.barCount }
        set {
            guard newValue != generator.barCount else { return }
            generator.barCount = newValue
            analyzer.setBarCount(newValue)
            bandCount = 0   // the old vector does not match the new bars
            smoother.reset()   // ANL-003-R5
        }
    }

    /// Throws `VisualGeneratorError` when there is no Metal device or the pipeline cannot be built
    /// (VIS-001-R16); the caller falls back to projectM.
    /// A glow that cannot be built does not throw: the host renders without it (FX-001-R13).
    /// `forceGlowFailure` simulates that failure (DEBUG UI tests).
    static func make(device: MTLDevice?, reader: (any NormalizedPCMReader)?, style: NativeSpectrumStyle = .circular,
                     barCount: SpectrumBarCount, glow: BloomParameters = BloomParameters(),
                     forceGlowFailure: Bool = false) throws -> NativeSpectrumHost {
        guard let device, let queue = device.makeCommandQueue() else { throw VisualGeneratorError.noDevice }
        let generator = try makeGenerator(device: device, style: style, barCount: barCount)
        let analyzer = try LiveBandAnalyzer(barCount: barCount)
        var bloom: BloomEffect?
        var chain: EffectChain?
        if !forceGlowFailure {
            do {
                let effect = try BloomEffect(device: device, pixelFormat: .bgra8Unorm_srgb, parameters: glow)
                chain = try EffectChain(device: device, pixelFormat: .bgra8Unorm_srgb, effects: [effect])
                bloom = effect
            } catch {
                bloom = nil
                chain = nil
            }
        }
        let host = NativeSpectrumHost(device: device, queue: queue, style: style, generator: generator, analyzer: analyzer,
                                      reader: reader, bloom: bloom, chain: chain)
        host.glow = glow
        host.updateBeatSubscription()   // VIS-006
        return host
    }

    /// The generator of `style` (pipeline built here).
    private static func makeGenerator(device: MTLDevice, style: NativeSpectrumStyle,
                                      barCount: SpectrumBarCount) throws -> any SpectrumTextureGenerator {
        switch style {
        case .circular:
            return try CircularSpectrumGenerator(device: device, pixelFormat: .bgra8Unorm_srgb,
                                                 configuration: CircularSpectrumConfiguration(barCount: barCount))
        case let .linear(orientation, spacing):
            return try LinearSpectrumGenerator(device: device, pixelFormat: .bgra8Unorm_srgb,
                                               configuration: LinearSpectrumConfiguration(barCount: barCount, orientation: orientation,
                                                                                          spacing: spacing))
        case let .oscilloscope(line, window):
            let generator = try OscilloscopeGenerator(device: device, pixelFormat: .bgra8Unorm_srgb,
                                                      configuration: oscilloscopeConfiguration(line: line, windowMilliseconds: window))
            generator.barCount = barCount
            return generator
        case let .lissajous(mode, _):
            // The persistence half-life is applied by `applyLissajousPersistence()` (it needs the clamp).
            let generator = try LissajousGenerator(device: device, pixelFormat: .bgra8Unorm_srgb,
                                                   configuration: LissajousConfiguration(mode: mode))
            generator.barCount = barCount
            return generator
        case let .radialWaveform(ring, amplitude):   // VIS-005
            let generator = try RadialWaveformGenerator(device: device, pixelFormat: .bgra8Unorm_srgb,
                                                        configuration: RadialWaveformConfiguration(baseRadius: ring.value,
                                                                                                   amplitude: amplitude.value))
            generator.barCount = barCount
            return generator
        case let .beatRings(life):   // VIS-006
            let generator = try BeatRingGenerator(device: device, pixelFormat: .bgra8Unorm_srgb,
                                                  configuration: BeatRingConfiguration(life: life.seconds))
            generator.barCount = barCount
            return generator
        case let .mandala(symmetry, mirror, petal):   // VIS-007
            let generator = try MandalaGenerator(device: device, pixelFormat: .bgra8Unorm_srgb,
                                                 configuration: MandalaConfiguration(symmetry: symmetry, mirror: mirror,
                                                                                     petalStyle: petal))
            generator.barCount = barCount
            return generator
        case let .particleFountain(gravity):   // VIS-008
            let generator = try ParticleFountainGenerator(device: device, pixelFormat: .bgra8Unorm_srgb,
                                                          configuration: ParticleFountainConfiguration(gravity: gravity.value))
            generator.barCount = barCount
            return generator
        case let .particleOrbit(radius):   // VIS-009
            let generator = try ParticleOrbitGenerator(device: device, pixelFormat: .bgra8Unorm_srgb,
                                                       configuration: ParticleOrbitConfiguration(radius: radius.value))
            generator.barCount = barCount
            return generator
        }
    }

    /// VIS-003: the oscilloscope's configuration for the app's choices.
    private static func oscilloscopeConfiguration(line: OscilloscopeLine, windowMilliseconds: Int) -> OscilloscopeConfiguration {
        OscilloscopeConfiguration(windowMilliseconds: Double(windowMilliseconds), lineThickness: line.thickness)
    }

    private init(device: MTLDevice, queue: MTLCommandQueue, style: NativeSpectrumStyle, generator: any SpectrumTextureGenerator,
                 analyzer: LiveBandAnalyzer, reader: (any NormalizedPCMReader)?, bloom: BloomEffect?, chain: EffectChain?) {
        self.device = device
        self.queue = queue
        self.style = style
        self.generator = generator
        self.analyzer = analyzer
        self.reader = reader
        waveform = reader.map { (r: any NormalizedPCMReader) -> WaveformTap in WaveformTap(r) }
        self.bloom = bloom
        self.chain = chain
        glowUnavailable = chain == nil
        bands = .allocate(capacity: SpectrumBarCount.maximum)
        bands.initialize(repeating: 0, count: SpectrumBarCount.maximum)
        samples = .allocate(capacity: WaveformFrameBuffer.capacity)
        samples.initialize(repeating: 0, count: WaveformFrameBuffer.capacity)
        view = NativeSpectrumLayerView(device: device)
        view.onLayout = { [weak self] in self?.layoutDrawable() }
        observeFrameRatePressure()
        applyGlow()
        applyLissajousPersistence()   // VIS-004-R9
    }

    /// Switches the drawn spectrum (VIS-002-D5). Another kind builds its generator (throws
    /// `VisualGeneratorError` when its pipeline fails; the current one keeps drawing); the linear
    /// spectrum's orientation and spacing only change its configuration. The envelope's history
    /// starts over with a new generator (a new visual, FX-019-R11).
    func apply(style newStyle: NativeSpectrumStyle) throws {
        guard newStyle != style else { return }
        if case let .linear(orientation, spacing) = newStyle, let linear = generator as? LinearSpectrumGenerator {
            var configuration = linear.configuration
            configuration.orientation = orientation
            configuration.spacing = spacing
            linear.configuration = configuration
        } else if case let .oscilloscope(line, window) = newStyle, let scope = generator as? OscilloscopeGenerator {
            var configuration = scope.configuration
            let wanted = Self.oscilloscopeConfiguration(line: line, windowMilliseconds: window)
            configuration.lineThickness = wanted.lineThickness
            configuration.windowMilliseconds = wanted.windowMilliseconds
            scope.configuration = configuration
        } else if case let .lissajous(mode, _) = newStyle, let lissajous = generator as? LissajousGenerator {
            var configuration = lissajous.configuration
            configuration.mode = mode   // a mode change clears the ghosts (VIS-004-R8)
            lissajous.configuration = configuration
        } else if case let .radialWaveform(ring, amplitude) = newStyle, let radial = generator as? RadialWaveformGenerator {
            var configuration = radial.configuration   // VIS-005: in place, from the next frame
            configuration.baseRadius = ring.value
            configuration.amplitude = amplitude.value
            radial.configuration = configuration
        } else if case let .beatRings(life) = newStyle, let rings = generator as? BeatRingGenerator {
            var configuration = rings.configuration   // VIS-006: in place, from the next frame
            configuration.life = life.seconds
            rings.configuration = configuration
        } else if case let .mandala(symmetry, mirror, petal) = newStyle, let mandala = generator as? MandalaGenerator {
            var configuration = mandala.configuration   // VIS-007: in place, from the next frame
            configuration.symmetry = symmetry
            configuration.mirror = mirror
            configuration.petalStyle = petal
            mandala.configuration = configuration
        } else if case let .particleFountain(gravity) = newStyle, let fountain = generator as? ParticleFountainGenerator {
            var configuration = fountain.configuration   // VIS-008: later bursts, no rebuild
            configuration.gravity = gravity.value
            fountain.configuration = configuration
        } else if case let .particleOrbit(radius) = newStyle, let orbit = generator as? ParticleOrbitGenerator {
            var configuration = orbit.configuration   // VIS-009: the base radius, eased in by the simulation
            configuration.radius = radius.value
            orbit.configuration = configuration
        } else {
            let replacement = try Self.makeGenerator(device: device, style: newStyle, barCount: generator.barCount)
            generator = replacement
            applyPalette()   // ACC-003-R13: a new generator starts with the default palette
            applyReduceMotion()   // VIS-007-R5
            samples.update(repeating: 0, count: WaveformFrameBuffer.capacity)   // VIS-004: mono and stereo histories differ
        }
        style = newStyle
        updateBeatSubscription()   // VIS-006
        applyLissajousPersistence()   // VIS-004-R9
        applyGlow()
    }

    private func applyGlow() {
        resolveEffectiveGlow()
        view.accessibilityLabel = "\(style.title) visualization"
        view.accessibilityIdentifier = style.accessibilityIdentifier
        view.accessibilityValue = Self.accessibilityValue(style: style, glowEnabled: glow.enabled, glowUnavailable: glowUnavailable)
        refreshQuality()   // PERF-003-R7: switching the glow changes whether the governor defers the serious cap
    }

    // MARK: - Audio feature bindings (MOD-002)

    private var glowIntensityIsBound: Bool { modulator?.isBound(VisualParameterIDs.bloomIntensity) ?? false }

    /// Applies `glow` with any bound intensity to the bloom and the luminance model. Unbound, this is
    /// exactly the FX-001 path.
    func resolveEffectiveGlow() {
        // MOD-011 order: base (MIDI-003's live value replaces the manual one) → every binding in list order,
        // clamped after each → ACC-012 depth scaling → ACC-012-R4 cap (`GlowModulationOrder`, ADR-0057).
        let base: BloomParameters = glow.applying(externalValues)
        var resolved: BloomParameters = GlowModulationOrder.resolve(base: base, modulator: modulator, clamp: safetyClamp)
        let factor: Float = effectLadder.intensityFactor   // PERF-003-R8: after the clamp; only ever lowers the glow
        if factor < 1 { resolved.intensity *= factor }
        effectiveGlow = resolved
        bloom?.parameters = resolved
        if glowIntensityIsBound {
            glowLuminance.model = BloomLuminanceModel(parameters: resolved)
            generator.downstreamLuminance = glowActive ? glowLuminance : nil   // a class reference: no allocation
        } else {
            generator.downstreamLuminance = glowActive ? BloomLuminanceModel(parameters: resolved) : nil
        }
    }

    /// Binds an audio feature to a catalog parameter (validated, MOD-002 contract C2); effective
    /// from the next frame.
    func bind(_ binding: AudioFeatureBinding) throws(AudioFeatureBindingError) {
        guard let modulator else { throw .unknownTarget(binding.target) }
        try modulator.bind(binding)
        resolveEffectiveGlow()
    }

    /// MOD-011: adds `binding` as its parameter's next layer (applied after the ones already bound); the
    /// first binding when the parameter is unbound. At most 4 per parameter.
    func addLayer(_ binding: AudioFeatureBinding) throws(AudioFeatureBindingError) {
        guard let modulator else { throw .unknownTarget(binding.target) }
        try modulator.addLayer(binding)
        resolveEffectiveGlow()
    }

    /// The live bindings in order (SCN-002 captures them into the current scene).
    var bindings: [AudioFeatureBinding] { modulator?.bindings ?? [] }

    /// MOD-012-R3: turns one layer on or off in place (its signal keeps running); effective at once.
    func setLayerEnabled(_ enabled: Bool, for target: ParameterID, layer: Int) throws(AudioFeatureBindingError) {
        guard let modulator else { throw .unknownTarget(target) }
        try modulator.setEnabled(enabled, for: target, layer: layer)
        resolveEffectiveGlow()
    }

    /// MOD-012-R6: moves one layer within its parameter (the fold order); signals move with their layers.
    func moveLayer(of target: ParameterID, from: Int, to: Int) throws(AudioFeatureBindingError) {
        guard let modulator else { throw .unknownTarget(target) }
        try modulator.moveLayer(of: target, from: from, to: to)
        resolveEffectiveGlow()
    }

    /// MOD-012 (undo): replaces every binding (all or nothing; signals restart at 0).
    func replaceBindings(_ list: [AudioFeatureBinding]) throws(AudioFeatureBindingError) {
        guard let modulator else { throw .unknownTarget(list.first?.target ?? VisualParameterIDs.bloomIntensity) }
        try modulator.replaceBindings(list)
        resolveEffectiveGlow()
    }

    /// MOD-012-R7: the current 0…1 signal of `target`'s `layer`-th binding (the route detail's live value).
    func layerSignal(for target: ParameterID, layer: Int) -> Double? { modulator?.signal(for: target, layer: layer) }

    /// UIX-003-R7: the modulator's value for `id` given `manual`; nil when `id` is unbound. Read-only.
    func modulatorValue(for id: ParameterID, manual: Double) -> Double? {
        guard let modulator, modulator.isBound(id) else { return nil }
        return modulator.value(for: id, manual: manual)
    }

    /// Removes a binding; the parameter returns to its manual value at once.
    @discardableResult
    func unbind(_ target: ParameterID) -> Bool {
        let removed = modulator?.unbind(target) ?? false
        resolveEffectiveGlow()
        return removed
    }

    /// MOD-006: replaces the threshold triggers (validated; each starts armed). Effective from the next frame.
    func setTriggers(_ bindings: [ThresholdTriggerBinding]) throws(ThresholdTriggerError) {
        try triggerBank.set(bindings)
    }

    /// MOD-007: replaces the scene's oscillators by position (validated); their shared origin restarts at the next frame.
    func setLFOs(_ oscillators: [LFO?]) throws(LFOError) {
        try lfoBank.set(oscillators)
    }

    /// MOD-007: the live oscillators by position.
    var lfos: [LFO?] { lfoBank.oscillators }

    /// ANL-013: records the warning and reports a change (tests call it to stand in for the bus).
    func setPhaseInverted(_ value: Bool) {
        guard value != phaseInverted else { return }
        phaseInverted = value
        onPhaseWarningChange?(value)
    }

    /// MOD-006: the live threshold triggers in order.
    var triggers: [ThresholdTriggerBinding] { triggerBank.bindings }

    /// Advances the bindings and the threshold triggers with one frame's features at the frame's display time and
    /// applies the result. Does nothing without bindings or triggers. Called by `frame(_:)`; tests call it directly.
    func applyModulation(bands: UnsafeBufferPointer<Float>, kick: Float? = nil, centroid: Float? = nil,
                         loudness: Float? = nil, midTransient: Float? = nil, highTransient: Float? = nil,
                         rolloff: Float? = nil, flatness: Float? = nil, correlation: Float? = nil,
                         sectionChange: Float? = nil, timeNanoseconds: UInt64) {
        let bound: Bool = modulator?.hasBindings ?? false
        guard bound || triggerBank.hasTriggers else { return }
        var lfos = UnsafeBufferPointer<Double>(start: nil, count: 0)
        if lfoBank.hasOscillators {   // MOD-007: at most 8 values, no allocation; ≤ 3 Hz under Reduce flashing (ACC-012)
            let cap: Double = reduceFlashing ? LFOBank.reduceFlashingMaximumRateHz : .infinity
            let tempo: Double? = lfoBank.hasSyncedOscillators ? lfoTempoBPM?() : nil   // MOD-009
            lfoBank.values(atNanoseconds: timeNanoseconds, tempoBPM: tempo, maximumRateHz: cap, into: lfoValues)
            lfos = UnsafeBufferPointer(lfoValues)
        }
        bandEnvelopeBank.advance(bands: bands, timeNanoseconds: timeNanoseconds)   // MOD-015: held while nothing is bound
        let frame = AudioFeatureFrame(bands: bands, kick: kick, centroid: centroid, loudness: loudness, midTransient: midTransient,
                                      highTransient: highTransient, rolloff: rolloff, flatness: flatness,
                                      correlation: correlation, sectionChange: sectionChange, lfos: lfos,
                                      bandEnvelopes: bandEnvelopeBank.values)
        if triggerBank.hasTriggers {   // MOD-006: one step per trigger, no allocation
            triggerBank.advance(frame: frame, timeNanoseconds: timeNanoseconds) { (action: ThresholdTriggerAction) -> Void in
                onTrigger?(action)
            }
        }
        guard bound, let modulator else { return }
        modulator.advance(frame: frame, timeNanoseconds: timeNanoseconds)
        resolveEffectiveGlow()
    }

    /// VIS-009-R4: hands the particle orbit this frame's base radius and bass ("mapped bass"). Unbound, the base is the
    /// Radius setting and the bass the ANL-007 kick envelope; with a binding on `visual.particleOrbit.radius` the base
    /// is the modulator's value and the bass is off. Called by `frame(_:)` after `applyModulation`; tests call it
    /// directly. No allocation.
    func driveParticleOrbit(kick: Float) {
        guard let orbit = generator as? ParticleOrbitGenerator else { return }
        let resolved: (base: Double, bass: Double) = ParticleOrbitRadiusDrive.resolve(manual: orbit.configuration.radius,
                                                                                      kick: Double(kick), modulator: modulator)
        orbit.drive(base: resolved.base, bass: resolved.bass)
    }

    /// "bound, manual 0.50, effective 0.73" (MOD-002-R12; the Debug readout and tests).
    var glowModulationReadout: String {
        let state = glowIntensityIsBound ? "bound" : "unbound"
        return "\(state), manual \(String(format: "%.2f", Double(glow.intensity))), effective \(String(format: "%.2f", Double(effectiveGlow.intensity)))"
    }

    /// The bloom's current parameters (nil without a bloom).
    var bloomParameters: BloomParameters? { bloom?.parameters }

    /// The luminance model Reduce flashing applies to the generator's output.
    var downstreamLuminance: (any FrameLuminanceTransfer)? { generator.downstreamLuminance }

    /// The accessibility value naming the glow state.
    static func glowDescription(enabled: Bool, unavailable: Bool) -> String {
        guard enabled else { return "Glow off" }
        return unavailable ? "Glow unavailable" : "Glow on"
    }

    /// The visual's accessibility value: the glow state, preceded by the orientation for the linear
    /// spectrum ("Vertical, Glow off"; VIS-002-R13) and the window for the oscilloscope ("20 ms, Glow
    /// off"; VIS-003-R13).
    static func accessibilityValue(style: NativeSpectrumStyle, glowEnabled: Bool, glowUnavailable: Bool) -> String {
        let glow = glowDescription(enabled: glowEnabled, unavailable: glowUnavailable)
        switch style {
        case .circular: return glow
        case let .linear(orientation, _): return "\(orientation.title), \(glow)"
        case let .oscilloscope(_, window): return "\(window) ms, \(glow)"
        case let .lissajous(mode, persistence): return "\(mode.title), Persistence \(persistence ? "on" : "off"), \(glow)"   // VIS-004-R14
        case let .radialWaveform(ring, amplitude): return "\(ring.title) ring, \(amplitude.title) amplitude, \(glow)"   // VIS-005-R11
        case let .beatRings(life): return "\(life.title) ring life, \(glow)"   // VIS-006-R11
        case let .mandala(symmetry, mirror, petal):   // VIS-007-R11
            return "\(symmetry)-fold, Mirror \(mirror ? "on" : "off"), \(petal.title), \(glow)"
        case let .particleFountain(gravity): return "\(gravity.title) gravity, \(glow)"   // VIS-008-R12
        case let .particleOrbit(radius): return "\(radius.title) radius, \(glow)"   // VIS-009-R12
        }
    }

    /// The chain's textures could not be created: continue without the glow (FX-001-R13).
    private func dropGlow() {
        chain = nil
        glowUnavailable = true
        applyGlow()
    }

    isolated deinit {
        displayLink?.invalidate()
        analyzer.stop()
        observers.forEach(NotificationCenter.default.removeObserver)
        bands.deinitialize(count: SpectrumBarCount.maximum)
        bands.deallocate()
        samples.deinitialize(count: WaveformFrameBuffer.capacity)
        samples.deallocate()
        lfoValues.deallocate()   // MOD-007
    }

    /// SHOW-011 (research SHOW-011-D3): while this visual is shown its analyzer is the analysis tap's
    /// only reader, so the tap tempo reads this subscription on its pipeline.
    private(set) lazy var tempoReader: TempoSubscriptionReader? = (try? analyzer.subscribe()).map {
        TempoSubscriptionReader(subscription: $0, sampleRate: analyzer.sampleRate)
    }

    /// True while the frame loop runs (resumed and not suspended).
    var isRunning: Bool { displayLink != nil }

    // MARK: - Pause (FR-046) and presentation (PERF-011)

    func pause() {
        paused = true
        updateLoop()
    }

    func resume() {
        paused = false
        updateLoop()
    }

    var presentationResources: [any PresentationBoundResource] { [self] }
    var presentationResourceName: String { "Native spectrum frame loop and analysis" }

    func suspendForPresentationLoss() {
        guard !isSuspended else { return }
        isSuspended = true
        updateLoop()
    }

    func resumeForPresentation() {
        guard isSuspended else { return }
        isSuspended = false
        layoutDrawable()
        updateLoop()
    }

    private func updateLoop() {
        let run = !paused && !isSuspended
        if run, displayLink == nil {
            generator.restartLoop()
            discardBeatEvents()   // VIS-006: no burst of rings for beats heard while stopped
            smoother.reset()   // ANL-003-R5: no ramp from the picture before the pause
            lastLinkTimestamp = nil
            kickEnvelope = 0   // ANL-007: no kick carried over a pause
            centroid = 0       // ANL-010: the analysis session restarts, so its centroid does too
            loudness = 0       // ANL-014: and its loudness envelope
            midTransient = 0   // ANL-008: and its mid transient
            highTransient = 0  // ANL-009: and its high transient
            rolloff = 0        // ANL-011: and its rolloff
            flatness = 0       // ANL-012: and its flatness
            correlation = 0    // ANL-013: and its stereo correlation
            sectionChange = 0  // ANL-015: and its section-change envelope
            setPhaseInverted(false)   // ANL-013: and its warning
            startEffectQuality()   // PERF-003: the floor at once, no fade
            if let waveform { analyzer.start(reader: waveform) }   // VIS-003: the tap through the pass-through wrapper
            let link = CADisplayLink(target: NativeSpectrumLinkProxy(self), selector: #selector(NativeSpectrumLinkProxy.fire(_:)))
            link.preferredFrameRateRange = quality.frameRateRange
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else if !run, let link = displayLink {
            link.invalidate()
            displayLink = nil
            analyzer.stop()
            setPhaseInverted(false)   // ANL-013: no warning while nothing is analysed
            meter.reset()
            cancelCapture()   // REC-001-R14: no frame comes while the loop is stopped
        }
    }

    // MARK: - Frame capture (REC-001)

    func captureFrame(_ handler: @escaping @MainActor (CapturedPixels?) -> Void) {
        pendingCapture?(nil)
        pendingCapture = handler
        view.metalLayer.framebufferOnly = false   // the next drawables can be read
    }

    func cancelCapture() {
        let handler = pendingCapture
        pendingCapture = nil
        view.metalLayer.framebufferOnly = videoRecording == nil   // REC-003 keeps the drawables readable
        handler?(nil)
    }

    /// Encodes the read-back of the drawn `target` when a capture waits and the drawable is readable.
    private func encodeCaptureIfPending(_ target: MTLTexture, commands: MTLCommandBuffer) {
        guard let handler = pendingCapture, !target.isFramebufferOnly else { return }
        pendingCapture = nil
        view.metalLayer.framebufferOnly = videoRecording == nil   // REC-003 keeps the drawables readable
        let width = target.width, height = target.height, rowBytes = width * 4
        guard target.pixelFormat == .bgra8Unorm_srgb || target.pixelFormat == .bgra8Unorm,
              let buffer = device.makeBuffer(length: rowBytes * height, options: .storageModeShared),
              let blit = commands.makeBlitCommandEncoder() else {
            handler(nil)
            return
        }
        blit.label = "REC-001 native capture"
        blit.copy(from: target, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: width, height: height, depth: 1), to: buffer, destinationOffset: 0,
                  destinationBytesPerRow: rowBytes, destinationBytesPerImage: rowBytes * height)
        blit.endEncoding()
        // Read only after the GPU finished; nothing else holds the buffer.
        nonisolated(unsafe) let readBack = buffer
        commands.addCompletedHandler { (completed: MTLCommandBuffer) in
            var pixels: CapturedPixels?
            if completed.status == .completed {
                let bytes = readBack.contents().bindMemory(to: UInt8.self, capacity: rowBytes * height)
                pixels = CapturedPixels(width: width, height: height,
                                        layout: .sRGBBGRA8TopDown(Array(UnsafeBufferPointer(start: bytes, count: rowBytes * height))))
            }
            Task { @MainActor in handler(pixels) }
        }
    }

    /// REC-003: a blit of the readable drawable's top-left region into the recording's texture.
    private static func encodeRecordingCopy(from target: MTLTexture, into texture: MTLTexture, commands: MTLCommandBuffer) -> Bool {
        guard !target.isFramebufferOnly, target.pixelFormat == texture.pixelFormat,
              texture.width <= target.width, texture.height <= target.height,
              let blit = commands.makeBlitCommandEncoder() else { return false }
        blit.label = "REC-003 native recording copy"
        blit.copy(from: target, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1), to: texture,
                  destinationSlice: 0, destinationLevel: 0, destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        return true
    }

    // MARK: - Frames

    /// One frame's context: the effective Reduce flashing and the profile's envelope (ACC-012-R5). The
    /// generators' limiter applies `flashConfiguration`; tests read the same value.
    func frameContext(timeNanoseconds: UInt64, frameDuration: Double) -> VisualFrameContext {
        VisualFrameContext(timeNanoseconds: timeNanoseconds, frameDuration: frameDuration, reduceFlashing: reduceFlashing,
                           flashLimits: safetyClamp.flashLimitsOverride)
    }

    fileprivate func frame(_ link: CADisplayLink) {
        let layer = view.metalLayer
        guard view.window != nil, layer.drawableSize.width >= 1, layer.drawableSize.height >= 1 else { return }
        let timer: FrameStageTimer? = stageTimer   // PERF-001
        timer?.beginFrame()
        defer { timer?.endFrame() }
        if let timer { gpuTimes.drain(into: timer) }
        timer?.begin(.audio)
        if let info = analyzer.output.readLatest(into: bands, capacity: SpectrumBarCount.maximum) {
            bandCount = info.count
            bandSession = info.session
            kickEnvelope = info.kickEnvelope
            centroid = info.centroid
            loudness = info.loudness
            midTransient = info.midTransient
            highTransient = info.highTransient
            rolloff = info.rolloff
            flatness = info.flatness
            correlation = info.correlation
            sectionChange = info.sectionChange
            setPhaseInverted(info.phaseInverted)
        }
        // ANL-003: the real interval since the previous frame (the first frame after a start snaps).
        let interval: Double = lastLinkTimestamp.map { (previous: CFTimeInterval) -> Double in link.timestamp - previous } ?? 0
        lastLinkTimestamp = link.timestamp
        let smoothedBands = smoother.update(target: bands, count: bandCount, frameInterval: interval, generation: bandSession)
        timer?.end(.audio)   // the drawable wait is not audio work; the modulation below is (accumulated)
        guard let drawable = layer.nextDrawable(), let commands = queue.makeCommandBuffer() else { return }
        timer?.begin(.audio)
        let context: VisualFrameContext = frameContext(timeNanoseconds: UInt64(max(link.targetTimestamp, 0) * 1e9),
                                                       frameDuration: link.targetTimestamp - link.timestamp)
        let bandInput = UnsafeBufferPointer(start: bands, count: bandCount)
        applyModulation(bands: bandInput, kick: kickEnvelope, centroid: centroid, loudness: loudness, midTransient: midTransient,
                        highTransient: highTransient, rolloff: rolloff, flatness: flatness, correlation: correlation,
                        sectionChange: sectionChange, timeNanoseconds: context.timeNanoseconds)   // MOD-002; no-op without bindings
        driveParticleOrbit(kick: kickEnvelope)   // VIS-009: after the modulation step; nothing for another visual
        stepEffectQuality(time: link.timestamp)   // PERF-003: arithmetic; the glow changes only when the level or fade moves
        drainBeatEvents(context: context)   // VIS-006: nothing unless beat rings are shown
        // VIS-003: the oscilloscope draws the newest sample history (kept when nothing new arrived).
        let input: UnsafeBufferPointer<Float>
        if style.drawsMonoHistory {   // VIS-003, VIS-005
            _ = waveform?.output.readLatest(into: samples, capacity: WaveformFrameBuffer.capacity)
            input = UnsafeBufferPointer(start: samples, count: WaveformFrameBuffer.capacity)
        } else if case .lissajous = style {   // VIS-004: the newest stereo history (interleaved)
            _ = waveform?.stereoOutput.readLatest(into: samples, capacity: WaveformFrameBuffer.capacity)
            input = UnsafeBufferPointer(start: samples, count: WaveformFrameBuffer.capacity)
        } else {
            input = smoothedBands   // ANL-003: the spectra draw the smoothed bands
        }
        timer?.end(.audio)
        timer?.begin(.render)
        let target = drawable.texture
        var drawn = false
        if let chain, glowActive {
            do {
                try chain.prepare(width: target.width, height: target.height)   // creates textures only on a size change
                drawn = chain.encode(output: target, commandBuffer: commands) { image in
                    generator.encode(into: image, commandBuffer: commands, bands: input, context: context)
                }
            } catch {
                dropGlow()
            }
        }
        if !drawn && !glowActive {
            drawn = generator.encode(into: target, commandBuffer: commands, bands: input, context: context)
        }
        timer?.end(.render)
        guard drawn else { return }
        encodeCaptureIfPending(target, commands: commands)   // REC-001; nothing without a request
        if videoRecording != nil { timer?.begin(.encode) }
        // REC-003: the drawn drawable (glow included) copied into the recording's pixel buffer.
        videoRecording?.record(commandBuffer: commands, presentationNanoseconds: context.timeNanoseconds,
                               drawable: target) { (texture: MTLTexture) -> Bool in
            Self.encodeRecordingCopy(from: target, into: texture, commands: commands)
        }
        timer?.end(.encode)
        timer?.begin(.present)
        frameDrops?.track(drawable, link: link)   // PERF-007: before present, so the handler is in place
        commands.present(drawable)
        commands.commit()
        timer?.end(.present)
        if timer != nil { gpuTimes.track(commands) }
        presentedFrameCount += 1
        if meter.record(presentedAt: link.timestamp) { metrics = meter.metrics }
    }

    private func layoutDrawable() {
        guard !isSuspended else { return }
        let displayScale = view.traitCollection.displayScale > 0 ? view.traitCollection.displayScale : 2
        let scale = displayScale * quality.renderScale
        view.contentScaleFactor = scale
        let size = CGSize(width: (view.bounds.width * scale).rounded(), height: (view.bounds.height * scale).rounded())
        if size.width >= 1, size.height >= 1, size != view.metalLayer.drawableSize {
            view.metalLayer.drawableSize = size
        }
    }

    /// FR-049, PERF-003-R7: re-reads the thermal state and Low Power Mode (or their overrides) and applies the
    /// governor's settings when they changed.
    func refreshQuality() {
        readEffectInputs()
        let quality: QualitySettings = governedQuality
        guard quality != self.quality else { return }
        self.quality = quality
        displayLink?.preferredFrameRateRange = quality.frameRateRange
        layoutDrawable()
    }

    /// FR-049: frame-rate cap and render scale follow the thermal state and Low Power Mode.
    private func observeFrameRatePressure() {
        let center = NotificationCenter.default
        for name in QualityGovernor.changeNotifications {   // PERF-008: the power profile too
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshQuality() }
            })
        }
    }
}

/// The CAMetalLayer-backed view; one accessibility element (VIS-001-R18, VIS-002-R13). The host sets
/// its label, identifier and value for the shown visual.
final class NativeSpectrumLayerView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }
    var metalLayer: CAMetalLayer { layer as! CAMetalLayer }
    var onLayout: (() -> Void)?

    init(device: MTLDevice) {
        super.init(frame: .zero)
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm_srgb
        metalLayer.framebufferOnly = true
        metalLayer.isOpaque = true
        isOpaque = true
        backgroundColor = .black
        isUserInteractionEnabled = false
        isAccessibilityElement = true
        accessibilityLabel = "Circular Spectrum visualization"
        accessibilityTraits = .image
        accessibilityIdentifier = "circularSpectrum"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

/// Breaks the CADisplayLink → target retain cycle.
private final class NativeSpectrumLinkProxy: NSObject {
    weak var host: NativeSpectrumHost?
    init(_ host: NativeSpectrumHost) { self.host = host }
    @MainActor @objc func fire(_ link: CADisplayLink) { host?.frame(link) }
}

/// MOD-002 (research MOD-002-D6): the bloom's luminance model behind a class reference, so the frame
/// loop can follow a modulated intensity without boxing a new existential every frame. Mutated and
/// read only on the main thread (the frame loop encodes there), hence `@unchecked Sendable`.
final class ModulatedGlowLuminance: FrameLuminanceTransfer, @unchecked Sendable {
    var model = BloomLuminanceModel(parameters: BloomParameters())

    func outputLuminance(ofFlatColor color: LinearColor) -> Double { model.outputLuminance(ofFlatColor: color) }
    func outputRedness(ofFlatColor color: LinearColor) -> Double { model.outputRedness(ofFlatColor: color) }
    func spreadRadius(width: Int, height: Int) -> Double { model.spreadRadius(width: width, height: height) }
}

/// Which native spectrum the host draws (VIS-002-D5).
enum NativeSpectrumStyle: Equatable, Sendable {
    case circular
    case linear(LinearSpectrumOrientation, spacing: Double)
    /// VIS-003: the waveform oscilloscope.
    case oscilloscope(line: OscilloscopeLine, windowMilliseconds: Int)
    /// VIS-004: the Lissajous scope.
    case lissajous(mode: LissajousMode, persistence: Bool)
    /// VIS-005: the radial waveform.
    case radialWaveform(ring: RadialWaveformRing, amplitude: RadialWaveformAmplitude)
    /// VIS-006: beat pulse rings.
    case beatRings(life: BeatRingLife)
    /// VIS-007: the mandala.
    case mandala(symmetry: Int, mirror: Bool, petal: MandalaPetalStyle)
    /// VIS-008: the particle fountain.
    case particleFountain(gravity: ParticleGravity)
    /// VIS-009: the particle orbit.
    case particleOrbit(radius: ParticleOrbitRadius)

    /// VIS-006, VIS-008, VIS-009: the host drains its analysis bus subscription into the generator.
    var drainsAnalysisEvents: Bool {
        switch self {
        case .beatRings, .particleFountain, .particleOrbit: true
        default: false
        }
    }

    /// The oscilloscope and the radial waveform draw the mono sample history instead of the bands.
    var drawsMonoHistory: Bool {
        switch self {
        case .oscilloscope, .radialWaveform: true
        default: false
        }
    }

    var title: String {
        switch self {
        case .circular: VisualChoice.circularSpectrum.title
        case .linear: VisualChoice.linearSpectrum.title
        case .oscilloscope: VisualChoice.oscilloscope.title
        case .lissajous: VisualChoice.lissajous.title
        case .radialWaveform: VisualChoice.radialWaveform.title
        case .beatRings: VisualChoice.beatRings.title
        case .mandala: VisualChoice.mandala.title
        case .particleFountain: VisualChoice.particleFountain.title
        case .particleOrbit: VisualChoice.particleOrbit.title
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .circular: "circularSpectrum"
        case .linear: "linearSpectrum"
        case .oscilloscope: "oscilloscope"
        case .lissajous: "lissajous"
        case .radialWaveform: "radialWaveform"
        case .beatRings: "beatRings"
        case .mandala: "mandala"
        case .particleFountain: "particleFountain"
        case .particleOrbit: "particleOrbit"
        }
    }
}

extension LinearSpectrumOrientation {
    /// Settings and VoiceOver.
    var title: String {
        switch self {
        case .vertical: "Vertical"
        case .horizontal: "Horizontal"
        }
    }
}
