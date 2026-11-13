// PRE-012-T12, T20: the off-screen preset trial with the real engine on the iOS Simulator
// (PRE-012-R14-R16, S3). The presets are written here; none is a third-party file. Simulator
// results are not device evidence (Constitution X).
import XCTest
import Rendering
@testable import ANGLERendering

@MainActor
final class PresetTrialRunnerTests: XCTestCase {
    private func preset(perFrame: [String] = ["wave_r = 0.5 + 0.5*sin(time*1.1);", "rot = 0.02*sin(time*0.3) + 0.01*bass;"],
                        perFrameInit: [String] = [],
                        perPixel: [String] = ["zoom = zoom + 0.02*sin(rad*6 + time);"],
                        comp: [String] = ["shader_body", "{", "ret = tex2D(sampler_main, uv).xyz*0.9 + 0.1*tex2D(sampler_noise_lq, uv).xyz;", "}"]) -> Data {
        var lines = ["MILKDROP_PRESET_VERSION=201", "PSVERSION=2", "PSVERSION_WARP=2", "PSVERSION_COMP=2", "[preset00]",
                     "fRating=3.000000", "fDecay=0.960000", "zoom=1.010000", "rot=0.010000", "wave_r=0.6", "wave_g=0.6", "wave_b=0.9",
                     "nWaveMode=2", "fWaveAlpha=1.0", "fWaveScale=1.5"]
        lines += perFrameInit.enumerated().map { "per_frame_init_\($0.offset + 1)=\($0.element)" }
        lines += perFrame.enumerated().map { "per_frame_\($0.offset + 1)=\($0.element)" }
        lines += perPixel.enumerated().map { "per_pixel_\($0.offset + 1)=\($0.element)" }
        lines += comp.enumerated().map { "comp_\($0.offset + 1)=`\($0.element)" }
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    private func makeLaidOut() throws -> ANGLERenderer {
        let renderer = try ANGLERenderer.make()
        renderer.view.frame = CGRect(x: 0, y: 0, width: 64, height: 64)
        renderer.view.layoutIfNeeded()
        return renderer
    }

    private func trial(_ renderer: ANGLERenderer) throws -> any PresetTrialing {
        try XCTUnwrap(renderer.presetTrial)
    }

    private func litPixels(_ pixels: [UInt8]) -> Int {
        stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0] > 8 || pixels[$0 + 1] > 8 || pixels[$0 + 2] > 8 }.count
    }

    func testAValidPresetPasses() async throws {
        let renderer = try makeLaidOut()
        let started = Date()
        let outcome = try await trial(renderer).run(preset(), timeout: .seconds(10))
        XCTAssertEqual(outcome, .passed)
        print("PRE-012 trial: valid preset passed in \(String(format: "%.2f", Date().timeIntervalSince(started))) s")
        // The runner is free again and its graphics resources are gone.
        XCTAssertFalse(renderer.trialRunner.isBusy)
        let again = try await trial(renderer).run(preset(perFrame: ["rot = 0.1;"]), timeout: .seconds(10))
        XCTAssertEqual(again, .passed)
    }

    func testEquationsTheEngineCannotCompileFailWithItsMessage() async throws {
        let renderer = try makeLaidOut()
        for (name, data) in [("per-frame", preset(perFrame: ["wave_r = = 3 +* ;"])),
                             ("per-pixel", preset(perPixel: ["zoom = zoom +* / 2;"])),
                             ("init", preset(perFrameInit: ["q1 = ) 3;"]))] {
            let outcome = try await trial(renderer).run(data, timeout: .seconds(10))
            guard case .failed(let message) = outcome else { XCTFail("\(name): \(outcome)"); continue }
            XCTAssertFalse(message.isEmpty, name)
            print("PRE-012 trial: \(name) failure message: \(message)")
        }
        XCTAssertFalse(renderer.trialRunner.isBusy)
    }

    /// A shader the engine cannot translate is dropped by the engine, not fatal: the preset loads
    /// without it (engine audit). The trial must report what the engine does.
    func testAShaderTheEngineDropsStillPasses() async throws {
        let renderer = try makeLaidOut()
        let outcome = try await trial(renderer).run(preset(comp: ["shader_body", "{", "ret = this is not hlsl at all(;", "}"]), timeout: .seconds(10))
        print("PRE-012 trial: untranslatable shader → \(outcome)")
        XCTAssertNotEqual(outcome, .timedOut)
        XCTAssertFalse(renderer.trialRunner.isBusy)
    }

    /// The shapes that go deepest per byte in the engine's shader translator (hlslparser), in
    /// ANGLE's shader compiler and in the equation compiler, built at `scale` times the static
    /// limits of PresetImportLimits (nesting 64; shader statement complexity 256; equation
    /// statement complexity 512; 64 control keywords).
    private func worstCases(scale: Int) -> [(String, Data)] {
        func shader(_ lines: [String]) -> Data {
            preset(comp: ["shader_body", "{", "ret = tex2D(sampler_main, uv).xyz;", "float t = uv.x;"] + lines + ["}"])
        }
        func repeated(_ text: String, _ count: Int) -> String { String(repeating: text, count: count) }
        let nesting = 64 * scale, shaderOps = 256 * scale - 1, equationOps = 512 * scale - 1, keywords = 64 * scale
        return [
            ("equation: \(nesting) nested parentheses", preset(perFrame: ["q1 = " + repeated("(", nesting) + "time" + repeated(")", nesting) + ";"])),
            ("equation: \(nesting) nested calls", preset(perFrame: ["q1 = " + repeated("sin(", nesting) + "time" + repeated(")", nesting) + ";"])),
            ("equation: sum of \(equationOps) terms", preset(perFrame: ["q1 = time;", "q2 = " + repeated("q1+", equationOps) + "q1;"])),
            ("equation: \(equationOps) unary operators", preset(perPixel: ["q2 = " + repeated("-!", equationOps / 2) + "rad;"])),
            ("equation: \(equationOps) chained assignments", preset(perFrame: [repeated("q1=q2=q3=q4=", equationOps / 4) + "time;"])),
            ("shader: \(shaderOps) casts", shader(["ret = " + repeated("(float3)", shaderOps) + "ret;"])),
            ("shader: \(shaderOps) unary operators", shader(["ret = " + repeated("-+", shaderOps / 2) + "ret;"])),
            ("shader: sum of \(shaderOps) terms", shader(["ret = " + repeated("ret+", shaderOps) + "ret;"])),
            ("shader: \(shaderOps) member accesses", shader(["ret = ret" + repeated(".xyz", shaderOps) + ";"])),
            ("shader: \(nesting) nested parentheses", shader(["ret = " + repeated("(", nesting) + "ret" + repeated(")", nesting) + ";"])),
            ("shader: \(nesting) nested calls", shader(["ret = " + repeated("abs(", nesting) + "ret" + repeated(")", nesting) + ";"])),
            ("shader: \(nesting - 1) nested blocks", shader([repeated("{", nesting - 1) + "ret *= 0.99;" + repeated("}", nesting - 1)])),
            ("shader: else-if chain of \(keywords) keywords", shader(["if(t>2) ret*=0.9;" + repeated(" else if(t>2) ret*=0.9;", keywords / 2 - 1) + " else ret*=0.99;"])),
            ("shader: \(keywords) nested ifs", shader([repeated("if(t>-1) ", keywords) + "ret*=0.99;"])),
            ("shader: macro of \(200 * scale) terms used \(50 * scale) times",
             preset(comp: ["#define BIG (" + repeated("ret+", 200 * scale) + "ret)", "shader_body", "{", "ret = tex2D(sampler_main, uv).xyz;",
                           "ret = BIG" + repeated("+BIG", 50 * scale) + ";", "}"])),
        ]
    }

    private func runWorstCases(scale: Int) async throws {
        let renderer = try makeLaidOut()
        for (name, data) in worstCases(scale: scale) {
            let started = Date()
            let outcome = try await trial(renderer).run(data, timeout: .seconds(30))
            print("PRE-012 trial (limits × \(scale)): \(name) → \(outcome) in \(String(format: "%.2f", Date().timeIntervalSince(started))) s")
            switch outcome {
            case .passed, .failed: break
            default: XCTFail("\(name): \(outcome)")
            }
            // What passed the trial is then loaded by the visible engine, on the main thread.
            if outcome == .passed {
                try await renderer.setPreset(Preset(id: name, name: name, fileURL: URL(fileURLWithPath: "/dev/null"), data: data))
                for _ in 0..<3 { XCTAssertTrue(renderer.renderFrame(present: false)) }
            }
        }
    }

    /// Presets at the static limits must not take the process down, on the trial's thread or on
    /// the visible renderer's. A crash here means a limit is too high.
    func testPresetsAtTheStaticLimitsDoNotCrashTheProcess() async throws {
        try await runWorstCases(scale: 1)
    }

    /// The margin: the same shapes at twice the limits still do not crash (on this simulator;
    /// the device check is PRE-012-T31).
    func testPresetsAtTwiceTheStaticLimitsDoNotCrashEither() async throws {
        try await runWorstCases(scale: 2)
    }

    func testASuspendedRunnerIsUnavailableAndRunsAgainAfterResume() async throws {
        let renderer = try makeLaidOut()
        renderer.suspendForPresentationLoss()
        let outcome = try await trial(renderer).run(preset(), timeout: .seconds(10))
        guard case .unavailable = outcome else { return XCTFail("\(outcome)") }
        renderer.resumeForPresentation()
        let later = try await trial(renderer).run(preset(), timeout: .seconds(10))
        XCTAssertEqual(later, .passed)
    }

    /// S3: while presets fail their trial, the visible renderer keeps presenting its own preset.
    func testTheVisibleRendererKeepsDrawingWhileTrialsFail() async throws {
        let renderer = try makeLaidOut()
        try await renderer.setPreset(Preset(id: "visible", name: "visible", fileURL: URL(fileURLWithPath: "/dev/null"),
                                            data: preset(perFrame: ["wave_r = 1;"])))
        for _ in 0..<5 { XCTAssertTrue(renderer.renderFrame(present: true)) }
        let framesBefore = renderer.presentedFrameCount
        let runner = try trial(renderer)
        let bad = preset(perFrame: ["wave_r = = 3 +* ;"])
        async let outcome = runner.run(bad, timeout: .seconds(10))
        var presentedDuringTrial = 0
        while renderer.trialRunner.isBusy || presentedDuringTrial < 10 {
            XCTAssertTrue(renderer.renderFrame(present: true))
            presentedDuringTrial += 1
            try await Task.sleep(for: .milliseconds(5))
            if presentedDuringTrial > 2_000 { break }
        }
        guard case .failed = await outcome else { return XCTFail("the bad preset must fail its trial") }
        XCTAssertEqual(renderer.presentedFrameCount, framesBefore + presentedDuringTrial)
        // The visible engine still draws its own preset: there is a picture.
        var lit = 0
        let deadline = ContinuousClock.now + .seconds(30)   // time-bounded, not frame-bounded
        while lit == 0 && ContinuousClock.now < deadline {
            XCTAssertTrue(renderer.renderFrame(present: false))
            lit = litPixels(renderer.readPixels())
            if lit == 0 { try await Task.sleep(for: .milliseconds(10)) }
        }
        XCTAssertGreaterThan(lit, 0)
    }

    /// Named to run last: the hung trial's thread spins until the test process ends (that is the
    /// documented limit, PRE-012-R21).
    func testZZAPresetThatNeverFinishesTimesOutAndBlocksLaterTrials() async throws {
        let renderer = try makeLaidOut()
        let forever = "q1 = 0; loop(1000000, loop(1000000, loop(1000000, loop(1000000, q1 = q1 + 1))));"
        let started = Date()
        let outcome = try await trial(renderer).run(preset(perFrame: [forever]), timeout: .seconds(3))
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertEqual(outcome, .timedOut)
        XCTAssertGreaterThan(elapsed, 2.5)
        XCTAssertLessThan(elapsed, 6)
        XCTAssertTrue(renderer.trialRunner.isBusy, "the abandoned thread is still there")
        let next = try await trial(renderer).run(preset(), timeout: .seconds(3))
        guard case .unavailable = next else { return XCTFail("\(next)") }
        // The visible renderer is unaffected by the stuck thread.
        try await renderer.setPreset(Preset(id: "visible", name: "visible", fileURL: URL(fileURLWithPath: "/dev/null"), data: preset()))
        let before = renderer.presentedFrameCount
        for _ in 0..<20 { XCTAssertTrue(renderer.renderFrame(present: true)) }
        XCTAssertEqual(renderer.presentedFrameCount, before + 20)
    }
}
