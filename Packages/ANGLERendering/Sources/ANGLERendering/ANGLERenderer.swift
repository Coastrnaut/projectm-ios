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
// * Everything runs on the main thread, the engine's render thread.
import AudioCore
import CANGLE
import Foundation
import ProjectMBridge
import QuartzCore
import Rendering
import UIKit

public enum ANGLERendererError: Error, Equatable {
    case displayUnavailable(Int32)
    case noConfig(Int32)
    case contextUnavailable(Int32)
    case surfaceUnavailable(Int32)
}

@MainActor
public final class ANGLERenderer: NSObject, VisualizerRenderer {
    public var view: UIView { layerView }
    public private(set) var metrics = RenderMetrics.zero
    /// FR-072; see GLESRenderer.reduceFlashing.
    public var reduceFlashing = false

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
    private var observers: [NSObjectProtocol] = []

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
        super.init()
        layerView.onLayout = { [weak self] in self?.layoutSurface() }
        layerView.onWindowChange = { [weak self] inWindow in
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
        displayLink?.invalidate()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        eglMakeCurrent(display, placeholder, placeholder, context)
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
        try engine.loadPreset(atPath: preset.fileURL.path, smooth: true)
    }

    public func pause() {
        paused = true
        displayLink?.isPaused = true
        meter.reset()
    }

    public func resume() {
        paused = false
        displayLink?.isPaused = false
    }

    // MARK: - Frames

    /// Renders one frame; with `present`, swaps it onto the layer. Returns false with no surface.
    @discardableResult
    func renderFrame(present: Bool = true) -> Bool {
        guard let engine, let surface else { return false }
        eglMakeCurrent(display, surface, surface, context)
        if let reader {
            let frames = reader.read(into: pcm, maxFrames: maxFrames)
            if frames > 0 {
                engine.addPCMInterleavedStereo(pcm, frames: UInt(frames))
            }
        }
        engine.renderFrame(toFramebuffer: 0)
        if present { eglSwapBuffers(display, surface) }
        return true
    }

    @objc fileprivate func displayLinkFired(_ link: CADisplayLink) {
        guard renderFrame() else { return }
        if meter.record(presentedAt: link.timestamp) {
            metrics = meter.metrics
        }
    }

    private func makeCurrent() {
        let target = surface ?? placeholder
        eglMakeCurrent(display, target, target, context)
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
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

    private func frameRateRange() -> CAFrameRateRange {
        let info = ProcessInfo.processInfo
        let constrained = info.isLowPowerModeEnabled || info.thermalState == .serious || info.thermalState == .critical
        return constrained ? CAFrameRateRange(minimum: 30, maximum: 30, preferred: 30)
                           : CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
    }

    private func observeFrameRatePressure() {
        let center = NotificationCenter.default
        for name in [ProcessInfo.thermalStateDidChangeNotification, Notification.Name.NSProcessInfoPowerStateDidChange] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, let link = self.displayLink else { return }
                    link.preferredFrameRateRange = self.frameRateRange()
                }
            })
        }
    }

    // MARK: - Surface

    private func layoutSurface() {
        let scale = layerView.traitCollection.displayScale > 0 ? layerView.traitCollection.displayScale : 2
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

    // MARK: - Test support

    var isDisplayLinkPaused: Bool? { displayLink?.isPaused }
    var currentSurfaceSize: (width: Int, height: Int) { surfaceSize }
    var hasWindowSurface: Bool { surface != nil }

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
