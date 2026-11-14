// PresetComparisonRunner.swift — draws two presets in lockstep off screen for the Compare sheet (roadmap PRE-009;
// specs/235-pre-009-preset-comparison, research PRE-009-D2-D6, contract C1, C2).
//
// Built like PresetThumbnailRunner (PRE-001) and PresetPrewarmer:
//
// * One worker thread per session owns two unshared EGL contexts on the renderer's display (one per preview), two
//   fresh engines, two FX-019 flash limiters and two BGRA8 targets of the preview size. Nothing exists between
//   sessions.
// * Lockstep by construction (D2): for every batch the worker records the delivery, feeds the identical samples in
//   identical chunks, pins the identical frame time (`setFrameTime`, PRE-005) and draws A, then does the same for B,
//   then reads both back and reports them together. Ticks that arrive while it draws wait in the mailbox and become
//   the next batch for both (D3), so a slow preview makes both skip display frames together.
// * Each preview passes the flash envelope given at start (the current safety clamp; D6).
// * A preset that fails to load leaves its side out (R11); the other keeps drawing.
// * While the app cannot present frames (PERF-011) nothing starts, and a running session ends at its next batch.
// * The engine is unchanged (Constitution VIII): `addPCMInterleavedStereo`, `setFrameTime`, `renderFrameToFramebuffer`.
import CANGLE
import CFlashLimiter
import Foundation
import ProjectMBridge
import Rendering

final class PresetComparisonRunner: PresetComparing, @unchecked Sendable {
    static let stackSize = 768 * 1024
    /// How long `stop` and a suspension wait for the worker to end.
    static let stopWait: TimeInterval = 1.0

    private let display: EGLDisplay
    private let config: EGLConfig
    private let condition = NSCondition()
    private var busy = false
    private var suspended = false
    private var stopRequested = false
    private var mailbox: PresetComparisonMailbox?
    /// The renderer's texture directories; a configuration's own paths win when it has any.
    private var texturePaths: [String] = []
    /// Tests: records every delivery per side right before that engine is fed (the acceptance instrument).
    var recorder: PresetComparisonRecorder?
    /// Tests: the worker sleeps this long after drawing that side, making it the slow preview.
    var slowSide: (side: PresetComparisonSide, seconds: TimeInterval)?
    /// Batches drawn in the current or last session (tests).
    private(set) var batchesDrawn = 0
    /// Sessions started (tests).
    private(set) var startedCount = 0

    init(display: EGLDisplay, config: EGLConfig) {
        self.display = display
        self.config = config
    }

    // MARK: - PresetComparing

    func start(_ a: Data, _ b: Data, configuration: PresetComparisonConfiguration,
               onEvent: @escaping @Sendable (PresetComparisonEvent) -> Void) -> Bool {
        guard configuration.width > 0, configuration.height > 0 else { return false }
        condition.lock()
        guard !suspended, !busy else {
            condition.unlock()
            return false
        }
        busy = true
        stopRequested = false
        batchesDrawn = 0
        startedCount += 1
        let box = PresetComparisonMailbox()
        mailbox = box
        var configuration = configuration
        if configuration.texturePaths.isEmpty { configuration.texturePaths = texturePaths }
        condition.unlock()
        let thread = Thread { [self] in
            let reason = work([a, b], configuration: configuration, mailbox: box, onEvent: onEvent)
            condition.lock()
            busy = false
            if mailbox === box { mailbox = nil }
            condition.broadcast()
            condition.unlock()
            if let reason { onEvent(.stopped(reason)) }
        }
        thread.name = "projectM preset comparison"
        thread.stackSize = Self.stackSize
        thread.qualityOfService = .userInitiated
        thread.start()
        return true
    }

    func submit(_ tick: PresetComparisonTick) {
        condition.lock()
        mailbox?.post(tick)
        condition.broadcast()
        condition.unlock()
    }

    func stop() {
        condition.lock()
        stopRequested = true
        condition.broadcast()
        waitForWorkerLocked()
        condition.unlock()
    }

    // MARK: - Renderer hooks

    func setTexturePaths(_ paths: [String]) {
        condition.lock()
        texturePaths = paths
        condition.unlock()
    }

    /// PERF-011: no session while the app cannot present frames; a running one ends at its next batch.
    func setSuspended(_ value: Bool) {
        condition.lock()
        suspended = value
        if value {
            stopRequested = true
            condition.broadcast()
            waitForWorkerLocked()
        }
        condition.unlock()
    }

    var isBusy: Bool {
        condition.lock()
        defer { condition.unlock() }
        return busy
    }

    /// Waits (with the lock held) until the worker ended or `stopWait` passed.
    private func waitForWorkerLocked() {
        let deadline = Date().addingTimeInterval(Self.stopWait)
        while busy {
            if !condition.wait(until: deadline) { break }
        }
    }

    // MARK: - The worker thread

    /// One preview's GPU objects.
    private struct Lane {
        let side: PresetComparisonSide
        var context: EGLContext?
        var surface: EGLSurface?
        var engine: ProjectMEngine?
        var limiter: OpaquePointer?
        var framebuffer: UInt32 = 0
        var texture: UInt32 = 0
        var ready = false
    }

    /// Runs one session; returns why it ended when that was not `stop()`.
    private func work(_ presets: [Data], configuration: PresetComparisonConfiguration, mailbox: PresetComparisonMailbox,
                      onEvent: @escaping @Sendable (PresetComparisonEvent) -> Void) -> String? {
        var lanes: [Lane] = PresetComparisonSide.allCases.map { (side: PresetComparisonSide) -> Lane in Lane(side: side) }
        defer {
            for index in lanes.indices { release(&lanes[index]) }
            eglMakeCurrent(display, nil, nil, nil)
        }
        for index in lanes.indices {
            if let message = prepare(&lanes[index], preset: presets[index], configuration: configuration) {
                onEvent(.failed(lanes[index].side, message))
            } else {
                onEvent(.loaded(lanes[index].side))
            }
        }
        guard lanes.contains(where: { (lane: Lane) -> Bool in lane.ready }) else { return nil }
        var previousLastTick = -1
        while true {
            condition.lock()
            while !stopRequested && mailbox.isEmpty {
                _ = condition.wait(until: Date().addingTimeInterval(0.5))
            }
            let stopping = stopRequested
            let suspendedNow = suspended
            condition.unlock()
            if stopping { return suspendedNow ? "The app left the screen." : nil }
            guard let batch = mailbox.take() else { continue }
            let firstPrevious = previousLastTick < 0 ? batch.firstTick - 1 : previousLastTick
            let duration = Double(max(1, batch.lastTick - firstPrevious)) / configuration.rate
            previousLastTick = batch.lastTick
            let delivery = PresetComparisonDelivery(batch)
            var pictures: [Data?] = [nil, nil]
            for index in lanes.indices where lanes[index].ready {
                pictures[index] = draw(lanes[index], batch: batch, delivery: delivery, duration: duration, configuration: configuration)
                if let slow = slowSide, slow.side == lanes[index].side { Thread.sleep(forTimeInterval: slow.seconds) }
            }
            condition.lock()
            batchesDrawn += 1
            condition.unlock()
            onEvent(.frame(PresetComparisonFrame(width: configuration.width, height: configuration.height,
                                                 a: pictures[0], b: pictures[1], delivery: delivery)))
        }
    }

    /// Creates the lane's context, engine, limiter and target and loads its preset; returns a failure message.
    private func prepare(_ lane: inout Lane, preset: Data, configuration: PresetComparisonConfiguration) -> String? {
        let contextAttributes: [EGLint] = [EGL_CONTEXT_MAJOR_VERSION, 3, EGL_CONTEXT_MINOR_VERSION, 0, EGL_NONE]
        let pbufferAttributes: [EGLint] = [EGL_WIDTH, 1, EGL_HEIGHT, 1, EGL_NONE]
        guard let context = eglCreateContext(display, config, nil, contextAttributes) else { return "No drawing context." }
        lane.context = context
        guard let surface = eglCreatePbufferSurface(display, config, pbufferAttributes) else { return "No drawing surface." }
        lane.surface = surface
        eglMakeCurrent(display, surface, surface, context)
        guard let engine = try? ProjectMEngine(glLoader: PMANGLELoadProc, userData: nil) else { return "No engine." }
        lane.engine = engine
        engine.setViewportWidth(configuration.width, height: configuration.height)
        engine.setTextureSearchPaths(configuration.texturePaths)
        lane.framebuffer = PMANGLECreateBGRAFramebuffer(Int32(configuration.width), Int32(configuration.height), &lane.texture)
        guard lane.framebuffer != 0 else { return "No drawing target." }
        lane.limiter = PMFlashLimiterCreate(PMANGLELoadProc, nil)
        guard lane.limiter != nil else { return "No flash limiter." }   // R9: never draw without the envelope
        do {
            try engine.loadPresetData(preset, smooth: false)
        } catch {
            let message = (error as NSError).localizedDescription
            return message.isEmpty ? "The preset could not be loaded." : message
        }
        lane.ready = true
        return nil
    }

    /// Feeds one batch to one lane and draws it; returns the picture (RGBA, top row first).
    private func draw(_ lane: Lane, batch: PresetComparisonBatch, delivery: PresetComparisonDelivery, duration: Double,
                      configuration: PresetComparisonConfiguration) -> Data? {
        guard let engine = lane.engine, let context = lane.context, let surface = lane.surface, let limiter = lane.limiter else { return nil }
        eglMakeCurrent(display, surface, surface, context)
        recorder?.record(delivery, side: lane.side)   // the instrument: what this engine is about to receive
        let limit = Int(ProjectMEngine.maxSamplesPerFrame)
        batch.samples.withUnsafeBufferPointer { (buffer: UnsafeBufferPointer<Float>) in
            guard let base = buffer.baseAddress else { return }
            var offset = 0
            let frames = batch.frameCount
            while offset < frames {
                let count = min(limit, frames - offset)
                engine.addPCMInterleavedStereo(base.advanced(by: offset * 2), frames: UInt(count))
                offset += count
            }
        }
        engine.setFrameTime(batch.frameTime)   // the shared timeline's time, identical for both engines
        let scene = PMFlashLimiterBegin(limiter, Int32(configuration.width), Int32(configuration.height))
        guard scene != 0 else { return nil }   // R9: no envelope, no picture
        engine.renderFrame(toFramebuffer: scene)
        var parameters = configuration.flash.limiterParameters(frameTime: duration)
        PMFlashLimiterFinish(limiter, lane.framebuffer, &parameters)
        return PresetThumbnailRunner.readBack(lane.framebuffer, width: configuration.width, height: configuration.height)
    }

    private func release(_ lane: inout Lane) {
        guard let context = lane.context else { return }
        if let surface = lane.surface { eglMakeCurrent(display, surface, surface, context) }
        PMFlashLimiterDestroy(lane.limiter)
        lane.limiter = nil
        if lane.framebuffer != 0 { PMANGLEDeleteFramebuffer(lane.framebuffer, lane.texture) }
        lane.framebuffer = 0
        lane.engine = nil   // destroyed while its context is current (bridge guarantee 3)
        eglMakeCurrent(display, nil, nil, nil)
        if let surface = lane.surface { eglDestroySurface(display, surface) }
        eglDestroyContext(display, context)
        lane.surface = nil
        lane.context = nil
    }
}
