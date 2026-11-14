// TextVisualHost.swift — the Text visual on screen (MED-009-R1, R9, R11, R13, R18; plan, Complexity
// Tracking).
//
// * One CMP-001 `Compositor` with a CMP-002 `LayerStack`: the circular spectrum (`SpectrumLayerSource`,
//   transparent background, over the compositor's black) at index 0 and the text (`TextLayerSource`,
//   transparent fallback) at index 1, composited into a `CAMetalLayer` by one `CADisplayLink` on the
//   main run loop. The composite flash guard applies Reduce flashing; the text itself is static.
// * The frame loop runs only while resumed (the coordinator resumes it only while Text is shown on
//   the visualizer and not paused), not suspended for presentation loss (PERF-011), in the
//   foreground and with the scene connected — the same rules as the Photo visual. OUT-001: scene
//   events of an external display are filtered out; the view is placed through `VisualSlotHost`.
// * `spec` sets the text layer's spec; the layer draws it off the frame loop (MED-009-R8).
//   `textState` mirrors the layer's state (DEBUG diagnostics read its checksum).
// * Per frame this file allocates nothing: the band scratch is preallocated and the audio context is
//   a view of it. This repeats PhotoVisualHost's loop on purpose (plan, Complexity Tracking).
import AudioCore
import Compositor
import FrameTiming
import Metal
import PerformanceControlAnalysis
import PresentationLifecycle
import QuartzCore
import Rendering
import SpectrumLayers
import TextLayer
import UIKit
import VisualBandFeed
import VisualGenerators

@MainActor
final class TextVisualHost: PresentationBoundResource, CompositorVisualHost {
    let view: NativeSpectrumLayerView
    let text: TextLayerSource
    private let spectrum: SpectrumLayerSource
    let compositor: Compositor   // internal for REC-001's FrameCaptureSource
    let queue: MTLCommandQueue   // XFADE: the freeze is encoded after this host's frames
    private let analyzer: LiveBandAnalyzer
    private let reader: (any NormalizedPCMReader)?
    private let bands: UnsafeMutablePointer<Float>
    private var bandCount = 0
    private var displayLink: CADisplayLink?
    private var paused = true
    private(set) var isSuspended = false
    private var inBackground = false
    private var sceneDisconnected = false
    private var meter = FrameRateMeter()
    /// PERF-001: the stage timer while the performance overlay is shown (nil: no timing work), and the
    /// frames' command buffers until their GPU times are known.
    var stageTimer: FrameStageTimer? {
        didSet { attachStageTimer(stageTimer, compositor: compositor, gpuTimes: gpuTimes) }
    }
    private let gpuTimes = MetalGPUFrameTimes()
    private var quality = QualityGovernor.current()
    private var observers: [NSObjectProtocol] = []

    /// Frame rate and frame time for the FR-048 overlay.
    private(set) var metrics = RenderMetrics.zero
    /// FR-072: the app's Reduce flashing setting.
    var reduceFlashing = false
    /// FX-003: the colour grade of the compositor's output passes (neutral: bypass).
    var colorGrade: ColorGrade {
        get { compositor.colorGrade }
        set { compositor.colorGrade = newValue }
    }
    /// REC-003: the attached video recording, fed with each composited frame (nil when not recording).
    var videoRecording: VideoRecordingTap?
    /// The text layer's state; `onTextStateChange` reports every change.
    private(set) var textState: TextLayerState = .empty
    var onTextStateChange: ((TextLayerState) -> Void)?
    /// Presented frames (tests, diagnostics).
    private(set) var framesComposited = 0
    /// PERF-014: the compositor's render health record, reported when it changes (once per tick).
    var onRenderHealthChange: ((RenderHealth) -> Void)?
    private var reportedHealthRevision = 0
    /// PERF-014: frame ticks of this visual (DEBUG readout, tests).
    var renderTicks: UInt64 { compositor.frameTicks }

    /// Frames that showed the text (diagnostics, UI tests).
    var framesShown: Int { text.framesShown }

    /// What the text layer draws (MED-009-R17: may change at any time).
    var spec: TextOverlaySpec {
        get { text.spec }
        set {
            text.spec = newValue
            updateAccessibility()
        }
    }

    var barCount: SpectrumBarCount {
        get { spectrum.generator.barCount }
        set {
            guard newValue != spectrum.generator.barCount else { return }
            spectrum.generator.barCount = newValue
            analyzer.setBarCount(newValue)
            bandCount = 0
        }
    }

    /// Throws `VisualGeneratorError`, `LayerStackError` or `CompositorError` when there is no Metal
    /// device or a pipeline cannot be built; the caller falls back to projectM with a notice.
    static func make(device: MTLDevice?, reader: (any NormalizedPCMReader)?, barCount: SpectrumBarCount) throws -> TextVisualHost {
        guard let device, let queue = device.makeCommandQueue() else { throw VisualGeneratorError.noDevice }
        let transparent = LinearColor(red: 0, green: 0, blue: 0, alpha: 0)
        let generator = try CircularSpectrumGenerator(device: device, pixelFormat: LayerPictureDescriptor.metalPixelFormat,
                                                      configuration: CircularSpectrumConfiguration(barCount: barCount, background: transparent))
        let spectrum = try SpectrumLayerSource(device: device, generator: generator, name: "spectrum")
        let text = TextLayerSource(device: device)
        // CMP-002: the stack, bottom first: the circular spectrum, then the text (one per stack).
        var stack = LayerStack()
        try stack.add(LayerDescriptor(kind: .circularSpectrum))
        try stack.add(LayerDescriptor(kind: .text))
        let compositor = try Compositor(device: device, texturePool: SharedTexturePool.pool(for: device))   // PERF-004
        try compositor.apply(stack) { (entry: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in
            switch entry.descriptor.kind {
            case .text: return text
            case .circularSpectrum: return spectrum
            default: throw .notReady
            }
        }
        let analyzer = try LiveBandAnalyzer(barCount: barCount)
        return TextVisualHost(device: device, queue: queue, text: text, spectrum: spectrum, compositor: compositor,
                               analyzer: analyzer, reader: reader)
    }

    private init(device: MTLDevice, queue: MTLCommandQueue, text: TextLayerSource, spectrum: SpectrumLayerSource,
                 compositor: Compositor, analyzer: LiveBandAnalyzer, reader: (any NormalizedPCMReader)?) {
        self.queue = queue
        self.text = text
        self.spectrum = spectrum
        self.compositor = compositor
        self.analyzer = analyzer
        self.reader = reader
        bands = .allocate(capacity: SpectrumBarCount.maximum)
        bands.initialize(repeating: 0, count: SpectrumBarCount.maximum)
        view = NativeSpectrumLayerView(device: device)
        view.onLayout = { [weak self] in self?.layoutDrawable() }
        text.onStateChange = { [weak self] (state: TextLayerState) in self?.textStateChanged(state) }
        observeSystem()
        updateAccessibility()
    }

    isolated deinit {
        displayLink?.invalidate()
        analyzer.stop()
        observers.forEach(NotificationCenter.default.removeObserver)
        bands.deinitialize(count: SpectrumBarCount.maximum)
        bands.deallocate()
    }

    /// SHOW-011: while this visual is shown its analyzer is the analysis tap's only reader.
    private(set) lazy var tempoReader: TempoSubscriptionReader? = (try? analyzer.subscribe()).map {
        TempoSubscriptionReader(subscription: $0, sampleRate: analyzer.sampleRate)
    }

    /// True while the frame loop runs.
    var isRunning: Bool { displayLink != nil }

    private func textStateChanged(_ state: TextLayerState) {
        guard state != textState else { return }
        textState = state
        onTextStateChange?(state)
    }

    private func updateAccessibility() {
        view.accessibilityLabel = "Text visualization"
        view.accessibilityIdentifier = "textVisual"
        view.accessibilityValue = TextOverlayCoordinator.accessibilityValue(text.spec)
    }

    // MARK: - Pause (FR-046), presentation (PERF-011), background and scene

    func pause() {
        paused = true
        updateLoop()
    }

    func resume() {
        paused = false
        updateLoop()
    }

    var presentationResources: [any PresentationBoundResource] { [self] }
    var presentationResourceName: String { "Text visual frame loop and analysis" }

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

    func appEnteredBackground() {
        inBackground = true
        updateLoop()
    }

    func appWillEnterForeground() {
        inBackground = false
        updateLoop()
    }

    func sceneDidDisconnect() {
        sceneDisconnected = true
        updateLoop()
    }

    func sceneWillConnect() {
        sceneDisconnected = false
        updateLoop()
    }

    private func updateLoop() {
        let run = !paused && !isSuspended && !inBackground && !sceneDisconnected
        if run, displayLink == nil {
            compositor.resetFlashHistory()   // a new scene for the flash guard (FX-019-R11)
            compositor.resetRenderHealth()   // PERF-014-R6: a fresh retry budget whenever the loop starts
            if let reader { analyzer.start(reader: reader) }
            let link = CADisplayLink(target: TextVisualLinkProxy(self), selector: #selector(TextVisualLinkProxy.fire(_:)))
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
        let timer: FrameStageTimer? = stageTimer   // PERF-001
        timer?.beginFrame()
        defer { timer?.endFrame() }
        if let timer { gpuTimes.drain(into: timer) }
        timer?.begin(.audio)
        if let info = analyzer.output.readLatest(into: bands, capacity: SpectrumBarCount.maximum) {
            bandCount = info.count
        }
        timer?.end(.audio)
        guard let drawable = layer.nextDrawable(), let commands = queue.makeCommandBuffer() else { return }
        let audio = LayerAudioContext(frame: nil, bands: UnsafeBufferPointer(start: bands, count: bandCount),
                                      events: UnsafeBufferPointer(start: nil, count: 0), droppedEvents: 0)
        let compositeStart: UInt64 = timer?.now() ?? 0
        guard compositor.composite(into: drawable.texture, commandBuffer: commands,
                                   presentationTimeNanoseconds: UInt64(max(link.targetTimestamp, 0) * 1e9),
                                   contentScale: Double(view.contentScaleFactor), reduceFlashing: reduceFlashing,
                                   audio: audio) else {
            reportRenderHealth()
            return
        }
        timer?.recordComposite(of: compositor, start: compositeStart)
        reportRenderHealth()
        if videoRecording != nil { timer?.begin(.encode) }
        // REC-003: the shown frame once more into the recording's pixel buffer (nothing without a recording).
        videoRecording?.record(commandBuffer: commands, presentationNanoseconds: UInt64(max(link.targetTimestamp, 0) * 1e9),
                               drawable: drawable.texture) { (texture: MTLTexture) -> Bool in
            compositor.encodeOutput(into: texture, commandBuffer: commands)
        }
        timer?.end(.encode)
        timer?.begin(.present)
        commands.present(drawable)
        commands.commit()
        timer?.end(.present)
        if timer != nil { gpuTimes.track(commands) }
        framesComposited &+= 1
        if meter.record(presentedAt: link.timestamp) { metrics = meter.metrics }
    }

    /// PERF-014: reports the compositor's health record when its revision changed (no allocation).
    private func reportRenderHealth() {
        let health = compositor.health
        guard health.revision != reportedHealthRevision else { return }
        reportedHealthRevision = health.revision
        onRenderHealthChange?(health)
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

    /// FR-049 frame-rate pressure, background and scene connection.
    private func observeSystem() {
        let center = NotificationCenter.default
        let observed: [(Notification.Name, @MainActor (TextVisualHost, Notification) -> Void)] = [
            (UIApplication.didEnterBackgroundNotification, { host, _ in host.appEnteredBackground() }),
            (UIApplication.willEnterForegroundNotification, { host, _ in host.appWillEnterForeground() }),
            // OUT-001-R9: an external display scene's connect and disconnect never stop or start this visual.
            (UIScene.didDisconnectNotification, { host, note in if ExternalDisplayScenes.affectsDeviceVisuals(note) { host.sceneDidDisconnect() } }),
            (UIScene.willConnectNotification, { host, note in if ExternalDisplayScenes.affectsDeviceVisuals(note) { host.sceneWillConnect() } }),
            (ProcessInfo.thermalStateDidChangeNotification, { host, _ in host.qualityChanged() }),
            (Notification.Name.NSProcessInfoPowerStateDidChange, { host, _ in host.qualityChanged() }),
        ]
        for (name, action) in observed {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] (note: Notification) in
                // Delivered on the main queue and used synchronously there, never sent anywhere else.
                nonisolated(unsafe) let note = note
                MainActor.assumeIsolated {
                    guard let self else { return }
                    action(self, note)
                }
            })
        }
    }

    private func qualityChanged() {
        let quality = QualityGovernor.current()
        guard quality != self.quality else { return }
        self.quality = quality
        displayLink?.preferredFrameRateRange = quality.frameRateRange
        layoutDrawable()
    }
}

/// Breaks the CADisplayLink → target retain cycle.
private final class TextVisualLinkProxy: NSObject {
    weak var host: TextVisualHost?
    init(_ host: TextVisualHost) { self.host = host }
    @MainActor @objc func fire(_ link: CADisplayLink) { host?.frame(link) }
}
