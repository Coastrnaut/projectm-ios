// PresetTrialRunner.swift — tries an untrusted preset off screen before it may be played
// (roadmap PRE-012; PRE-012-R14-R16, R21).
//
// A preset the user imported has passed static validation, but only the engine can tell whether
// it loads and draws. This class finds out without the visible picture being involved:
//
// * Each trial runs on its own thread, with its own unshared EGL context on the renderer's
//   display, a fresh engine instance and a small BGRA8 target (the way PresetPrewarmer warms
//   presets). The engine is created for the trial and destroyed after it, so trials cannot affect
//   each other or the visible engine.
// * The thread's stack is 512 KiB. The visible engine runs on the main thread, whose stack is
//   1 MiB, so recursion in the engine (its equation and shader compilers recurse on expression
//   depth) that fits here fits there.
// * The trial loads the preset (which compiles its equations and shaders and runs its init code),
//   then draws `frames` frames with a test tone as audio, then waits for the GPU.
// * `run` returns when the trial ends or when `timeout` passes, whichever is first. A thread
//   cannot be stopped from outside: after a timeout the thread is abandoned. It ends by itself if
//   the engine ever returns; until then this runner answers `unavailable`, so at most one
//   abandoned thread exists per renderer.
// * While the app cannot present frames (PERF-011) nothing is tried: a running trial stops at its
//   next safe point (between the load and each frame) and reports `unavailable`.
//
// What this cannot contain: a native crash inside the engine or ANGLE during a trial ends the
// process. `UserPresetLibrary` writes a record before every trial so that the next launch
// quarantines that preset instead of trying it again.
import CANGLE
import Foundation
import ProjectMBridge
import Rendering

final class PresetTrialRunner: PresetTrialing, @unchecked Sendable {
    static let targetSize = 256
    static let stackSize = 768 * 1024
    /// Frames drawn after the load (PresetImportLimits.trialFrames in the app's library).
    static let frames = 30
    /// How long a suspension waits for a running trial to reach a safe point.
    static let suspendWait: TimeInterval = 1.0

    private let display: EGLDisplay
    private let config: EGLConfig
    private let condition = NSCondition()
    private var busy = false
    private var suspended = false
    private var texturePaths: [String] = []
    private var current: Attempt?

    init(display: EGLDisplay, config: EGLConfig) {
        self.display = display
        self.config = config
    }

    /// One trial: answers exactly once, whoever gets there first (the thread, the timeout or a
    /// suspension).
    private final class Attempt: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<PresetTrialOutcome, Never>?
        private var cancelFlag = false

        init(_ continuation: CheckedContinuation<PresetTrialOutcome, Never>) { self.continuation = continuation }

        func finish(_ outcome: PresetTrialOutcome) {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(returning: outcome)
        }

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelFlag
        }

        func cancel() {
            lock.lock()
            cancelFlag = true
            lock.unlock()
        }
    }

    // MARK: - PresetTrialing

    func run(_ contents: Data, timeout: Duration) async -> PresetTrialOutcome {
        await withCheckedContinuation { continuation in
            let attempt = Attempt(continuation)
            condition.lock()
            if suspended {
                condition.unlock()
                attempt.finish(.unavailable("The app is not on screen."))
                return
            }
            if busy {
                condition.unlock()
                attempt.finish(.unavailable("An earlier check has not finished."))
                return
            }
            busy = true
            current = attempt
            let paths = texturePaths
            condition.unlock()

            let thread = Thread { [self] in
                let outcome = work(contents, texturePaths: paths, attempt: attempt)
                condition.lock()
                busy = false
                if current === attempt { current = nil }
                condition.broadcast()
                condition.unlock()
                attempt.finish(outcome)
            }
            thread.name = "projectM preset trial"
            thread.stackSize = Self.stackSize
            thread.qualityOfService = .userInitiated
            thread.start()

            let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + max(seconds, 0)) {
                attempt.finish(.timedOut)   // a no-op when the trial already answered
            }
        }
    }

    // MARK: - Renderer hooks

    func setTexturePaths(_ paths: [String]) {
        condition.lock()
        texturePaths = paths
        condition.unlock()
    }

    /// PERF-011: no trial runs while the app cannot present frames. Suspending asks a running
    /// trial to stop at its next safe point and waits briefly for it; a trial that does not stop
    /// (it is inside the engine) is answered `unavailable` and left to end by itself.
    func setSuspended(_ value: Bool) {
        condition.lock()
        suspended = value
        guard value, let attempt = current else {
            condition.unlock()
            return
        }
        attempt.cancel()
        let deadline = Date().addingTimeInterval(Self.suspendWait)
        while busy && current === attempt {
            if !condition.wait(until: deadline) { break }
        }
        condition.unlock()
        attempt.finish(.unavailable("The app left the screen during the check."))
    }

    /// A trial's thread exists (a running trial, or one abandoned after a timeout).
    var isBusy: Bool {
        condition.lock()
        defer { condition.unlock() }
        return busy
    }

    // MARK: - The trial thread

    private func work(_ contents: Data, texturePaths: [String], attempt: Attempt) -> PresetTrialOutcome {
        let contextAttributes: [EGLint] = [EGL_CONTEXT_MAJOR_VERSION, 3, EGL_CONTEXT_MINOR_VERSION, 0, EGL_NONE]
        let pbufferAttributes: [EGLint] = [EGL_WIDTH, 1, EGL_HEIGHT, 1, EGL_NONE]
        guard let context = eglCreateContext(display, config, nil, contextAttributes) else {
            return .unavailable("No drawing context for the check.")
        }
        guard let pbuffer = eglCreatePbufferSurface(display, config, pbufferAttributes) else {
            eglDestroyContext(display, context)
            return .unavailable("No drawing surface for the check.")
        }
        eglMakeCurrent(display, pbuffer, pbuffer, context)
        var outcome = PresetTrialOutcome.passed
        var engine: ProjectMEngine?
        var texture: UInt32 = 0
        var framebuffer: UInt32 = 0
        do {
            let created = try ProjectMEngine(glLoader: PMANGLELoadProc, userData: nil)
            engine = created
            created.setViewportWidth(Self.targetSize, height: Self.targetSize)
            framebuffer = PMANGLECreateBGRAFramebuffer(Int32(Self.targetSize), Int32(Self.targetSize), &texture)
            if framebuffer == 0 {
                outcome = .unavailable("No drawing target for the check.")
            } else {
                created.setTextureSearchPaths(texturePaths)
            }
        } catch {
            outcome = .unavailable("No engine for the check.")
        }

        if outcome == .passed, let engine {
            if attempt.isCancelled {
                outcome = .unavailable("The check was stopped.")
            } else {
                do {
                    // Compiles the equations and shaders and runs the init code.
                    try engine.loadPresetData(contents, smooth: false)
                } catch {
                    let message = (error as NSError).localizedDescription
                    outcome = .failed(message.isEmpty ? "The preset could not be loaded" : message)
                }
            }
        }
        if outcome == .passed, let engine {
            let framesPerCall = min(735, Int(ProjectMEngine.maxSamplesPerFrame))   // 1/60 s at 44.1 kHz
            var tone = [Float](repeating: 0, count: framesPerCall * 2)
            var phase: Float = 0
            let step = 2 * Float.pi * 440 / 44_100
            for _ in 0..<Self.frames {
                if attempt.isCancelled {
                    outcome = .unavailable("The check was stopped.")
                    break
                }
                for index in 0..<framesPerCall {
                    let sample = 0.5 * sin(phase)
                    tone[index * 2] = sample
                    tone[index * 2 + 1] = sample
                    phase += step
                    if phase > 2 * .pi { phase -= 2 * .pi }
                }
                tone.withUnsafeBufferPointer { engine.addPCMInterleavedStereo($0.baseAddress!, frames: UInt(framesPerCall)) }
                engine.renderFrame(toFramebuffer: framebuffer)
            }
            PMANGLEFinish()
        }

        if framebuffer != 0 { PMANGLEDeleteFramebuffer(framebuffer, texture) }
        engine = nil   // destroyed while its context is current (bridge guarantee 3)
        eglMakeCurrent(display, nil, nil, nil)
        eglDestroySurface(display, pbuffer)
        eglDestroyContext(display, context)
        return outcome
    }
}
