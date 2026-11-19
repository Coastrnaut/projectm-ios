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
// PERF-011-R7: `stop()` asks the thread to end and returns at once; it never waits. The thread
// checks for a stop between a preset's load and each of its two frames, then destroys its
// framebuffer, engine, surface and context itself; an interrupted preset is not recorded as warmed.
// A request made while the thread is still ending is kept and starts a new thread when it has ended.
// QA-011 device run 2026-11-19 (D2, D3): the old `stop()` waited for that safe point on the main
// thread, but an engine call that began just before the app went to the background blocked inside
// ANGLE in `-[MTLCommandBuffer waitUntilCompleted]` (the GPU does not run a background app's work),
// so the main thread waited for good (spindump: LifecycleCoordinator.handle → setCanPresent(false) →
// PresetWarmUpController.suspendForPresentationLoss → PresetPrewarmer.stop → NSCondition.wait).
// The display is never terminated, so the ending thread can always release what it made.
import CANGLE
import Foundation
import ProjectMBridge
import Rendering

/// What PresetWarmUpController needs from the warm-up worker (a fake in tests).
protocol PresetWarming: AnyObject, Sendable {
    /// Replaces the queue with `presets` (most likely first) and starts working if idle.
    func request(_ presets: [Preset], texturePaths: [String])
    /// Drops the queue and asks all work to end; the worker then releases its graphics resources
    /// by itself. Never waits (QA-011: the main thread calls it). The worker can be used again at once.
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
    private var startedThreads = 0

    init(display: EGLDisplay, config: EGLConfig) {
        self.display = display
        self.config = config
    }

    /// Replaces the queue with `presets` (most likely first).
    func request(_ presets: [Preset], texturePaths: [String]) {
        condition.lock()
        queue = presets
        self.texturePaths = texturePaths
        // While a stopped thread is still ending, the request waits in the queue: `finish` starts
        // the next thread.
        if thread == nil, !unavailable { startThread() }
        condition.signal()
        condition.unlock()
    }

    /// With the lock held.
    private func startThread() {
        let thread = Thread { [self] in run() }
        thread.name = "projectM preset warm-up"
        thread.qualityOfService = .utility
        self.thread = thread
        startedThreads += 1
        thread.start()
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

    /// Drops the queue and asks the thread to end at its next safe point; returns at once (file
    /// header, QA-011). The thread then destroys its context, engine and target. Does nothing when idle.
    func stop() {
        condition.lock()
        queue.removeAll()
        if thread != nil {
            stopping = true
            condition.broadcast()
        }
        condition.unlock()
    }

    /// Tests only, never the main thread of the app: waits until no thread exists (a stopped thread
    /// has released its context, engine and target), at most `timeout`. True when idle.
    func waitUntilIdle(timeout: TimeInterval) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        condition.lock()
        defer { condition.unlock() }
        while thread != nil {
            if !condition.wait(until: deadline) { return thread == nil }
        }
        return true
    }

    /// Threads started so far (tests: a request during a stop starts one thread after it ends).
    var threadStarts: Int {
        condition.lock()
        defer { condition.unlock() }
        return startedThreads
    }

    #if DEBUG
    /// Tests: called on the warm-up thread after a preset's load, before the stop check (an engine
    /// call that does not return, as on device when the GPU does not run a background app's work).
    var afterLoadForTesting: (@Sendable () -> Void)?
    #endif

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
                #if DEBUG
                afterLoadForTesting?()
                #endif
                // Safe points: a stop (PERF-011) leaves after the current engine call.
                if shouldStop { break }
                engine.renderFrame(toFramebuffer: framebuffer)
                if shouldStop { break }
                engine.renderFrame(toFramebuffer: framebuffer)
                PMANGLEFinish()
                if shouldStop { break }   // stopped during the frames: not recorded
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

    /// The thread is ending: the prewarmer is idle again (or unavailable for good). A request made
    /// while it was stopping starts the next thread now.
    private func finish(unavailable: Bool) {
        condition.lock()
        if unavailable { self.unavailable = true }
        thread = nil
        let restart = stopping && !queue.isEmpty && !self.unavailable
        stopping = false
        if restart { startThread() }
        condition.broadcast()
        condition.unlock()
    }
}
