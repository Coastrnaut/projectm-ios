// GLESRenderer.swift — ADR-0003 Option A: the engine on Apple's OpenGL ES 3.0 (task T071).
//
// * A UIView backed by CAEAGLLayer, an OpenGL ES 3 EAGLContext, and one framebuffer whose color
//   renderbuffer is the layer's drawable (resized with the view at the display scale).
// * The engine resolves GL functions through PMAppleGLESLoadProc, a static table of the linked
//   OpenGL ES 3.0 functions (no dlsym; Constitution I).
// * A CADisplayLink drives frames at up to 60 fps (30-60 range). Under Low Power Mode or serious
//   thermal pressure it asks for 30 fps (FR-049: never below 30).
// * Each frame reads the NormalizedPCMReader once, up to the engine's maxSamplesPerFrame, adds those
//   frames, renders, and presents. An empty reader adds nothing (R-06 underrun policy).
// * Threading: everything runs on the main thread, which is the engine's render thread (the bridge
//   asserts that its creating thread is used). Moving rendering to its own thread is an ADR-0003
//   decision once the device measurements (T075) are in.
import AudioCore
import Foundation
import OpenGLES
import ProjectMBridge
import QuartzCore
import UIKit

public enum RendererError: Error, Equatable {
    case contextUnavailable
    case framebufferIncomplete(UInt32)
}

@MainActor
public final class GLESRenderer: NSObject, VisualizerRenderer {
    public var view: UIView { layerView }
    public private(set) var metrics = RenderMetrics.zero
    public private(set) var presentedFrameCount = 0
    /// FR-072. Stored only: the Reduce-flashing post-pass (T104) is in ANGLERenderer, the renderer
    /// ADR-0003 chose. This renderer is the fallback when no EGL context can be created.
    public var reduceFlashing = false

    private let layerView: GLESLayerView
    private let context: EAGLContext
    private var engine: ProjectMEngine?
    private var framebuffer: GLuint = 0
    private var colorRenderbuffer: GLuint = 0
    private var drawableSize = (width: GLint(0), height: GLint(0))
    private var displayLink: CADisplayLink?
    private var reader: (any NormalizedPCMReader)?
    private let pcm: UnsafeMutablePointer<Float>
    private let maxFrames: Int
    private var meter = FrameRateMeter()
    private var paused = false
    private var observers: [NSObjectProtocol] = []

    private init(context: EAGLContext, engine: ProjectMEngine) {
        self.context = context
        self.engine = engine
        maxFrames = Int(ProjectMEngine.maxSamplesPerFrame)
        pcm = UnsafeMutablePointer<Float>.allocate(capacity: maxFrames * 2)
        pcm.initialize(repeating: 0, count: maxFrames * 2)
        layerView = GLESLayerView(frame: .zero)
        super.init()
        layerView.onLayout = { [weak self] in self?.layoutDrawable() }
        layerView.onWindowChange = { [weak self] inWindow in
            inWindow ? self?.startDisplayLink() : self?.stopDisplayLink()
        }
        observeFrameRatePressure()
    }

    /// Creates a renderer with its own OpenGL ES 3 context and engine. The display link starts when
    /// the view joins a window and stops when it leaves.
    public static func make() throws -> GLESRenderer {
        guard let context = EAGLContext(api: .openGLES3) else { throw RendererError.contextUnavailable }
        guard EAGLContext.setCurrent(context) else { throw RendererError.contextUnavailable }
        let engine = try ProjectMEngine(glLoader: PMAppleGLESLoadProc, userData: nil)
        engine.softCutDuration = presetBlendSeconds   // FR-043 / T091: blend at most 2 s
        return GLESRenderer(context: context, engine: engine)
    }

    isolated deinit {
        displayLink?.invalidate()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        EAGLContext.setCurrent(context)
        engine = nil   // destroyed while its context is current (bridge guarantee 3)
        deleteFramebuffer()
        EAGLContext.setCurrent(nil)
        pcm.deinitialize(count: maxFrames * 2)
        pcm.deallocate()
    }

    // MARK: - VisualizerRenderer

    public func attach(pcm reader: any NormalizedPCMReader) {
        self.reader = reader
    }

    public func setPreset(_ preset: Preset) async throws {
        guard let engine else { return }
        EAGLContext.setCurrent(context)
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

    /// Renders and presents one frame. Returns false when there is no drawable yet.
    @discardableResult
    func renderFrame() -> Bool {
        guard let engine, framebuffer != 0 else { return false }
        EAGLContext.setCurrent(context)
        if let reader {
            let frames = reader.read(into: pcm, maxFrames: maxFrames)
            if frames > 0 {
                engine.addPCMInterleavedStereo(pcm, frames: UInt(frames))
            }
        }
        engine.renderFrame(toFramebuffer: UInt32(framebuffer))
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), colorRenderbuffer)
        context.presentRenderbuffer(Int(GL_RENDERBUFFER))
        presentedFrameCount += 1
        return true
    }

    @objc fileprivate func displayLinkFired(_ link: CADisplayLink) {
        guard renderFrame() else { return }
        if meter.record(presentedAt: link.timestamp) {
            metrics = meter.metrics
        }
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: DisplayLinkProxy(self), selector: #selector(DisplayLinkProxy.fire(_:)))
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

    /// FR-049: 60 fps normally; 30 under Low Power Mode or serious/critical thermal state.
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

    // MARK: - Drawable

    private func layoutDrawable() {
        let displayScale = layerView.traitCollection.displayScale > 0 ? layerView.traitCollection.displayScale : 2
        let scale = displayScale * quality.renderScale   // FR-049: lower render scale when critical
        layerView.contentScaleFactor = scale
        let width = GLint((layerView.bounds.width * scale).rounded())
        let height = GLint((layerView.bounds.height * scale).rounded())
        guard width > 0, height > 0, (width, height) != drawableSize else { return }
        EAGLContext.setCurrent(context)
        deleteFramebuffer()
        do {
            try createFramebuffer()
            engine?.setViewportWidth(Int(drawableSize.width), height: Int(drawableSize.height))
        } catch {
            deleteFramebuffer()
        }
    }

    private func createFramebuffer() throws {
        glGenFramebuffers(1, &framebuffer)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), framebuffer)
        glGenRenderbuffers(1, &colorRenderbuffer)
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), colorRenderbuffer)
        context.renderbufferStorage(Int(GL_RENDERBUFFER), from: layerView.eaglLayer)
        glFramebufferRenderbuffer(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_RENDERBUFFER), colorRenderbuffer)
        var width: GLint = 0
        var height: GLint = 0
        glGetRenderbufferParameteriv(GLenum(GL_RENDERBUFFER), GLenum(GL_RENDERBUFFER_WIDTH), &width)
        glGetRenderbufferParameteriv(GLenum(GL_RENDERBUFFER), GLenum(GL_RENDERBUFFER_HEIGHT), &height)
        let status = glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER))
        guard status == GLenum(GL_FRAMEBUFFER_COMPLETE), width > 0, height > 0 else {
            throw RendererError.framebufferIncomplete(status)
        }
        drawableSize = (width, height)
    }

    private func deleteFramebuffer() {
        if colorRenderbuffer != 0 { glDeleteRenderbuffers(1, &colorRenderbuffer) }
        if framebuffer != 0 { glDeleteFramebuffers(1, &framebuffer) }
        colorRenderbuffer = 0
        framebuffer = 0
        drawableSize = (0, 0)
    }

    // MARK: - Test support

    var isDisplayLinkPaused: Bool? { displayLink?.isPaused }
    var currentDrawableSize: (width: Int, height: Int) { (Int(drawableSize.width), Int(drawableSize.height)) }

    /// Reads back the framebuffer as RGBA bytes (tests).
    func readPixels() -> [UInt8] {
        guard framebuffer != 0 else { return [] }
        EAGLContext.setCurrent(context)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), framebuffer)
        var pixels = [UInt8](repeating: 0, count: Int(drawableSize.width * drawableSize.height) * 4)
        glReadPixels(0, 0, drawableSize.width, drawableSize.height, GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), &pixels)
        return pixels
    }
}

/// A CAEAGLLayer-backed view that reports layout and window changes to its renderer.
final class GLESLayerView: UIView {
    override class var layerClass: AnyClass { CAEAGLLayer.self }
    var eaglLayer: CAEAGLLayer { layer as! CAEAGLLayer }
    var onLayout: (() -> Void)?
    var onWindowChange: ((Bool) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        eaglLayer.isOpaque = true
        eaglLayer.drawableProperties = [
            kEAGLDrawablePropertyRetainedBacking: false,
            kEAGLDrawablePropertyColorFormat: kEAGLColorFormatRGBA8,
        ]
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
private final class DisplayLinkProxy: NSObject {
    weak var renderer: GLESRenderer?
    init(_ renderer: GLESRenderer) { self.renderer = renderer }
    @MainActor @objc func fire(_ link: CADisplayLink) { renderer?.displayLinkFired(link) }
}
