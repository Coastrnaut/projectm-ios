// ANGLERenderer.swift — ADR-0003 Option B: the engine on ANGLE's Metal backend (task T077).
//
// * EGL display on ANGLE's Metal platform (EGL_PLATFORM_ANGLE_TYPE_METAL_ANGLE), an OpenGL ES 3.0
//   context, and a window surface on the view's CAMetalLayer (recreated when the drawable size
//   changes). Until the view has a size, a 1 × 1 pbuffer keeps the context current.
// * The engine resolves GL functions through eglGetProcAddress (PMANGLELoadProc; contract
//   projectm-bridge.md). No dlsym in this package.
// * Same frame loop as GLESRenderer: a CADisplayLink at up to 60 fps (30 under Low Power Mode or
//   serious thermal state, FR-049), one NormalizedPCMReader read per frame, render to the window
//   surface's default framebuffer (0), then eglSwapBuffers.
// * Strobe safety envelope (FX-019, ADR-0011; Reduce flashing FR-072, T104): the engine renders into
//   CFlashLimiter's offscreen texture on every frame and the pass draws it dimmed by the envelope's
//   gain: `FlashEnvelopeConfiguration.reduceFlashing` while Reduce flashing is on, the always-on cap
//   while it is off.
// * Everything runs on the main thread, the engine's render thread, except PresetPrewarmer
//   (feature 002 SC-104), which warms upcoming presets on its own thread and context, and
//   PresetTrialRunner (PRE-012), which tries imported presets on a thread, context and engine of
//   its own before they may be loaded here.
// * PERF-011: while the app cannot present frames (background, device lock) the renderer is
//   suspended: no display link, no frame, and the window surface and the Reduce-flashing target
//   are released. The context, engine, preset and textures stay, so the picture continues where it
//   was. Suspension is independent of pause()/resume() (FR-046): the loop runs only when neither
//   applies. The warm-up is a second presentation-bound resource (PresetWarmUpController).
// * REC-001 (specs/055-rec-001-still-frame-capture, research REC-001-D1): `captureNextFrame` reads
//   the next rendered frame back with glReadPixels after the FX-019 post-pass wrote framebuffer 0 and
//   before eglSwapBuffers (the swap leaves the buffer undefined), i.e. the frame as shown. One
//   synchronous read on the render thread, only for a request; frames without one are unchanged.
// * PERF-014 (specs/057-perf-014-render-failure-fallback, contracts/render-health.md): `health` is
//   projectM's render health record. A preset that fails to load (an invalid shader included) is
//   recorded as `presetLoadFailed` and the error is rethrown (FR-045 keeps the previous preset). A
//   failed swap is a counted `presentationFailed` fault: no frame is rendered until the back-off's
//   retry tick (30, 60, 120, 240 display ticks), each retry recreates the window surface, and after
//   the last failed retry the state is `placeholder` until `resume()` or `resumeForPresentation()`.
//   DEBUG builds can arm `faultInjection` (preset loads, swap results).
import AudioCore
import CANGLE
import CFlashLimiter
import Compositor
import FlashSafety
import Foundation
import FrameTiming
import PresentationLifecycle
import ProjectMBridge
import QuartzCore
import Rendering
import UIKit

/// REC-001: one frame read back from the window surface: 8-bit RGBA as the engine and the post-pass
/// wrote it (display-encoded), rows bottom-up (GL order), the surface's pixel size.
public struct ANGLECapturedFrame: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public let rgbaBottomUp: [UInt8]
}

public enum ANGLERendererError: Error, Equatable {
    case displayUnavailable(Int32)
    case noConfig(Int32)
    case contextUnavailable(Int32)
    case surfaceUnavailable(Int32)
}

@MainActor
public final class ANGLERenderer: NSObject, VisualizerRenderer, PresentationBoundResource {
    public var view: UIView { layerView }
    public private(set) var metrics = RenderMetrics.zero
    public private(set) var presentedFrameCount = 0
    /// PERF-001 (specs/152-perf-001-stage-timings): while set (the performance overlay is shown), each presented
    /// frame records its audio, render, output (flash-limiter pass) and present stages. Nil: no timing work.
    /// projectM's GPU time is unavailable: ANGLE submits the Metal work itself (research PERF-001-D3).
    public var stageTimer: FrameStageTimer? {
        didSet { stageTimer?.configure(pipeline: Self.frameStages) }
    }
    public static let frameStages: [FrameStage] = [.audio, .render, .output, .present]
    /// FR-072: selects the stricter envelope (FlashLimiter.c, FX-019). Toggling keeps the envelope's
    /// history, so a strobe cannot restart its budget (FX-019-R11).
    public var reduceFlashing = false
    /// ACC-012-R5: the sensory safety profile's envelope when it differs from the Reduce flashing one
    /// (`SafetyClamp.flashLimitsOverride`); nil = `forReduceFlashing(reduceFlashing)`, today's path. From the
    /// next frame; the envelope's history is kept (FX-019-R11).
    public var flashLimits: FlashEnvelopeConfiguration?
    /// The envelope the next frame's pass applies.
    public var flashConfiguration: FlashEnvelopeConfiguration {
        flashLimits ?? FlashEnvelopeConfiguration.forReduceFlashing(reduceFlashing)
    }
    /// While Reduce flashing is on, every area's mean relative luminance rises at most this much per
    /// second (FlashEnvelopeConfiguration.reduceFlashing; a 0.10 rise takes at least 0.4 s).
    public static let flashLimitPerSecond = Float(FlashEnvelopeConfiguration.reduceFlashing.riseRatePerSecond ?? 0)
    /// RendererLab's T104 baseline: frames bypass the pass (`timedFrames(_:reduceFlashing: false)`).
    private var envelopeBypassed = false
    public let supportsReduceFlashing = true
    private var flashLimiter: OpaquePointer?

    private let layerView: MetalLayerView
    private let display: EGLDisplay
    private let config: EGLConfig
    private let context: EGLContext
    private let placeholder: EGLSurface
    private var surface: EGLSurface?
    private var surfaceSize = (width: 0, height: 0)
    private var engine: ProjectMEngine?
    private var displayLink: CADisplayLink?
    private var reader: (any NormalizedPCMReader)?
    private let pcm: UnsafeMutablePointer<Float>
    private let maxFrames: Int
    private var meter = FrameRateMeter()
    private var paused = false
    /// PERF-011: the app cannot present frames. Independent of `paused`.
    private var presentationSuspended = false
    /// The view is in a window, so a display link is wanted whenever frames can be presented.
    private var inWindow = false
    private var observers: [NSObjectProtocol] = []
    /// REC-001: the handler waiting for the next rendered frame.
    private var pendingCapture: (@MainActor (ANGLECapturedFrame?) -> Void)?
    /// Feature 002 SC-104: upcoming presets' pipelines are built in the background (PresetPrewarmer).
    public var prewarmEnabled: Bool {
        get { warmUp.enabled }
        set { warmUp.enabled = newValue }
    }
    private var texturePaths: [String] = []
    /// The warm-up starts this long after a request, once the switch's blend is over. Warming during
    /// the blend cost D1 a third of its frame rate (2026-11-10: 29 vs 43 fps in the 3 s after a switch).
    public var prewarmDelay: Duration {
        get { warmUp.delay }
        set { warmUp.delay = newValue }
    }
    /// When the warm-up runs; a presentation-bound resource of its own (PERF-011-R7, R8).
    let warmUp: PresetWarmUpController
    /// PRE-012: tries imported presets on a separate engine before they may be played.
    let trialRunner: PresetTrialRunner
    public var presetTrial: (any PresetTrialing)? { trialRunner }
    /// PRE-001: the browser's thumbnails, drawn on their own thread, context and engine.
    let thumbnailRunner: PresetThumbnailRunner
    public var presetThumbnails: (any PresetThumbnailDrawing)? { thumbnailRunner }

    /// PERF-014-R2: projectM's render health record; `onRenderHealthChange` hears every update.
    public private(set) var health = RenderHealth()
    public var onRenderHealthChange: ((RenderHealth) -> Void)?
    /// PERF-014-D1: display-link ticks (the back-off's time base).
    public private(set) var displayTicks: UInt64 = 0
    public var recoveryPolicy = RenderRecoveryPolicy.standard
    private var presentationRetry = RenderRetryState()
    #if DEBUG
    /// PERF-014-R15: faults to force (DEBUG builds only).
    public var faultInjection = RenderFaultInjection()
    #endif

    private init(display: EGLDisplay, config: EGLConfig, context: EGLContext, placeholder: EGLSurface,
                 engine: ProjectMEngine) {
        self.display = display
        self.config = config
        self.context = context
        self.placeholder = placeholder
        self.engine = engine
        maxFrames = Int(ProjectMEngine.maxSamplesPerFrame)
        pcm = UnsafeMutablePointer<Float>.allocate(capacity: maxFrames * 2)
        pcm.initialize(repeating: 0, count: maxFrames * 2)
        layerView = MetalLayerView(frame: .zero)
        warmUp = PresetWarmUpController(worker: PresetPrewarmer(display: display, config: config),
                                        delay: .milliseconds(Int(presetBlendSeconds * 1000) + 500))
        trialRunner = PresetTrialRunner(display: display, config: config)
        thumbnailRunner = PresetThumbnailRunner(display: display, config: config)
        super.init()
        layerView.onLayout = { [weak self] in self?.layoutSurface() }
        layerView.onWindowChange = { [weak self] inWindow in
            self?.inWindow = inWindow
            inWindow ? self?.startDisplayLink() : self?.stopDisplayLink()
        }
        observeFrameRatePressure()
    }

    /// Creates the EGL display, context and engine. The display link starts when the view joins a
    /// window and stops when it leaves.
    public static func make() throws -> ANGLERenderer {
        let platform: [EGLAttrib] = [EGLAttrib(EGL_PLATFORM_ANGLE_TYPE_ANGLE), EGLAttrib(EGL_PLATFORM_ANGLE_TYPE_METAL_ANGLE),
                                     EGLAttrib(EGL_NONE)]
        guard let display = eglGetPlatformDisplay(EGLenum(EGL_PLATFORM_ANGLE_ANGLE), nil, platform),
              eglInitialize(display, nil, nil) == EGL_TRUE else {
            throw ANGLERendererError.displayUnavailable(eglGetError())
        }
        let attributes: [EGLint] = [EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8,
                                    EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
                                    EGL_SURFACE_TYPE, EGL_WINDOW_BIT | EGL_PBUFFER_BIT, EGL_NONE]
        var config: EGLConfig?
        var count: EGLint = 0
        guard eglChooseConfig(display, attributes, &config, 1, &count) == EGL_TRUE, count > 0, let config else {
            throw ANGLERendererError.noConfig(eglGetError())
        }
        let contextAttributes: [EGLint] = [EGL_CONTEXT_MAJOR_VERSION, 3, EGL_CONTEXT_MINOR_VERSION, 0, EGL_NONE]
        guard let context = eglCreateContext(display, config, nil, contextAttributes) else {
            throw ANGLERendererError.contextUnavailable(eglGetError())
        }
        let pbuffer: [EGLint] = [EGL_WIDTH, 1, EGL_HEIGHT, 1, EGL_NONE]
        guard let placeholder = eglCreatePbufferSurface(display, config, pbuffer),
              eglMakeCurrent(display, placeholder, placeholder, context) == EGL_TRUE else {
            throw ANGLERendererError.surfaceUnavailable(eglGetError())
        }
        let engine = try ProjectMEngine(glLoader: PMANGLELoadProc, userData: nil)
        engine.softCutDuration = presetBlendSeconds   // FR-043 / T091: blend at most 2 s
        return ANGLERenderer(display: display, config: config, context: context, placeholder: placeholder, engine: engine)
    }

    isolated deinit {
        trialRunner.setSuspended(true)   // no new trial; a running one stops at its next safe point
        thumbnailRunner.setSuspended(true)   // PRE-001: likewise for a thumbnail
        warmUp.shutdown()
        displayLink?.invalidate()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        eglMakeCurrent(display, placeholder, placeholder, context)
        PMFlashLimiterDestroy(flashLimiter)
        engine = nil   // destroyed while its context is current (bridge guarantee 3)
        eglMakeCurrent(display, nil, nil, nil)
        if let surface { eglDestroySurface(display, surface) }
        eglDestroySurface(display, placeholder)
        eglDestroyContext(display, context)
        pcm.deinitialize(count: maxFrames * 2)
        pcm.deallocate()
    }

    // MARK: - VisualizerRenderer

    public func attach(pcm reader: any NormalizedPCMReader) {
        self.reader = reader
    }

    public func setPreset(_ preset: Preset) async throws {
        guard let engine else { return }
        makeCurrent()
        do {
            #if DEBUG
            if faultInjection.failPresetLoads > 0 {   // PERF-014-R15: as a shader that does not compile
                faultInjection.failPresetLoads -= 1
                throw PMEngineError(.presetLoadFailed, userInfo: [NSLocalizedDescriptionKey: "Preset shader failed to compile (injected)"])
            }
            #endif
            if let data = preset.data {
                try engine.loadPresetData(data, smooth: true)
            } else {
                try engine.loadPreset(atPath: preset.fileURL.path, smooth: true)
            }
        } catch {
            updateHealth { (health: inout RenderHealth) in health.recordFault(.presetLoadFailed, atTick: displayTicks) }   // PERF-014-R8
            throw error
        }
    }

    public func setTextureSearchPaths(_ paths: [URL]) {
        guard let engine else { return }
        makeCurrent()
        texturePaths = paths.map(\.path)
        engine.setTextureSearchPaths(texturePaths)
        trialRunner.setTexturePaths(texturePaths)
        thumbnailRunner.setTexturePaths(texturePaths)
    }

    public func prewarm(_ presets: [Preset]) {
        warmUp.request(presets, texturePaths: texturePaths)
    }

    /// Presets whose pipelines were built in the background (tests and automation reports).
    public var prewarmedCount: Int { warmUp.warmedCount }

    public func pause() {
        paused = true
        displayLink?.isPaused = true
        meter.reset()
    }

    public func resume() {
        paused = false
        displayLink?.isPaused = false
        resetPresentationHealth()
    }

    // MARK: - Frames

    /// Renders one frame; with `present`, swaps it onto the layer. Returns false with no surface.
    /// `frameTime` (seconds since the previous frame) sets the Reduce-flashing step.
    @discardableResult
    func renderFrame(present: Bool = true, frameTime: Double = 1.0 / 60) -> Bool {
        guard !presentationSuspended, let engine, let surface else { return false }
        // PERF-001: shown frames only; FrameTiming comes with the Compositor product.
        let timer: FrameStageTimer? = present ? stageTimer : nil
        timer?.beginFrame()
        defer { timer?.endFrame() }
        eglMakeCurrent(display, surface, surface, context)
        timer?.begin(.audio)
        if let reader {
            let frames = reader.read(into: pcm, maxFrames: maxFrames)
            if frames > 0 {
                engine.addPCMInterleavedStereo(pcm, frames: UInt(frames))
            }
        }
        timer?.end(.audio)
        timer?.begin(.render)
        if !envelopeBypassed, let limiter = flashLimiterForFrame() {
            let framebuffer = PMFlashLimiterBegin(limiter, Int32(surfaceSize.width), Int32(surfaceSize.height))
            if framebuffer != 0 {
                engine.renderFrame(toFramebuffer: framebuffer)
                timer?.end(.render)
                timer?.begin(.output)
                var parameters = flashConfiguration.limiterParameters(frameTime: frameTime)
                PMFlashLimiterFinish(limiter, 0, &parameters)
                timer?.end(.output)
            } else {
                engine.renderFrame(toFramebuffer: 0)
            }
        } else {
            engine.renderFrame(toFramebuffer: 0)
        }
        timer?.end(.render)   // no-op when the output pass already ended it
        if let handler = pendingCapture {   // REC-001: the frame as shown, before the swap
            pendingCapture = nil
            let pixels = readPixels()
            handler(pixels.isEmpty ? nil : ANGLECapturedFrame(width: surfaceSize.width, height: surfaceSize.height, rgbaBottomUp: pixels))
            eglMakeCurrent(display, surface, surface, context)
        }
        if present {
            timer?.begin(.present)
            var swapped = eglSwapBuffers(display, surface) == EGL_TRUE
            timer?.end(.present)
            #if DEBUG
            if faultInjection.failPresentation { swapped = false }
            #endif
            presentationResult(swapped)
            guard swapped else { return false }
            presentedFrameCount += 1
        }
        return true
    }

    // MARK: - Render health (PERF-014)

    /// One display tick (PERF-014-R9): no frame while the presentation part backs off; at its retry
    /// tick the window surface is recreated first. Returns true when a frame was presented.
    @discardableResult
    func presentationTick(frameTime: Double = 1.0 / 60) -> Bool {
        displayTicks &+= 1
        if presentationRetry.isRetryDue(atTick: displayTicks) {
            presentationRetry.beginRetry(atTick: displayTicks)
            recreateSurface()
        }
        guard !presentationRetry.isHolding else { return false }
        return renderFrame(frameTime: frameTime)
    }

    private func presentationResult(_ swapped: Bool) {
        updateHealth { (health: inout RenderHealth) in
            if swapped {
                if presentationRetry.succeeded(encodedAtTick: displayTicks) { health.recordRecovery() }
            } else if presentationRetry.fault(atTick: displayTicks, policy: recoveryPolicy) {
                health.recordFault(.presentationFailed, atTick: displayTicks)
            }
        }
    }

    /// PERF-014-R6: a fresh budget; a faulted presentation is tried again from the next tick.
    private func resetPresentationHealth() {
        guard presentationRetry.isFaulted else { return }
        updateHealth { (_: inout RenderHealth) in presentationRetry.reset(atTick: displayTicks &+ 1) }
    }

    /// Applies `change`, derives the state from the presentation part, and reports a changed record.
    private func updateHealth(_ change: (inout RenderHealth) -> Void) {
        let revision = health.revision
        change(&health)
        health.setState(presentationRetry.hasGivenUp ? .placeholder : (presentationRetry.isFaulted ? .recovering : .healthy))
        if health.revision != revision { onRenderHealthChange?(health) }
    }

    /// A retry's fresh window surface at the view's size.
    private func recreateSurface() {
        guard !presentationSuspended else { return }
        eglMakeCurrent(display, placeholder, placeholder, context)
        if let surface { eglDestroySurface(display, surface) }
        surface = nil
        surfaceSize = (0, 0)
        layoutSurface()
    }

    // MARK: - Frame capture (REC-001)

    /// Reads back the next frame this renderer renders, after the flash post-pass; `handler` runs once
    /// on the main actor (nil if the read fails or the request is replaced or cancelled).
    public func captureNextFrame(_ handler: @escaping @MainActor (ANGLECapturedFrame?) -> Void) {
        pendingCapture?(nil)
        pendingCapture = handler
    }

    /// Drops a pending capture (its handler gets nil).
    public func cancelFrameCapture() {
        let handler = pendingCapture
        pendingCapture = nil
        handler?(nil)
    }

    /// True while a capture waits for the next frame.
    public var hasPendingFrameCapture: Bool { pendingCapture != nil }

    /// Created on first use, with the context current.
    private func flashLimiterForFrame() -> OpaquePointer? {
        if flashLimiter == nil { flashLimiter = PMFlashLimiterCreate(PMANGLELoadProc, nil) }
        return flashLimiter
    }

    @objc fileprivate func displayLinkFired(_ link: CADisplayLink) {
        guard presentationTick(frameTime: link.targetTimestamp - link.timestamp) else { return }
        if meter.record(presentedAt: link.timestamp) {
            metrics = meter.metrics
        }
    }

    private func makeCurrent() {
        let target = surface ?? placeholder
        eglMakeCurrent(display, target, target, context)
    }

    private func startDisplayLink() {
        guard displayLink == nil, !presentationSuspended else { return }
        let link = CADisplayLink(target: ANGLEDisplayLinkProxy(self), selector: #selector(ANGLEDisplayLinkProxy.fire(_:)))
        link.preferredFrameRateRange = frameRateRange()
        link.isPaused = paused
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        meter.reset()
    }

    /// FR-049 via QualityGovernor (T100): frame-rate cap and render scale for the thermal state
    /// and Low Power Mode, never below 30 fps.
    private var quality = QualityGovernor.current()

    private func frameRateRange() -> CAFrameRateRange {
        quality.frameRateRange
    }

    private func observeFrameRatePressure() {
        let center = NotificationCenter.default
        for name in [ProcessInfo.thermalStateDidChangeNotification, Notification.Name.NSProcessInfoPowerStateDidChange] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let quality = QualityGovernor.current()
                    guard quality != self.quality else { return }
                    self.quality = quality
                    self.displayLink?.preferredFrameRateRange = self.frameRateRange()
                    self.layerView.setNeedsLayout()   // render scale may have changed
                }
            })
        }
    }

    // MARK: - Surface

    private func layoutSurface() {
        // PERF-011-R6: no surface while the app cannot present; resume lays out again.
        guard !presentationSuspended else { return }
        let displayScale = layerView.traitCollection.displayScale > 0 ? layerView.traitCollection.displayScale : 2
        let scale = displayScale * quality.renderScale   // FR-049: lower render scale when critical
        layerView.contentScaleFactor = scale
        layerView.metalLayer.contentsScale = scale
        let width = Int((layerView.bounds.width * scale).rounded())
        let height = Int((layerView.bounds.height * scale).rounded())
        guard width > 0, height > 0, (width, height) != surfaceSize else { return }
        layerView.metalLayer.drawableSize = CGSize(width: width, height: height)
        eglMakeCurrent(display, placeholder, placeholder, context)
        if let surface { eglDestroySurface(display, surface) }
        surface = nil
        surfaceSize = (0, 0)
        let layer = Unmanaged.passUnretained(layerView.metalLayer).toOpaque()
        guard let created = eglCreateWindowSurface(display, config, layer, nil) else { return }
        surface = created
        var w: EGLint = 0
        var h: EGLint = 0
        eglQuerySurface(display, created, EGL_WIDTH, &w)
        eglQuerySurface(display, created, EGL_HEIGHT, &h)
        surfaceSize = (Int(w), Int(h))
        eglMakeCurrent(display, created, created, context)
        engine?.setViewportWidth(Int(w), height: Int(h))
    }

    // MARK: - PERF-011: presentation-bound resource

    /// Registration order: the frame loop and surface first, then the warm-up. The registry
    /// suspends in reverse (warm-up first) and resumes in this order.
    public var presentationResources: [any PresentationBoundResource] { [self, warmUp] }
    /// PERF-006: the warm-up's context (cache) and the warm-up itself (optional).
    public var memoryPressureResponders: [any MemoryPressureResponder] { warmUp.memoryPressureResponders }

    public var presentationResourceName: String { "ANGLE frame loop and surface" }

    /// Stops the frame loop and releases the window surface (its drawables) and the Reduce-flashing
    /// target. The context, engine, current preset and textures are kept.
    public func suspendForPresentationLoss() {
        guard !presentationSuspended else { return }
        presentationSuspended = true
        cancelFrameCapture()   // REC-001-R14: no frame until presentation returns
        trialRunner.setSuspended(true)   // PRE-012: no off-screen trial without presentation either
        thumbnailRunner.setSuspended(true)   // PRE-001: nor a thumbnail
        stopDisplayLink()
        eglMakeCurrent(display, placeholder, placeholder, context)
        if let flashLimiter {
            PMFlashLimiterDestroy(flashLimiter)   // recreated on the next limited frame
            self.flashLimiter = nil
        }
        if let surface { eglDestroySurface(display, surface) }
        surface = nil
        surfaceSize = (0, 0)
    }

    /// Recreates the surface at the view's current size and restarts the frame loop if the view is
    /// in a window (paused if the user paused).
    public func resumeForPresentation() {
        guard presentationSuspended else { return }
        presentationSuspended = false
        trialRunner.setSuspended(false)
        thumbnailRunner.setSuspended(false)
        resetPresentationHealth()
        layoutSurface()
        if inWindow { startDisplayLink() }
    }

    // MARK: - Measurement (RendererLab)

    /// Renders `frames` frames back to back without presenting, waiting for the GPU after each
    /// (glFinish), and returns each frame's wall time in milliseconds. RendererLab compares runs with
    /// the pass (`reduceFlashing: true`, the Reduce-flashing envelope) and without it (`false`: the
    /// pass is bypassed, a measurement baseline only; the app always runs the pass, FX-019) to
    /// measure the post-pass cost (T104, FX-019-T22). Pause the display link first.
    public func timedFrames(_ frames: Int, reduceFlashing: Bool) -> [Double] {
        let saved = self.reduceFlashing
        self.reduceFlashing = reduceFlashing
        envelopeBypassed = !reduceFlashing
        defer {
            self.reduceFlashing = saved
            envelopeBypassed = false
        }
        var times: [Double] = []
        times.reserveCapacity(frames)
        for _ in 0..<frames {
            let start = CACurrentMediaTime()
            guard renderFrame(present: false) else { break }
            PMANGLEFinish()
            times.append((CACurrentMediaTime() - start) * 1000)
        }
        return times
    }

    /// The window surface size in pixels (RendererLab reports).
    public var currentSurfaceSizeForLab: (width: Int, height: Int) { surfaceSize }

    // MARK: - Test support

    var isDisplayLinkPaused: Bool? { displayLink?.isPaused }
    var isPresentationSuspended: Bool { presentationSuspended }
    var hasFlashLimiter: Bool { flashLimiter != nil }
    var currentSurfaceSize: (width: Int, height: Int) { surfaceSize }
    var hasWindowSurface: Bool { surface != nil }

    /// Makes the window surface current (tests that issue GL calls directly).
    func makeSurfaceCurrent() {
        guard let surface else { return }
        eglMakeCurrent(display, surface, surface, context)
    }

    /// The envelope's gain of the last frame, or nil while the pass was never created (tests).
    var flashLimiterGain: Float? {
        guard let flashLimiter, let surface else { return nil }
        eglMakeCurrent(display, surface, surface, context)
        return PMFlashLimiterLastGain(flashLimiter)
    }

    /// One frame of a solid gray `value` (encoded) through the renderer's own envelope pass onto the
    /// window surface (not presented), with the current setting; returns the gain, or nil without a
    /// surface or pass. Tests use it for exact levels, which the engine's picture cannot give.
    @discardableResult
    func limitedSolidFrame(_ value: Float, _ frameTime: Double) -> Float? {
        guard !presentationSuspended, let surface else { return nil }
        eglMakeCurrent(display, surface, surface, context)
        guard let limiter = flashLimiterForFrame() else { return nil }
        let framebuffer = PMFlashLimiterBegin(limiter, Int32(surfaceSize.width), Int32(surfaceSize.height))
        guard framebuffer != 0 else { return nil }
        PMANGLEClearFramebuffer(framebuffer, value, value, value)
        var parameters = flashConfiguration.limiterParameters(frameTime: frameTime)
        PMFlashLimiterFinish(limiter, 0, &parameters)
        return PMFlashLimiterLastGain(limiter)
    }

    /// Reads back the default framebuffer of the current surface as RGBA bytes (tests).
    func readPixels() -> [UInt8] {
        guard let surface else { return [] }
        eglMakeCurrent(display, surface, surface, context)
        PMANGLEBindDefaultFramebuffer()
        var pixels = [UInt8](repeating: 0, count: surfaceSize.width * surfaceSize.height * 4)
        let error = PMANGLEReadPixelsRGBA(0, 0, Int32(surfaceSize.width), Int32(surfaceSize.height), &pixels)
        return error == 0 ? pixels : []
    }
}

/// A CAMetalLayer-backed view that reports layout and window changes.
final class MetalLayerView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }
    var metalLayer: CAMetalLayer { layer as! CAMetalLayer }
    var onLayout: (() -> Void)?
    var onWindowChange: ((Bool) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        metalLayer.isOpaque = true
        metalLayer.pixelFormat = .bgra8Unorm
        isOpaque = true
        backgroundColor = .black
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowChange?(window != nil)
    }
}

/// Breaks the CADisplayLink → target retain cycle.
private final class ANGLEDisplayLinkProxy: NSObject {
    weak var renderer: ANGLERenderer?
    init(_ renderer: ANGLERenderer) { self.renderer = renderer }
    @MainActor @objc func fire(_ link: CADisplayLink) { renderer?.displayLinkFired(link) }
}
