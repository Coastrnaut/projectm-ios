// PresetPrewarmer.swift — builds the GPU pipelines of upcoming presets in the background (feature
// 002 SC-104).
//
// On ANGLE's Metal backend, a preset's first frame waits while Metal pipelines are created for its
// shaders. For the heaviest presets that takes about a second, during which nothing is presented.
// This class renders each upcoming preset twice on its own thread. It uses a second, unshared EGL
// context on the same display, its own engine instance, and a small BGRA8 framebuffer (the window
// surface's format). ANGLE's in-memory Metal library cache and Metal's own pipeline cache then hold
// the compiled shaders, so the visible engine's switch to that preset no longer compiles them.
//
// The work runs at utility priority. Every engine and GL call stays on the warm-up thread, and the
// context is created and destroyed there. A new request replaces the queue; presets already warmed
// are skipped.
import CANGLE
import Foundation
import ProjectMBridge
import Rendering

final class PresetPrewarmer: @unchecked Sendable {
    /// Pipeline descriptors do not depend on the target size, so a small target is enough.
    static let targetSize = 256

    private let display: EGLDisplay
    private let config: EGLConfig
    private let condition = NSCondition()
    private var queue: [Preset] = []
    private var texturePaths: [String] = []
    private var stopping = false
    private var thread: Thread?
    private var done = false
    /// Presets warmed so far (tests and automation reports).
    private var warmedIDs: Set<String> = []

    init(display: EGLDisplay, config: EGLConfig) {
        self.display = display
        self.config = config
    }

    /// Replaces the queue with `presets` (most likely first).
    func request(_ presets: [Preset], texturePaths: [String]) {
        condition.lock()
        queue = presets
        self.texturePaths = texturePaths
        if thread == nil, !stopping {
            let thread = Thread { [self] in run() }
            thread.name = "projectM preset warm-up"
            thread.qualityOfService = .utility
            self.thread = thread
            thread.start()
        }
        condition.signal()
        condition.unlock()
    }

    var warmedCount: Int {
        condition.lock()
        defer { condition.unlock() }
        return warmedIDs.count
    }

    func isWarmed(_ id: String) -> Bool {
        condition.lock()
        defer { condition.unlock() }
        return warmedIDs.contains(id)
    }

    /// Stops the thread and waits until its context and engine are gone.
    func stop() {
        condition.lock()
        stopping = true
        condition.signal()
        while thread != nil, !done { condition.wait() }
        condition.unlock()
    }

    private func run() {
        let contextAttributes: [EGLint] = [EGL_CONTEXT_MAJOR_VERSION, 3, EGL_CONTEXT_MINOR_VERSION, 0, EGL_NONE]
        let pbufferAttributes: [EGLint] = [EGL_WIDTH, 1, EGL_HEIGHT, 1, EGL_NONE]
        guard let context = eglCreateContext(display, config, nil, contextAttributes),
              let pbuffer = eglCreatePbufferSurface(display, config, pbufferAttributes) else {
            finish()
            return
        }
        eglMakeCurrent(display, pbuffer, pbuffer, context)
        var engine = try? ProjectMEngine(glLoader: PMANGLELoadProc, userData: nil)
        engine?.setViewportWidth(Self.targetSize, height: Self.targetSize)
        var texture: UInt32 = 0
        let framebuffer = PMANGLECreateBGRAFramebuffer(Int32(Self.targetSize), Int32(Self.targetSize), &texture)
        var appliedPaths: [String] = []

        while let (preset, paths) = next() {
            guard let engine, framebuffer != 0 else { continue }
            if paths != appliedPaths {
                engine.setTextureSearchPaths(paths)
                appliedPaths = paths
            }
            do {
                if let data = preset.data {
                    try engine.loadPresetData(data, smooth: false)
                } else {
                    try engine.loadPreset(atPath: preset.fileURL.path, smooth: false)
                }
                engine.renderFrame(toFramebuffer: framebuffer)
                engine.renderFrame(toFramebuffer: framebuffer)
                PMANGLEFinish()
            } catch {
                // A preset that fails here fails for the visible engine too; that path reports it.
            }
            condition.lock()
            warmedIDs.insert(preset.id)
            condition.unlock()
        }

        PMANGLEDeleteFramebuffer(framebuffer, texture)
        engine = nil   // destroyed while its context is current (bridge guarantee 3)
        eglMakeCurrent(display, nil, nil, nil)
        eglDestroySurface(display, pbuffer)
        eglDestroyContext(display, context)
        finish()
    }

    /// The next preset not yet warmed, or nil when stopping.
    private func next() -> (Preset, [String])? {
        condition.lock()
        defer { condition.unlock() }
        while true {
            if stopping { return nil }
            while let preset = queue.first {
                queue.removeFirst()
                if !warmedIDs.contains(preset.id) { return (preset, texturePaths) }
            }
            condition.wait()
        }
    }

    private func finish() {
        condition.lock()
        done = true
        condition.broadcast()
        condition.unlock()
    }
}
