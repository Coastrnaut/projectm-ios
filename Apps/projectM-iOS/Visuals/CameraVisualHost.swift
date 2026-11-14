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
// * CAM-002: `cameraPosition` and `mirrored` are forwarded to the provider (`select`) and the camera
//   layer (`mirrored`). Neither touches the frame loop, the analysis or the audio source; the mirror
//   lives only in the camera layer, so the screen, Save Frame, Record and the external display (one
//   composite) agree.
// * CAM-007: `crop` is forwarded to the camera layer the same way; the layer recomputes the fit every
//   frame from the drawable's size and the picture's rotation, so a device rotation keeps it.
// * CAM-013 (ADR-0017 decisions 11-14): an interruption or a runtime error already clears the picture
//   (the layer draws only while running). The host keeps a `CameraRecovery` on a monotonic clock:
//   `retryCamera()` (the notice's Retry) stops and starts the camera at once when the backoff allows,
//   else holds one pending retry; a media reset is retried once by itself. Any stop of the loop and
//   Stop camera cancel the pending retry and reset the recovery. Clock and scheduler are injectable
//   (tests use a fake clock). `stopReason`, `retryPending` and the counts are reported to the
//   coordinator through `onRecoveryChange`.
// * Per frame this file allocates nothing: the band scratch is preallocated and the audio context is
//   a view of it; Metal's command buffer and drawable are the system's.
import AudioCore
import CameraLayer
import Compositor
import FrameTiming
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
final class CameraVisualHost: PresentationBoundResource, CompositorVisualHost {
    let view: NativeSpectrumLayerView
    let camera: CameraLayerSource
    private let spectrum: SpectrumLayerSource
    /// Internal for PERF-004's app tests (offscreen frames through the shared pool).
    let compositor: Compositor
    let queue: MTLCommandQueue   // XFADE: the freeze is encoded after this host's frames
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
    /// PERF-014: the compositor's render health record, reported when it changes (once per tick).
    var onRenderHealthChange: ((RenderHealth) -> Void)?
    private var reportedHealthRevision = 0
    /// PERF-014: frame ticks of this visual (DEBUG readout, tests).
    var renderTicks: UInt64 { compositor.frameTicks }
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
    /// The camera feed (CAM-001 data model); `onFeedStateChange` reports every change.
    private(set) var feedState: CameraFeedState = .idle
    var onFeedStateChange: ((CameraFeedState) -> Void)?

    /// Frames that showed a camera picture (diagnostics, UI tests).
    var framesShown: Int { camera.framesShown }

    // MARK: CAM-013 recovery state

    /// The retry rules and counts (numbers only).
    private(set) var recovery = CameraRecovery()
    /// A Retry waits for the backoff to end.
    private(set) var retryPending = false
    /// Why the feed is interrupted or failed (the provider's reason, mirrored on every change).
    private(set) var stopReason: CameraStopReason?
    /// Called after `stopReason`, `retryPending` or the counts change.
    var onRecoveryChange: (() -> Void)?
    /// Monotonic seconds (tests: a fake clock).
    var clock: @MainActor () -> Double = { () -> Double in ProcessInfo.processInfo.systemUptime }
    /// Runs the closure after the delay in seconds on the main actor (tests: a manual scheduler).
    var scheduler: @MainActor (Double, @escaping @MainActor () -> Void) -> Void = CameraVisualHost.sleepThen
    private var retryToken: UInt64 = 0

    /// "<state>|<reason or none>|<attempts>|<pending yes/no>|<counts>" (DEBUG readout; numbers only).
    var recoveryProbe: String {
        let reason: String = stopReason?.rawValue ?? "none"
        let pending: String = retryPending ? "yes" : "no"
        let state: String = "\(feedState)"
        return "\(state)|\(reason)|\(recovery.attempts)|\(pending)|\(recovery.countsSummary)"
    }

    /// CAM-002-R1, R7: the camera in use; a change while running switches cameras without a restart.
    var cameraPosition: CameraPosition {
        get { camera.provider.position }
        set {
            guard newValue != camera.provider.position else { return }
            camera.provider.select(newValue)
            updateAccessibility()
        }
    }

    /// CAM-002-R3, R5: flip the camera picture left to right, from the next frame.
    var mirrored: Bool {
        get { camera.mirrored }
        set { camera.mirrored = newValue }
    }

    /// CAM-007-R1, R5: the camera picture's crop (Fill or Fit, anchor, zoom), from the next frame.
    var crop: CameraCrop {
        get { camera.crop }
        set { camera.crop = newValue }
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

    /// The camera provider: the stand-in for `-uitestCamera <scenario>` (DEBUG; CAM-001-R13), the
    /// real camera otherwise. CAM-002: `-uitestCameraPattern marker` gives the stand-in a red marker
    /// in its top-left quarter, and `-uitestNoFrontCamera` removes its front camera.
    static func makeProvider(device: MTLDevice) -> any CameraFrameProvider {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let i = arguments.firstIndex(of: "-uitestCamera"), i + 1 < arguments.count,
           let scenario = CameraScenario(rawValue: arguments[i + 1]) {
            let orange = StubCameraFrameProvider.Color(red: 230, green: 120, blue: 30)
            let red = StubCameraFrameProvider.Color(red: 255, green: 0, blue: 0)
            let pattern: StubCameraFrameProvider.Pattern = arguments.contains("-uitestCameraPattern")
                ? .marker(background: orange, marker: red) : .solid(orange)
            let positions: Set<CameraPosition> = arguments.contains("-uitestNoFrontCamera") ? [.back] : [.back, .front]
            return StubCameraFrameProvider(device: device, scenario: scenario, pattern: pattern, width: 64, height: 48,
                                           availablePositions: positions)
        }
        #endif
        #if os(iOS)
        return AVCameraFrameProvider(device: device)
        #endif
    }

    /// Throws `VisualGeneratorError`, `LayerStackError` or `CompositorError` when there is no Metal device or a pipeline
    /// cannot be built; the caller falls back to projectM with a notice (spec Edge Cases).
    static func make(device: MTLDevice?, reader: (any NormalizedPCMReader)?, barCount: SpectrumBarCount,
                     position: CameraPosition = .back, mirrored: Bool = false, crop: CameraCrop = .fill,
                     provider: ((MTLDevice) -> any CameraFrameProvider)? = nil) throws -> CameraVisualHost {
        guard let device, let queue = device.makeCommandQueue() else { throw VisualGeneratorError.noDevice }
        let transparent = LinearColor(red: 0, green: 0, blue: 0, alpha: 0)
        let generator = try CircularSpectrumGenerator(device: device, pixelFormat: LayerPictureDescriptor.metalPixelFormat,
                                                      configuration: CircularSpectrumConfiguration(barCount: barCount, background: transparent))
        let spectrum = try SpectrumLayerSource(device: device, generator: generator, name: "spectrum")
        let camera = CameraLayerSource(provider: (provider ?? makeProvider)(device))
        camera.provider.select(position)   // CAM-002: before any start, so only the chosen camera ever runs
        camera.mirrored = mirrored
        camera.crop = crop   // CAM-007
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
        let reason: CameraStopReason? = state.offersRetry ? camera.provider.stopReason : nil
        stopReason = reason
        let now: Double = clock()
        if state == .running {
            recovery.noteRunning(now: now)
        } else if let reason {
            recovery.noteStop(reason, now: now)
        }
        updateAccessibility()
        onFeedStateChange?(state)
        onRecoveryChange?()
        // CAM-013-R7: one automatic retry after a media reset, through the backoff.
        // Deferred through the scheduler: never a restart inside the provider's own state callback.
        if let reason, recovery.claimAutomaticRetry(for: reason) { retryCamera(deferred: true) }
    }

    // MARK: - CAM-013 Retry

    /// The notice's Retry (CAM-013-R5, R6): runs at once when the backoff allows, else holds one
    /// pending retry that runs when the wait ends. Ignored unless the loop runs, the user has not
    /// stopped the camera and the feed offers Retry.
    func retryCamera(deferred: Bool = false) {
        guard isRunning, !cameraStoppedByUser, feedState.offersRetry, !retryPending else { return }
        let delay: Double = recovery.delayBeforeNextAttempt(now: clock())
        guard delay > 0 || deferred else {
            performRetry()
            return
        }
        retryPending = true
        retryToken &+= 1
        let token: UInt64 = retryToken
        onRecoveryChange?()
        scheduler(delay) { [weak self] () -> Void in
            guard let self, self.retryPending, token == self.retryToken else { return }
            self.retryPending = false
            self.onRecoveryChange?()
            guard self.isRunning, !self.cameraStoppedByUser, self.feedState.offersRetry else { return }
            self.performRetry()
        }
    }

    /// A retry: the camera stops completely (picture dropped, session released) and starts again.
    private func performRetry() {
        recovery.recordAttempt(now: clock())
        camera.stop()
        camera.start()
        onRecoveryChange?()
    }

    /// The camera was stopped by the user or the app: no pending retry, a new run (counts kept).
    private func cancelRecovery() {
        retryToken &+= 1
        retryPending = false
        recovery.reset()
        onRecoveryChange?()
    }

    static func sleepThen(_ seconds: Double, _ action: @escaping @MainActor () -> Void) {
        let nanoseconds: UInt64 = UInt64(max(seconds, 0) * 1_000_000_000)
        Task { @MainActor () -> Void in
            try? await Task.sleep(nanoseconds: nanoseconds)
            action()
        }
    }

    private func updateAccessibility() {
        view.accessibilityLabel = "Camera visualization"
        view.accessibilityIdentifier = "cameraVisual"
        view.accessibilityValue = feedState.accessibilityValue(position: camera.provider.position)
    }

    /// CAM-012-R4: the user's Stop camera. Stops the camera before returning (the provider reports
    /// idle synchronously), drops the held picture, and keeps the camera off on this host whatever
    /// happens next (resume, foreground, scene, presentation). The frame loop is left as it was.
    func stopCamera() {
        cameraStoppedByUser = true
        camera.stop()
        cancelRecovery()   // CAM-013-R6
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
            compositor.resetRenderHealth()   // PERF-014-R6: a fresh retry budget whenever the loop starts
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
            cancelRecovery()   // CAM-013-R6, R11: background, pause, scene or presentation loss
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
