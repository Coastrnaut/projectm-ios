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
//
// PERF-011-R7: `stop()` ends the thread and waits until its framebuffer, engine, surface and
// context are destroyed; afterwards the prewarmer is idle and a later request starts a new thread.
// The thread checks for a stop between a preset's load and each of its two frames, so the wait is
// at most one engine call, and an interrupted preset is not recorded as warmed.
import CANGLE
import Foundation
import ProjectMBridge
import Rendering

/// What PresetWarmUpController needs from the warm-up worker (a fake in tests).
protocol PresetWarming: AnyObject, Sendable {
    /// Replaces the queue with `presets` (most likely first) and starts working if idle.
    func request(_ presets: [Preset], texturePaths: [String])
    /// Drops the queue, ends all work and releases the worker's graphics resources. When it
    /// returns, no work is running. The worker can be used again afterwards.
    func stop()
    var warmedCount: Int { get }
    /// PERF-006: the worker holds a thread or graphics resources (context, engine, target) now.
    var holdsGraphicsResources: Bool { get }
}

extension PresetWarming {
    var holdsGraphicsResources: Bool { false }
}

final class PresetPrewarmer: PresetWarming, @unchecked Sendable {
    /// Pipeline descriptors do not depend on the target size, so a small target is enough.
    static let targetSize = 256

    private let display: EGLDisplay
    private let config: EGLConfig
    private let condition = NSCondition()
    private var queue: [Preset] = []
    private var texturePaths: [String] = []
    private var stopping = false
    private var thread: Thread?
    /// The context could not be created; later requests start nothing.
    private var unavailable = false
    /// The warm-up thread holds its EGL context, engine and render target (tests).
    private var holdsContext = false
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
        if thread == nil, !stopping, !unavailable {
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

    /// Drops the queue, stops the thread and waits until its context and engine are gone. The
    /// prewarmer is then idle; a later `request` starts a new thread. Does nothing when idle.
    func stop() {
        condition.lock()
        queue.removeAll()
        if thread != nil {
            stopping = true
            condition.broadcast()
            while thread != nil { condition.wait() }
            stopping = false
        }
        condition.unlock()
    }

    /// The warm-up thread exists.
    var isRunning: Bool {
        condition.lock()
        defer { condition.unlock() }
        return thread != nil
    }

    /// The warm-up thread holds an EGL context, engine and render target.
    var hasGraphicsContext: Bool {
        condition.lock()
        defer { condition.unlock() }
        return holdsContext
    }

    /// PERF-006: a thread, or its context, engine and target, exist.
    var holdsGraphicsResources: Bool {
        condition.lock()
        defer { condition.unlock() }
        return thread != nil || holdsContext
    }

    /// Presets waiting to be warmed.
    var queuedCount: Int {
        condition.lock()
        defer { condition.unlock() }
        return queue.count
    }

    private var shouldStop: Bool {
        condition.lock()
        defer { condition.unlock() }
        return stopping
    }

    private func run() {
        let contextAttributes: [EGLint] = [EGL_CONTEXT_MAJOR_VERSION, 3, EGL_CONTEXT_MINOR_VERSION, 0, EGL_NONE]
        let pbufferAttributes: [EGLint] = [EGL_WIDTH, 1, EGL_HEIGHT, 1, EGL_NONE]
        guard let context = eglCreateContext(display, config, nil, contextAttributes),
              let pbuffer = eglCreatePbufferSurface(display, config, pbufferAttributes) else {
            finish(unavailable: true)
            return
        }
        eglMakeCurrent(display, pbuffer, pbuffer, context)
        setHoldsContext(true)
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
                // Safe points: a stop (PERF-011) leaves after the current engine call.
                if shouldStop { break }
                engine.renderFrame(toFramebuffer: framebuffer)
                if shouldStop { break }
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
        setHoldsContext(false)
        finish(unavailable: false)
    }

    private func setHoldsContext(_ value: Bool) {
        condition.lock()
        holdsContext = value
        condition.unlock()
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

    /// The thread is ending: the prewarmer is idle again (or unavailable for good).
    private func finish(unavailable: Bool) {
        condition.lock()
        if unavailable { self.unavailable = true }
        thread = nil
        condition.broadcast()
        condition.unlock()
    }
}
