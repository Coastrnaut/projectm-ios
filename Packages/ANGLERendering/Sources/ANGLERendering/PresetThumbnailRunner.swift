// PresetThumbnailRunner.swift — draws a preset off screen into a small picture for the browser's
// thumbnails (roadmap PRE-001; research PRE-001-D1; contract thumbnail-cache.md C4).
//
// Built like PresetTrialRunner (PRE-012), the proven pattern of PresetPrewarmer:
//
// * Each drawing runs on its own thread at utility priority, with its own unshared EGL context on
//   the renderer's display, a fresh engine and a BGRA8 target of the thumbnail's size (the window
//   surface's format, so the drawing also leaves the preset's Metal pipelines in the cache).
// * It loads the preset, then for every block of audio feeds it and draws a frame, waits for the
//   GPU and reads the last frame back (RGBA, flipped to top row first).
// * `draw` returns when the drawing ends or `timeout` passes. A thread cannot be stopped from
//   outside: after a timeout it is abandoned and the runner answers `unavailable` until it ends.
// * While the app cannot present frames (PERF-011) nothing is drawn; a running drawing stops at its
//   next frame and answers `unavailable`.
// * Nothing is kept between drawings: no context, engine or target exists while idle (PERF-006).
// * PRE-005: the engine clock is pinned to the frame number (frame n at n/60 s), so a preset that moves
//   with `time` draws the same way every time; `drawSamples` also reads back requested earlier frames
//   (two extra GPU waits and small read-backs) for the motion score.
import CANGLE
import Foundation
import ProjectMBridge
import Rendering

final class PresetThumbnailRunner: PresetThumbnailDrawing, @unchecked Sendable {
    static let stackSize = 768 * 1024

    private let display: EGLDisplay
    private let config: EGLConfig
    private let condition = NSCondition()
    private var busy = false
    private var suspended = false
    private var texturePaths: [String] = []
    private var current: Attempt?
    /// Drawings started (tests).
    private(set) var startedCount = 0

    init(display: EGLDisplay, config: EGLConfig) {
        self.display = display
        self.config = config
    }

    /// One drawing: answers exactly once (the thread, the timeout or a suspension).
    private final class Attempt: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<PresetThumbnailSampleResult, Never>?
        private var cancelFlag = false

        init(_ continuation: CheckedContinuation<PresetThumbnailSampleResult, Never>) { self.continuation = continuation }

        func finish(_ result: PresetThumbnailDrawResult) {
            finish(PresetThumbnailSampleResult(picture: result, samples: []))
        }

        func finish(_ result: PresetThumbnailSampleResult) {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(returning: result)
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

    // MARK: - PresetThumbnailDrawing

    func draw(_ contents: Data, width: Int, height: Int, frames: [[Float]], timeout: Duration) async -> PresetThumbnailDrawResult {
        await drawSamples(contents, width: width, height: height, frames: frames, sampleFrames: [], timeout: timeout).picture
    }

    func drawSamples(_ contents: Data, width: Int, height: Int, frames: [[Float]], sampleFrames: [Int],
                     timeout: Duration) async -> PresetThumbnailSampleResult {
        await withCheckedContinuation { (continuation: CheckedContinuation<PresetThumbnailSampleResult, Never>) in
            let attempt = Attempt(continuation)
            condition.lock()
            if suspended {
                condition.unlock()
                attempt.finish(.unavailable("The app is not on screen."))
                return
            }
            if busy {
                condition.unlock()
                attempt.finish(.unavailable("An earlier thumbnail has not finished."))
                return
            }
            busy = true
            current = attempt
            startedCount += 1
            let paths = texturePaths
            condition.unlock()

            let thread = Thread { [self] in
                let result = work(contents, width: width, height: height, frames: frames, sampleFrames: sampleFrames,
                                  texturePaths: paths, attempt: attempt)
                condition.lock()
                busy = false
                if current === attempt { current = nil }
                condition.broadcast()
                condition.unlock()
                attempt.finish(result)
            }
            thread.name = "projectM preset thumbnail"
            thread.stackSize = Self.stackSize
            thread.qualityOfService = .utility
            thread.start()

            let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + max(seconds, 0)) {
                attempt.finish(.unavailable("The thumbnail took too long."))   // a no-op when already answered
            }
        }
    }

    // MARK: - Renderer hooks

    func setTexturePaths(_ paths: [String]) {
        condition.lock()
        texturePaths = paths
        condition.unlock()
    }

    /// PERF-011: no drawing while the app cannot present frames. A running drawing stops at its
    /// next frame; this waits briefly for it.
    func setSuspended(_ value: Bool) {
        condition.lock()
        suspended = value
        guard value, let attempt = current else {
            condition.unlock()
            return
        }
        attempt.cancel()
        let deadline = Date().addingTimeInterval(PresetTrialRunner.suspendWait)
        while busy && current === attempt {
            if !condition.wait(until: deadline) { break }
        }
        condition.unlock()
        attempt.finish(.unavailable("The app left the screen during the thumbnail."))
    }

    var isBusy: Bool {
        condition.lock()
        defer { condition.unlock() }
        return busy
    }

    // MARK: - The drawing thread

    private func work(_ contents: Data, width: Int, height: Int, frames: [[Float]], sampleFrames: [Int], texturePaths: [String],
                      attempt: Attempt) -> PresetThumbnailSampleResult {
        let refused: (PresetThumbnailDrawResult) -> PresetThumbnailSampleResult = { PresetThumbnailSampleResult(picture: $0, samples: []) }
        guard width > 0, height > 0, !frames.isEmpty else { return refused(.failed("Nothing to draw.")) }
        let contextAttributes: [EGLint] = [EGL_CONTEXT_MAJOR_VERSION, 3, EGL_CONTEXT_MINOR_VERSION, 0, EGL_NONE]
        let pbufferAttributes: [EGLint] = [EGL_WIDTH, 1, EGL_HEIGHT, 1, EGL_NONE]
        guard let context = eglCreateContext(display, config, nil, contextAttributes) else {
            return refused(.unavailable("No drawing context for the thumbnail."))
        }
        guard let pbuffer = eglCreatePbufferSurface(display, config, pbufferAttributes) else {
            eglDestroyContext(display, context)
            return refused(.unavailable("No drawing surface for the thumbnail."))
        }
        eglMakeCurrent(display, pbuffer, pbuffer, context)
        var result = refused(.unavailable("No engine for the thumbnail."))
        var engine: ProjectMEngine?
        var texture: UInt32 = 0
        var framebuffer: UInt32 = 0
        if let created = try? ProjectMEngine(glLoader: PMANGLELoadProc, userData: nil) {
            engine = created
            created.setViewportWidth(width, height: height)
            framebuffer = PMANGLECreateBGRAFramebuffer(Int32(width), Int32(height), &texture)
            if framebuffer != 0 {
                created.setTextureSearchPaths(texturePaths)
                result = draw(contents, engine: created, framebuffer: framebuffer, width: width, height: height,
                              frames: frames, sampleFrames: sampleFrames, attempt: attempt)
            } else {
                result = refused(.unavailable("No drawing target for the thumbnail."))
            }
        }
        if framebuffer != 0 { PMANGLEDeleteFramebuffer(framebuffer, texture) }
        engine = nil   // destroyed while its context is current (bridge guarantee 3)
        eglMakeCurrent(display, nil, nil, nil)
        eglDestroySurface(display, pbuffer)
        eglDestroyContext(display, context)
        return result
    }

    private func draw(_ contents: Data, engine: ProjectMEngine, framebuffer: UInt32, width: Int, height: Int,
                      frames: [[Float]], sampleFrames: [Int], attempt: Attempt) -> PresetThumbnailSampleResult {
        let refused: (PresetThumbnailDrawResult) -> PresetThumbnailSampleResult = { PresetThumbnailSampleResult(picture: $0, samples: []) }
        if attempt.isCancelled { return refused(.unavailable("The thumbnail was stopped.")) }
        do {
            try engine.loadPresetData(contents, smooth: false)
        } catch {
            let message = (error as NSError).localizedDescription
            return refused(.failed(message.isEmpty ? "The preset could not be loaded" : message))
        }
        let limit = Int(ProjectMEngine.maxSamplesPerFrame)
        let wanted = Set(sampleFrames.filter { $0 >= 0 && $0 < frames.count - 1 })
        var samples: [Data] = []
        for (index, block) in frames.enumerated() {
            if attempt.isCancelled { return refused(.unavailable("The thumbnail was stopped.")) }
            let count = min(block.count / 2, limit)
            if count > 0 {
                block.withUnsafeBufferPointer { engine.addPCMInterleavedStereo($0.baseAddress!, frames: UInt(count)) }
            }
            engine.setFrameTime(Double(index) / Self.frameRate)   // PRE-005: a pinned clock
            engine.renderFrame(toFramebuffer: framebuffer)
            if wanted.contains(index) {
                guard let sample = Self.readBack(framebuffer, width: width, height: height) else {
                    return refused(.unavailable("The thumbnail could not be read back."))
                }
                samples.append(sample)
            }
        }
        guard let picture = Self.readBack(framebuffer, width: width, height: height) else {
            return refused(.unavailable("The thumbnail could not be read back."))
        }
        return PresetThumbnailSampleResult(picture: .pixels(picture), samples: samples)
    }

    /// The drawing's clock rate: frame n is drawn at n / 60 s (PRE-001's 735 samples at 44.1 kHz).
    static let frameRate = 60.0

    /// Waits for the GPU and reads the framebuffer back as RGBA rows, top row first.
    static func readBack(_ framebuffer: UInt32, width: Int, height: Int) -> Data? {
        PMANGLEFinish()
        PMANGLEBindFramebuffer(framebuffer)
        let rowBytes = width * 4
        var pixels = [UInt8](repeating: 0, count: rowBytes * height)
        let error = pixels.withUnsafeMutableBytes { PMANGLEReadPixelsRGBA(0, 0, Int32(width), Int32(height), $0.baseAddress!) }
        PMANGLEBindDefaultFramebuffer()
        guard error == 0 else { return nil }
        // GL's rows start at the bottom; pictures start at the top.
        var flipped = Data(count: pixels.count)
        flipped.withUnsafeMutableBytes { (out: UnsafeMutableRawBufferPointer) in
            pixels.withUnsafeBytes { (source: UnsafeRawBufferPointer) in
                for row in 0..<height {
                    let from = (height - 1 - row) * rowBytes
                    out.baseAddress!.advanced(by: row * rowBytes).copyMemory(from: source.baseAddress!.advanced(by: from), byteCount: rowBytes)
                }
            }
        }
        return flipped
    }
}
