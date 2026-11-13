// CircularSpectrumHost.swift — the circular spectrum on screen (VIS-001-R12 to R16, R18; research
// VIS-001-D8; ADR-0009).
//
// * A `CAMetalLayer` view (`bgra8Unorm_srgb`, opaque). Its drawable size follows the view's bounds
//   × display scale × QualityGovernor's render scale at every layout, so rotation and iPad sizes need
//   nothing else: the generator lays out for whatever size it gets (VIS-001-R5).
// * A `CADisplayLink` on the main run loop at QualityGovernor's frame-rate range (FR-049, as
//   ANGLERenderer). Each frame takes the newest band vector from `LiveBandAnalyzer` without waiting,
//   encodes it with `CircularSpectrumGenerator` into the next drawable and presents it.
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
import AudioCore
import Metal
import PerformanceControlAnalysis
import PresentationLifecycle
import QuartzCore
import Rendering
import UIKit
import VisualBandFeed
import VisualEffects
import VisualGenerators

@MainActor
final class CircularSpectrumHost: PresentationBoundResource {
    let view: CircularSpectrumLayerView
    private let generator: CircularSpectrumGenerator
    private let queue: MTLCommandQueue
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

    /// The bloom runs (available and not pass-through).
    var glowActive: Bool { chain != nil && !glow.isPassThrough }

    var barCount: SpectrumBarCount {
        get { generator.configuration.barCount }
        set {
            guard newValue != generator.configuration.barCount else { return }
            generator.configuration.barCount = newValue
            analyzer.setBarCount(newValue)
            bandCount = 0   // the old vector does not match the new bars
        }
    }

    /// Throws `VisualGeneratorError` when there is no Metal device or the pipeline cannot be built
    /// (VIS-001-R16); the caller falls back to projectM.
    /// A glow that cannot be built does not throw: the host renders without it (FX-001-R13).
    /// `forceGlowFailure` simulates that failure (DEBUG UI tests).
    static func make(device: MTLDevice?, reader: (any NormalizedPCMReader)?, barCount: SpectrumBarCount,
                     glow: BloomParameters = BloomParameters(), forceGlowFailure: Bool = false) throws -> CircularSpectrumHost {
        guard let device, let queue = device.makeCommandQueue() else { throw VisualGeneratorError.noDevice }
        let generator = try CircularSpectrumGenerator(device: device, pixelFormat: .bgra8Unorm_srgb,
                                                      configuration: CircularSpectrumConfiguration(barCount: barCount))
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
        let host = CircularSpectrumHost(device: device, queue: queue, generator: generator, analyzer: analyzer, reader: reader,
                                        bloom: bloom, chain: chain)
        host.glow = glow
        return host
    }

    private init(device: MTLDevice, queue: MTLCommandQueue, generator: CircularSpectrumGenerator,
                 analyzer: LiveBandAnalyzer, reader: (any NormalizedPCMReader)?, bloom: BloomEffect?, chain: EffectChain?) {
        self.queue = queue
        self.generator = generator
        self.analyzer = analyzer
        self.reader = reader
        self.bloom = bloom
        self.chain = chain
        glowUnavailable = chain == nil
        bands = .allocate(capacity: SpectrumBarCount.maximum)
        bands.initialize(repeating: 0, count: SpectrumBarCount.maximum)
        view = CircularSpectrumLayerView(device: device)
        view.onLayout = { [weak self] in self?.layoutDrawable() }
        observeFrameRatePressure()
        applyGlow()
    }

    private func applyGlow() {
        bloom?.parameters = glow
        generator.downstreamLuminance = glowActive ? BloomLuminanceModel(parameters: glow) : nil
        view.accessibilityValue = Self.glowDescription(enabled: glow.enabled, unavailable: glowUnavailable)
    }

    /// The accessibility value naming the glow state.
    static func glowDescription(enabled: Bool, unavailable: Bool) -> String {
        guard enabled else { return "Glow off" }
        return unavailable ? "Glow unavailable" : "Glow on"
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
    var presentationResourceName: String { "Circular spectrum frame loop and analysis" }

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
            generator.limiter.reset()
            if let reader { analyzer.start(reader: reader) }
            let link = CADisplayLink(target: CircularSpectrumLinkProxy(self), selector: #selector(CircularSpectrumLinkProxy.fire(_:)))
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

/// The CAMetalLayer-backed view; one accessibility element (VIS-001-R18).
final class CircularSpectrumLayerView: UIView {
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
private final class CircularSpectrumLinkProxy: NSObject {
    weak var host: CircularSpectrumHost?
    init(_ host: CircularSpectrumHost) { self.host = host }
    @MainActor @objc func fire(_ link: CADisplayLink) { host?.frame(link) }
}
