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
import AudioCore
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
    private let bands: UnsafeMutablePointer<Float>
    private var bandCount = 0
    private var displayLink: CADisplayLink?
    private var paused = true
    private(set) var isSuspended = false
    private var meter = FrameRateMeter()
    private var quality = QualityGovernor.current()
    private var observers: [NSObjectProtocol] = []

    /// Frame rate and frame time for the FR-048 overlay.
    private(set) var metrics = RenderMetrics.zero
    private(set) var presentedFrameCount = 0
    /// FR-072: the app's Reduce flashing setting.
    var reduceFlashing = false

    /// FX-001: the bloom and the chain that runs it; nil when the glow is unavailable.
    private let bloom: BloomEffect?
    private var chain: EffectChain?
    /// The glow could not be built on this device (FX-001-R13); the visual renders without it.
    private(set) var glowUnavailable: Bool

    /// The glow settings; applied from the next frame (no shader rebuild, FX-001-R12).
    var glow = BloomParameters() {
        didSet { applyGlow() }
    }

    /// The bloom runs (available and the effective glow not pass-through).
    var glowActive: Bool { chain != nil && !effectiveGlow.isPassThrough }

    /// MOD-002: the glow actually rendered, `glow` with any bound intensity applied.
    private(set) var effectiveGlow = BloomParameters()
    /// MOD-002: audio feature bindings over the visual catalog (nil only if the catalog failed to
    /// validate, which `VisualParameterCatalogTests` rules out in CI).
    private let modulator: AudioFeatureModulator? = (try? VisualParameterCatalog.makeRegistry()).map(AudioFeatureModulator.init(registry:))
    /// MOD-002: the luminance model the generator sees while the glow intensity is bound.
    private let glowLuminance = ModulatedGlowLuminance()

    var barCount: SpectrumBarCount {
        get { generator.barCount }
        set {
            guard newValue != generator.barCount else { return }
            generator.barCount = newValue
            analyzer.setBarCount(newValue)
            bandCount = 0   // the old vector does not match the new bars
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
        }
    }

    private init(device: MTLDevice, queue: MTLCommandQueue, style: NativeSpectrumStyle, generator: any SpectrumTextureGenerator,
                 analyzer: LiveBandAnalyzer, reader: (any NormalizedPCMReader)?, bloom: BloomEffect?, chain: EffectChain?) {
        self.device = device
        self.queue = queue
        self.style = style
        self.generator = generator
        self.analyzer = analyzer
        self.reader = reader
        self.bloom = bloom
        self.chain = chain
        glowUnavailable = chain == nil
        bands = .allocate(capacity: SpectrumBarCount.maximum)
        bands.initialize(repeating: 0, count: SpectrumBarCount.maximum)
        view = NativeSpectrumLayerView(device: device)
        view.onLayout = { [weak self] in self?.layoutDrawable() }
        observeFrameRatePressure()
        applyGlow()
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
        } else {
            let replacement = try Self.makeGenerator(device: device, style: newStyle, barCount: generator.barCount)
            generator = replacement
        }
        style = newStyle
        applyGlow()
    }

    private func applyGlow() {
        resolveEffectiveGlow()
        view.accessibilityLabel = "\(style.title) visualization"
        view.accessibilityIdentifier = style.accessibilityIdentifier
        view.accessibilityValue = Self.accessibilityValue(style: style, glowEnabled: glow.enabled, glowUnavailable: glowUnavailable)
    }

    // MARK: - Audio feature bindings (MOD-002)

    private var glowIntensityIsBound: Bool { modulator?.isBound(VisualParameterIDs.bloomIntensity) ?? false }

    /// Applies `glow` with any bound intensity to the bloom and the luminance model. Unbound, this is
    /// exactly the FX-001 path.
    private func resolveEffectiveGlow() {
        var resolved = glow
        if let modulator, glowIntensityIsBound {
            resolved.intensity = Float(modulator.value(for: VisualParameterIDs.bloomIntensity, manual: Double(glow.intensity)))
        }
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

    /// Removes a binding; the parameter returns to its manual value at once.
    @discardableResult
    func unbind(_ target: ParameterID) -> Bool {
        let removed = modulator?.unbind(target) ?? false
        resolveEffectiveGlow()
        return removed
    }

    /// Advances the bindings with one frame's bands at the frame's display time and applies the
    /// result. Does nothing without bindings. Called by `frame(_:)`; tests call it directly.
    func applyModulation(bands: UnsafeBufferPointer<Float>, timeNanoseconds: UInt64) {
        guard let modulator, modulator.hasBindings else { return }
        modulator.advance(frame: AudioFeatureFrame(bands: bands), timeNanoseconds: timeNanoseconds)
        resolveEffectiveGlow()
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
    /// spectrum ("Vertical, Glow off"; VIS-002-R13).
    static func accessibilityValue(style: NativeSpectrumStyle, glowEnabled: Bool, glowUnavailable: Bool) -> String {
        let glow = glowDescription(enabled: glowEnabled, unavailable: glowUnavailable)
        guard case let .linear(orientation, _) = style else { return glow }
        return "\(orientation.title), \(glow)"
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
            if let reader { analyzer.start(reader: reader) }
            let link = CADisplayLink(target: NativeSpectrumLinkProxy(self), selector: #selector(NativeSpectrumLinkProxy.fire(_:)))
            link.preferredFrameRateRange = quality.frameRateRange
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else if !run, let link = displayLink {
            link.invalidate()
            displayLink = nil
            analyzer.stop()
            meter.reset()
        }
    }

    // MARK: - Frames

    fileprivate func frame(_ link: CADisplayLink) {
        let layer = view.metalLayer
        guard view.window != nil, layer.drawableSize.width >= 1, layer.drawableSize.height >= 1 else { return }
        if let info = analyzer.output.readLatest(into: bands, capacity: SpectrumBarCount.maximum) {
            bandCount = info.count
        }
        guard let drawable = layer.nextDrawable(), let commands = queue.makeCommandBuffer() else { return }
        let context = VisualFrameContext(timeNanoseconds: UInt64(max(link.targetTimestamp, 0) * 1e9),
                                         frameDuration: link.targetTimestamp - link.timestamp, reduceFlashing: reduceFlashing)
        let input = UnsafeBufferPointer(start: bands, count: bandCount)
        applyModulation(bands: input, timeNanoseconds: context.timeNanoseconds)   // MOD-002; no-op without bindings
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
        guard drawn else { return }
        commands.present(drawable)
        commands.commit()
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

    /// FR-049: frame-rate cap and render scale follow the thermal state and Low Power Mode.
    private func observeFrameRatePressure() {
        let center = NotificationCenter.default
        for name in [ProcessInfo.thermalStateDidChangeNotification, Notification.Name.NSProcessInfoPowerStateDidChange] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let quality = QualityGovernor.current()
                    guard quality != self.quality else { return }
                    self.quality = quality
                    self.displayLink?.preferredFrameRateRange = quality.frameRateRange
                    self.layoutDrawable()
                }
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

    var title: String {
        switch self {
        case .circular: VisualChoice.circularSpectrum.title
        case .linear: VisualChoice.linearSpectrum.title
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .circular: "circularSpectrum"
        case .linear: "linearSpectrum"
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
