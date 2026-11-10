// Task T068: ProjectMEngine (PMBridge) against the real engine in an OpenGL ES 3 context on the
// iOS Simulator. A malformed preset returns `presetLoadFailed` with no exception crossing, and the
// previous preset keeps running (FR-045); `maxSamplesPerFrame` > 0; 100 create/destroy cycles do
// not leak. The load proc is the static OpenGL ES 3.0 table (no dlsym, Constitution I).
import XCTest
import OpenGLES
import Darwin
import ProjectMBridge

final class PMEngineTests: XCTestCase {
    private var context: EAGLContext?
    private var framebuffer: GLuint = 0
    private var renderbuffer: GLuint = 0

    /// The engine's upstream test presets (Vendor/projectM/presets/tests); the simulator can read them.
    private static let testPresets = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Vendor/projectM/presets/tests")

    override func setUpWithError() throws {
        let context = try XCTUnwrap(EAGLContext(api: .openGLES3), "no OpenGL ES 3 context")
        XCTAssertTrue(EAGLContext.setCurrent(context))
        self.context = context
        // A small offscreen framebuffer to render into.
        glGenFramebuffers(1, &framebuffer)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), framebuffer)
        glGenRenderbuffers(1, &renderbuffer)
        glBindRenderbuffer(GLenum(GL_RENDERBUFFER), renderbuffer)
        glRenderbufferStorage(GLenum(GL_RENDERBUFFER), GLenum(GL_RGBA8), 64, 64)
        glFramebufferRenderbuffer(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_RENDERBUFFER), renderbuffer)
        XCTAssertEqual(glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER)), GLenum(GL_FRAMEBUFFER_COMPLETE))
    }

    override func tearDown() {
        glDeleteRenderbuffers(1, &renderbuffer)
        glDeleteFramebuffers(1, &framebuffer)
        EAGLContext.setCurrent(nil)
        context = nil
    }

    private func makeEngine() throws -> ProjectMEngine {
        let engine = try ProjectMEngine(glLoader: PMAppleGLESLoadProc, userData: nil)
        engine.setViewportWidth(64, height: 64)
        return engine
    }

    private func preset(_ name: String) -> String {
        Self.testPresets.appendingPathComponent(name).path
    }

    private func renderFrames(_ engine: ProjectMEngine, count: Int = 3) {
        let silence = [Float](repeating: 0, count: 2 * 512)
        for _ in 0..<count {
            silence.withUnsafeBufferPointer { engine.addPCMInterleavedStereo($0.baseAddress!, frames: 512) }
            engine.renderFrame(toFramebuffer: UInt32(framebuffer))
        }
    }

    // MARK: - Load proc

    func testLoadProcResolvesOpenGLES3FunctionsOnly() {
        XCTAssertGreaterThanOrEqual(PMAppleGLESFunctionCount(), 200)
        XCTAssertNotNil(PMAppleGLESLoadProc("glClear", nil))
        XCTAssertNotNil(PMAppleGLESLoadProc("glTexStorage2D", nil))   // ES 3.0
        XCTAssertNil(PMAppleGLESLoadProc("glNotARealFunction", nil))
        XCTAssertNil(PMAppleGLESLoadProc("eglGetProcAddress", nil))
    }

    // MARK: - Engine

    func testMaxSamplesPerFrameIsPositive() {
        XCTAssertGreaterThan(ProjectMEngine.maxSamplesPerFrame, 0)
    }

    func testEngineCreatesAndRendersWithACurrentContext() throws {
        let engine = try makeEngine()
        renderFrames(engine)
        XCTAssertEqual(glGetError(), GLenum(GL_NO_ERROR))
    }

    func testCreatingWithoutAContextFailsWithContextUnavailable() {
        EAGLContext.setCurrent(nil)
        XCTAssertThrowsError(try ProjectMEngine(glLoader: PMAppleGLESLoadProc, userData: nil)) { error in
            XCTAssertEqual((error as NSError).domain, PMEngineErrorDomain)
            XCTAssertEqual((error as NSError).code, PMEngineError.contextUnavailable.rawValue)
        }
    }

    func testUpstreamTestPresetLoads() throws {
        let engine = try makeEngine()
        XCTAssertNoThrow(try engine.loadPreset(atPath: preset("100-square.milk"), smooth: false))
        renderFrames(engine)
    }

    func testMissingPresetFailsWithPresetLoadFailed() throws {
        let engine = try makeEngine()
        XCTAssertThrowsError(try engine.loadPreset(atPath: preset("does-not-exist.milk"), smooth: false)) { error in
            XCTAssertEqual((error as NSError).domain, PMEngineErrorDomain)
            XCTAssertEqual((error as NSError).code, PMEngineError.presetLoadFailed.rawValue)
        }
    }

    func testMalformedPresetFailsAndThePreviousPresetKeepsRunning() throws {
        let engine = try makeEngine()
        try engine.loadPreset(atPath: preset("100-square.milk"), smooth: false)
        // Not a preset at all: an unsupported file type with binary content.
        let bad = FileManager.default.temporaryDirectory.appendingPathComponent("malformed-\(UUID().uuidString).bin")
        try Data([0x00, 0xFF, 0xFE, 0x00, 0x13, 0x37]).write(to: bad)
        defer { try? FileManager.default.removeItem(at: bad) }
        XCTAssertThrowsError(try engine.loadPreset(atPath: bad.path, smooth: false)) { error in
            XCTAssertEqual((error as NSError).code, PMEngineError.presetLoadFailed.rawValue)
        }
        renderFrames(engine)   // still running; no exception crossed into Swift
        XCTAssertEqual(glGetError(), GLenum(GL_NO_ERROR))
    }

    func testAddsUpToMaxSamplesPerFrame() throws {
        let engine = try makeEngine()
        let frames = Int(ProjectMEngine.maxSamplesPerFrame)
        let samples = (0..<(2 * frames)).map { Float(sin(Double($0) / 20)) * 0.5 }
        samples.withUnsafeBufferPointer { engine.addPCMInterleavedStereo($0.baseAddress!, frames: UInt(frames)) }
        engine.renderFrame(toFramebuffer: UInt32(framebuffer))
    }

    func testLogHandlerReceivesEngineMessages() throws {
        final class Box: @unchecked Sendable { var lines: [String] = [] }
        let box = Box()
        ProjectMEngine.setLogHandler({ message, _ in box.lines.append(message) }, minimumLevel: 3)
        defer { ProjectMEngine.setLogHandler(nil, minimumLevel: 4) }
        let engine = try makeEngine()
        let duringCreate = box.lines.count
        _ = try? engine.loadPreset(atPath: preset("does-not-exist.milk"), smooth: false)
        XCTAssertGreaterThan(box.lines.count, duringCreate, "the engine logged while loading a missing preset")
        // Creating an engine must not leave this thread filtering out INFO messages.
        let before = box.lines.count
        _ = try makeEngine()
        _ = try? engine.loadPreset(atPath: preset("does-not-exist.milk"), smooth: false)
        XCTAssertGreaterThan(box.lines.count, before)
    }

    func testHundredCreateDestroyCyclesDoNotLeak() throws {
        // Warm up once (engine statics, shader caches), then measure the footprint across 100 cycles.
        try autoreleasepool { _ = try makeEngine() }
        let before = Self.physicalFootprint()
        weak var last: ProjectMEngine?
        for _ in 0..<100 {
            try autoreleasepool {
                let engine = try makeEngine()
                renderFrames(engine, count: 1)
                last = engine
            }
        }
        XCTAssertNil(last, "the engine was released")
        let growthMB = Double(Int64(Self.physicalFootprint()) - Int64(before)) / 1_048_576
        XCTAssertLessThan(growthMB, 16, "footprint grew \(growthMB) MB over 100 cycles")
    }

    private static func physicalFootprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }
}
