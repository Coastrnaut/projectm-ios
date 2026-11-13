// CameraVisualHost.swift — the Camera visual on screen (CAM-001-R1, R5 to R8, R10, R14; research
// CAM-001-D1, D6; ADR-0017).
//
// * One CMP-001 `Compositor` with two layers: the camera (`CameraLayerSource`, transparent fallback)
//   at the bottom and the circular spectrum (`SpectrumLayerSource`, transparent background) on top,
//   composited into a `CAMetalLayer` (`bgra8Unorm_srgb`) by one `CADisplayLink` on the main run loop.
//   The composite flash guard applies Reduce flashing to the whole picture, camera included.
//   CMP-002: the two layers are a `LayerStack` (camera bottom, spectrum top) applied to the
//   compositor; the camera kind allows one instance, so no stack can open a second capture
//   session. The stack is fixed here: editing layers by hand belongs to the layer inspector
//   (CMP-015) and the editing UI rows.
// * The camera runs only while the frame loop runs: resumed (the coordinator calls `resume()` only
//   while Camera is shown on the visualizer and not paused), not suspended for presentation loss
//   (PERF-011), the app not in the background and the scene connected. Whenever one of these stops
//   holding, the loop and the camera stop before the call returns (CAM-001-R7).
// * CAM-012: `stopCamera()` is the user's Stop camera. The camera stops before it returns (the
//   provider's slot closed, its picture dropped, state idle); the frame loop keeps running if it
//   ran, and nothing on this host starts the camera again (the coordinator then releases the host).
//   `framesComposited` counts presented frames, so tests can see that the loop never froze.
// * The provider's state is mirrored in `feedState` and handed to the coordinator, which shows the
//   non-blocking notice (CAM-001-R5, R6, R8). The view's accessibility value names it (R14).
// * Per frame this file allocates nothing: the band scratch is preallocated and the audio context is
//   a view of it; Metal's command buffer and drawable are the system's.
import AudioCore
import CameraLayer
import Compositor
import Metal
import PerformanceControlAnalysis
import PresentationLifecycle
import QuartzCore
import Rendering
import SpectrumLayers
import UIKit
import VisualBandFeed
import VisualGenerators

@MainActor
final class CameraVisualHost: PresentationBoundResource {
    let view: NativeSpectrumLayerView
    let camera: CameraLayerSource
    private let spectrum: SpectrumLayerSource
    /// Internal for PERF-004's app tests (offscreen frames through the shared pool).
    let compositor: Compositor
    private let queue: MTLCommandQueue
    private let analyzer: LiveBandAnalyzer
    private let reader: (any NormalizedPCMReader)?
    private let bands: UnsafeMutablePointer<Float>
    private var bandCount = 0
    private var displayLink: CADisplayLink?
    private var paused = true
    /// CAM-012: the user stopped the camera; this host never starts it again.
    private(set) var cameraStoppedByUser = false
    /// CAM-012: frames the loop presented (tests, diagnostics; an Int, no allocation).
    private(set) var framesComposited = 0
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
    /// The camera feed (CAM-001 data model); `onFeedStateChange` reports every change.
    private(set) var feedState: CameraFeedState = .idle
    var onFeedStateChange: ((CameraFeedState) -> Void)?

    /// Frames that showed a camera picture (diagnostics, UI tests).
    var framesShown: Int { camera.framesShown }

    var barCount: SpectrumBarCount {
        get { spectrum.generator.barCount }
        set {
            guard newValue != spectrum.generator.barCount else { return }
            spectrum.generator.barCount = newValue
            analyzer.setBarCount(newValue)
            bandCount = 0
        }
    }

    /// The camera provider: the stand-in for `-uitestCamera <scenario>` (DEBUG; CAM-001-R13), the
    /// rear camera otherwise.
    static func makeProvider(device: MTLDevice) -> any CameraFrameProvider {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let i = arguments.firstIndex(of: "-uitestCamera"), i + 1 < arguments.count,
           let scenario = CameraScenario(rawValue: arguments[i + 1]) {
            let orange = StubCameraFrameProvider.Color(red: 230, green: 120, blue: 30)
            return StubCameraFrameProvider(device: device, scenario: scenario, pattern: .solid(orange), width: 64, height: 48)
        }
        #endif
        #if os(iOS)
        return AVCameraFrameProvider(device: device)
        #endif
    }

    /// Throws `VisualGeneratorError`, `LayerStackError` or `CompositorError` when there is no Metal device or a pipeline
    /// cannot be built; the caller falls back to projectM with a notice (spec Edge Cases).
    static func make(device: MTLDevice?, reader: (any NormalizedPCMReader)?, barCount: SpectrumBarCount,
                     provider: ((MTLDevice) -> any CameraFrameProvider)? = nil) throws -> CameraVisualHost {
        guard let device, let queue = device.makeCommandQueue() else { throw VisualGeneratorError.noDevice }
        let transparent = LinearColor(red: 0, green: 0, blue: 0, alpha: 0)
        let generator = try CircularSpectrumGenerator(device: device, pixelFormat: LayerPictureDescriptor.metalPixelFormat,
                                                      configuration: CircularSpectrumConfiguration(barCount: barCount, background: transparent))
        let spectrum = try SpectrumLayerSource(device: device, generator: generator, name: "spectrum")
        let camera = CameraLayerSource(provider: (provider ?? makeProvider)(device))
        // CMP-002: the stack, bottom first: the camera (one per stack), then the circular spectrum.
        var stack = LayerStack()
        try stack.add(LayerDescriptor(kind: .camera))
        try stack.add(LayerDescriptor(kind: .circularSpectrum))
        let compositor = try Compositor(device: device, texturePool: SharedTexturePool.pool(for: device))   // PERF-004
        try compositor.apply(stack) { (entry: LayerStackEntry) throws(LayerSourceError) -> any LayerSource in
            switch entry.descriptor.kind {
            case .camera: return camera
            case .circularSpectrum: return spectrum
            default: throw .notReady
            }
        }
        let analyzer = try LiveBandAnalyzer(barCount: barCount)
        return CameraVisualHost(device: device, queue: queue, camera: camera, spectrum: spectrum, compositor: compositor,
                                analyzer: analyzer, reader: reader)
    }

    private init(device: MTLDevice, queue: MTLCommandQueue, camera: CameraLayerSource, spectrum: SpectrumLayerSource,
                 compositor: Compositor, analyzer: LiveBandAnalyzer, reader: (any NormalizedPCMReader)?) {
        self.queue = queue
        self.camera = camera
        self.spectrum = spectrum
        self.compositor = compositor
        self.analyzer = analyzer
        self.reader = reader
        bands = .allocate(capacity: SpectrumBarCount.maximum)
        bands.initialize(repeating: 0, count: SpectrumBarCount.maximum)
        view = NativeSpectrumLayerView(device: device)
        view.onLayout = { [weak self] in self?.layoutDrawable() }
        camera.provider.onStateChange = { [weak self] state in
            MainActor.assumeIsolated { self?.feedStateChanged(state) }
        }
        observeSystem()
        updateAccessibility()
    }

    isolated deinit {
        displayLink?.invalidate()
        analyzer.stop()
        camera.stop()
        observers.forEach(NotificationCenter.default.removeObserver)
        bands.deinitialize(count: SpectrumBarCount.maximum)
        bands.deallocate()
    }

    /// SHOW-011: while this visual is shown its analyzer is the analysis tap's only reader.
    private(set) lazy var tempoReader: TempoSubscriptionReader? = (try? analyzer.subscribe()).map {
        TempoSubscriptionReader(subscription: $0, sampleRate: analyzer.sampleRate)
    }

    /// True while the frame loop and the camera run.
    var isRunning: Bool { displayLink != nil }

    private func feedStateChanged(_ state: CameraFeedState) {
        feedState = state
        updateAccessibility()
        onFeedStateChange?(state)
    }

    private func updateAccessibility() {
        view.accessibilityLabel = "Camera visualization"
        view.accessibilityIdentifier = "cameraVisual"
        view.accessibilityValue = feedState.accessibilityValue
    }

    /// CAM-012-R4: the user's Stop camera. Stops the camera before returning (the provider reports
    /// idle synchronously), drops the held picture, and keeps the camera off on this host whatever
    /// happens next (resume, foreground, scene, presentation). The frame loop is left as it was.
    func stopCamera() {
        cameraStoppedByUser = true
        camera.stop()
    }

    // MARK: - Pause (FR-046), presentation (PERF-011), background and scene (CAM-001-R7)

    func pause() {
        paused = true
        updateLoop()
    }

    func resume() {
        paused = false
        updateLoop()
    }

    var presentationResources: [any PresentationBoundResource] { [self] }
    var presentationResourceName: String { "Camera visual frame loop, camera and analysis" }

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

    /// The app entered the background (also handled by PERF-011; this stops the camera without
    /// waiting for the lifecycle stream).
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
            if !cameraStoppedByUser { camera.start() }   // CAM-012-R6
            if let reader { analyzer.start(reader: reader) }
            let link = CADisplayLink(target: CameraVisualLinkProxy(self), selector: #selector(CameraVisualLinkProxy.fire(_:)))
            link.preferredFrameRateRange = quality.frameRateRange
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else if !run, let link = displayLink {
            link.invalidate()
            displayLink = nil
            camera.stop()
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

    /// FR-049 frame-rate pressure, background and scene connection (CAM-001-R7).
    private func observeSystem() {
        let center = NotificationCenter.default
        let observed: [(Notification.Name, @MainActor (CameraVisualHost, Notification) -> Void)] = [
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
private final class CameraVisualLinkProxy: NSObject {
    weak var host: CameraVisualHost?
    init(_ host: CameraVisualHost) { self.host = host }
    @MainActor @objc func fire(_ link: CADisplayLink) { host?.frame(link) }
}
