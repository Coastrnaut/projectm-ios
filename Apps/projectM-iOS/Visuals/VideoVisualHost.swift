// VideoVisualHost.swift — the Video visual on screen (MED-002-R1, R12, R13, R19; ADR for the imported
// video layer). Mirrors PhotoVisualHost (MED-001) on purpose (plan, Complexity Tracking).
//
// * One CMP-001 `Compositor` with a CMP-002 `LayerStack`: the video (`VideoLayerSource`, transparent
//   fallback, aspect fill, the track's rotation) at the bottom and the circular spectrum
//   (`SpectrumLayerSource`, transparent background) on top, composited into a `CAMetalLayer`
//   (`bgra8Unorm_srgb`) by one `CADisplayLink` on the main run loop, whose target time is the
//   presentation time the video's playback clock follows. The composite flash guard applies Reduce
//   flashing.
// * The frame loop runs only while resumed (the coordinator resumes it only while Video is shown on
//   the visualizer and not paused), not suspended for presentation loss (PERF-011), in the
//   foreground and with the scene connected. While paused the decoder fills its 3-picture queue and
//   sleeps; in the background, on scene loss or presentation loss the decoder is stopped and its
//   pictures released (`suspendDecoding`), and playback resumes at the same time (R13).
// * The video's own soundtrack is never played or analysed (R16): the spectrum reads the app's
//   analysis tap of the chosen audio source, like every other visual.
// * Per frame this file allocates nothing: the band scratch is preallocated and the audio context is
//   a view of it.
import AudioCore
import Compositor
import Metal
import PerformanceControlAnalysis
import PresentationLifecycle
import QuartzCore
import Rendering
import SpectrumLayers
import UIKit
import VideoLayer
import VisualBandFeed
import VisualGenerators

@MainActor
final class VideoVisualHost: PresentationBoundResource {
    let view: NativeSpectrumLayerView
    let video: VideoLayerSource
    private let spectrum: SpectrumLayerSource
    private let compositor: Compositor
    private let queue: MTLCommandQueue
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
    private var quality = QualityGovernor.current()
    private var observers: [NSObjectProtocol] = []

    /// Frame rate and frame time for the FR-048 overlay.
    private(set) var metrics = RenderMetrics.zero
    /// FR-072: the app's Reduce flashing setting.
    var reduceFlashing = false
    /// The video layer's state; `onVideoStateChange` reports every change.
    private(set) var videoState: VideoLayerState = .empty
    var onVideoStateChange: ((VideoLayerState) -> Void)?
    /// Presented frames (tests, diagnostics).
    private(set) var framesComposited = 0

    /// Frames that showed a video picture (diagnostics, UI tests).
    var framesShown: Int { video.framesShown }

    /// The shown picture's index on a `frameRate` timeline (diagnostics: the UI test's fixture is 30 fps).
    func shownFrameIndex(frameRate: Double = 30) -> Int? {
        video.shownPresentationNanoseconds.map { Int((Double($0) * frameRate / 1e9).rounded(.down)) }
    }

    /// What the video layer plays.
    var content: VideoLayerContent {
        get { video.content }
        set { video.content = newValue }
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

    /// The VoiceOver value of the visual (R19).
    static func accessibilityValue(_ state: VideoLayerState) -> String {
        switch state {
        case .empty: "No video"
        case .loading: "Loading"
        case .playing(let width, let height): "Video \(width) × \(height)"
        case .failed: "Couldn't play the video"
        }
    }

    /// Throws `VisualGeneratorError`, `LayerStackError` or `CompositorError` when there is no Metal
    /// device or a pipeline cannot be built; the caller falls back to projectM with a notice.
    static func make(device: MTLDevice?, reader: (any NormalizedPCMReader)?, barCount: SpectrumBarCount) throws -> VideoVisualHost {
        guard let device, let queue = device.makeCommandQueue() else { throw VisualGeneratorError.noDevice }
        let transparent = LinearColor(red: 0, green: 0, blue: 0, alpha: 0)
        let generator = try CircularSpectrumGenerator(device: device, pixelFormat: LayerPictureDescriptor.metalPixelFormat,
                                                      configuration: CircularSpectrumConfiguration(barCount: barCount, background: transparent))
        let spectrum = try SpectrumLayerSource(device: device, generator: generator, name: "spectrum")
        let video = VideoLayerSource(device: device)
        // CMP-002: the stack, bottom first: the video (one per stack), then the circular spectrum.
        var stack = LayerStack()
        try stack.add(LayerDescriptor(kind: .video))
        try stack.add(LayerDescriptor(kind: .circularSpectrum))
        let compositor = try Compositor(device: device)
        try compositor.apply(stack) { (entry: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in
            switch entry.descriptor.kind {
            case .video: return video
            case .circularSpectrum: return spectrum
            default: throw .notReady
            }
        }
        let analyzer = try LiveBandAnalyzer(barCount: barCount)
        return VideoVisualHost(device: device, queue: queue, video: video, spectrum: spectrum, compositor: compositor,
                               analyzer: analyzer, reader: reader)
    }

    private init(device: MTLDevice, queue: MTLCommandQueue, video: VideoLayerSource, spectrum: SpectrumLayerSource,
                 compositor: Compositor, analyzer: LiveBandAnalyzer, reader: (any NormalizedPCMReader)?) {
        self.queue = queue
        self.video = video
        self.spectrum = spectrum
        self.compositor = compositor
        self.analyzer = analyzer
        self.reader = reader
        bands = .allocate(capacity: SpectrumBarCount.maximum)
        bands.initialize(repeating: 0, count: SpectrumBarCount.maximum)
        view = NativeSpectrumLayerView(device: device)
        view.onLayout = { [weak self] in self?.layoutDrawable() }
        video.onStateChange = { [weak self] (state: VideoLayerState) in self?.videoStateChanged(state) }
        observeSystem()
        updateAccessibility()
    }

    isolated deinit {
        displayLink?.invalidate()
        analyzer.stop()
        video.content = .none   // stops the decode thread
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

    private func videoStateChanged(_ state: VideoLayerState) {
        guard state != videoState else { return }
        videoState = state
        updateAccessibility()
        onVideoStateChange?(state)
    }

    private func updateAccessibility() {
        view.accessibilityLabel = "Video visualization"
        view.accessibilityIdentifier = "videoVisual"
        view.accessibilityValue = Self.accessibilityValue(videoState)
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
    var presentationResourceName: String { "Video visual frame loop, decoder and analysis" }

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
        // R13: no decoding while the app cannot show the video; a plain pause keeps the decoder idle.
        if isSuspended || inBackground || sceneDisconnected { video.suspendDecoding() } else { video.resumeDecoding() }
        let run = !paused && !isSuspended && !inBackground && !sceneDisconnected
        if run, displayLink == nil {
            compositor.resetFlashHistory()   // a new scene for the flash guard (FX-019-R11)
            if let reader { analyzer.start(reader: reader) }
            let link = CADisplayLink(target: VideoVisualLinkProxy(self), selector: #selector(VideoVisualLinkProxy.fire(_:)))
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
        let audio = LayerAudioContext(frame: nil, bands: UnsafeBufferPointer(start: bands, count: bandCount),
                                      events: UnsafeBufferPointer(start: nil, count: 0), droppedEvents: 0)
        guard compositor.composite(into: drawable.texture, commandBuffer: commands,
                                   presentationTimeNanoseconds: UInt64(max(link.targetTimestamp, 0) * 1e9),
                                   contentScale: Double(view.contentScaleFactor), reduceFlashing: reduceFlashing,
                                   audio: audio) else { return }
        commands.present(drawable)
        commands.commit()
        framesComposited &+= 1
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

    /// FR-049 frame-rate pressure, background and scene connection.
    private func observeSystem() {
        let center = NotificationCenter.default
        let observed: [(Notification.Name, @MainActor (VideoVisualHost, Notification) -> Void)] = [
            (UIApplication.didEnterBackgroundNotification, { host, _ in host.appEnteredBackground() }),
            (UIApplication.willEnterForegroundNotification, { host, _ in host.appWillEnterForeground() }),
            // OUT-001-R9: an external display scene's connect and disconnect never stop or start this
            // visual (or its decoder).
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
private final class VideoVisualLinkProxy: NSObject {
    weak var host: VideoVisualHost?
    init(_ host: VideoVisualHost) { self.host = host }
    @MainActor @objc func fire(_ link: CADisplayLink) { host?.frame(link) }
}
