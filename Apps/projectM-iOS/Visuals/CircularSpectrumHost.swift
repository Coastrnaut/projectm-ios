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
// * Per frame, this file's code allocates nothing: the band scratch is preallocated; Metal's command
//   buffer and drawable are the system's.
import AudioCore
import Metal
import PresentationLifecycle
import QuartzCore
import Rendering
import UIKit
import VisualBandFeed
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
    static func make(device: MTLDevice?, reader: (any NormalizedPCMReader)?, barCount: SpectrumBarCount) throws -> CircularSpectrumHost {
        guard let device, let queue = device.makeCommandQueue() else { throw VisualGeneratorError.noDevice }
        let generator = try CircularSpectrumGenerator(device: device, pixelFormat: .bgra8Unorm_srgb,
                                                      configuration: CircularSpectrumConfiguration(barCount: barCount))
        let analyzer = try LiveBandAnalyzer(barCount: barCount)
        return CircularSpectrumHost(device: device, queue: queue, generator: generator, analyzer: analyzer, reader: reader)
    }

    private init(device: MTLDevice, queue: MTLCommandQueue, generator: CircularSpectrumGenerator,
                 analyzer: LiveBandAnalyzer, reader: (any NormalizedPCMReader)?) {
        self.queue = queue
        self.generator = generator
        self.analyzer = analyzer
        self.reader = reader
        bands = .allocate(capacity: SpectrumBarCount.maximum)
        bands.initialize(repeating: 0, count: SpectrumBarCount.maximum)
        view = CircularSpectrumLayerView(device: device)
        view.onLayout = { [weak self] in self?.layoutDrawable() }
        observeFrameRatePressure()
    }

    isolated deinit {
        displayLink?.invalidate()
        analyzer.stop()
        observers.forEach(NotificationCenter.default.removeObserver)
        bands.deinitialize(count: SpectrumBarCount.maximum)
        bands.deallocate()
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
        let drawn = generator.encode(into: drawable.texture, commandBuffer: commands,
                                     bands: UnsafeBufferPointer(start: bands, count: bandCount), context: context)
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
