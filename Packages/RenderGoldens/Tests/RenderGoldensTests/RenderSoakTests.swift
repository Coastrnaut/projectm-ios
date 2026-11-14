// QA-006-T06, T08, T10 (US1, US2, US4; QA-006-R1 to R10; QA-006-S1, S2): the scene render soak.
// * Acceptance: six QA-002 scenes switched 120 times in 60 s of simulated time (crossfades and cuts on
//   CMP-014's bus, one shared pool) with seeded fixture bands: zero render errors, a flat memory slope
//   after a warm-up of the first half (10 cycles; research QA-006-D2a: a paravirtual GPU's driver keeps
//   freed allocations for the first ~60 scene builds of a process), no step above the bound, pool
//   checkouts at each scene's baseline after every switch, one scene alive per dwell end, nothing left
//   after release.
// * Negative controls: the same soak (3 scenes, 6 cycles) with a leak injected per cycle must fail.
// * Bench: `QA006_SOAK_SECONDS=<n>` runs n simulated seconds (skipped otherwise; scripts/run_render_soak.py).
// Every run writes a JSON report (QA006_REPORT_DIR or the temporary folder) and attaches it. Nothing
// asserts wall time. Without a Metal device the tests are skipped; the verdict is tested in Compositor.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Compositor
import Foundation
import GoldenImages
import SceneRenderHarness
import XCTest

final class RenderSoakTests: XCTestCase {
    /// Research QA-006-D3: six of the seven golden scenes (strobe-guarded adds nothing a soak checks).
    static let soakSceneNames = ["photo-gradient", "text-caption", "spectrum-circular", "material-plasma", "graph-hue-rings",
                                 "stack-composite"]

    private func driver() throws -> RenderSoakDriver {
        do {
            return try RenderSoakDriver(renderer: try GoldenSceneRenderer())
        } catch {
            throw XCTSkip("No Metal device; the soak verdict is covered by RenderSoakVerdictTests (Compositor).")
        }
    }

    /// Research QA-006-D2a: the warm-up covers the first half of a scene soak's cycles (at most 10, at least the
    /// standard 2). CI's paravirtual GPU grew `currentAllocatedSize` by ~190 KB per cycle over a process's first
    /// soak while the pool and the live objects stayed flat, then not at all (run 43612171768).
    static func settledTolerance(cycles: Int) -> RenderSoakTolerance {
        RenderSoakTolerance(warmUpCycles: max(RenderSoakTolerance.standard.warmUpCycles, min(10, cycles / 2)))
    }

    private func scenes(_ names: [String]) throws -> [RenderSoakScene] {
        try names.map { (name: String) throws -> RenderSoakScene in
            let run = try XCTUnwrap(GoldenSceneCatalog.run(named: name), name)
            return RenderSoakScene(run: run, document: try GoldenSceneRenderer.document(from: GoldenPaths.sceneBytes(run)))
        }
    }

    /// Writes and attaches the report; returns it.
    @discardableResult
    private func publish(_ report: RenderSoakReport) throws -> URL {
        let url = try RenderSoakDriver.write(report)
        let attachment = XCTAttachment(contentsOfFile: url)
        attachment.lifetime = .keepAlways
        add(attachment)
        print("QA-006 \(report.name) [\(report.platform), \(report.memorySource)]: \(report.verdict.summary); "
              + "\(report.frames) frames, \(report.switches) switches in \(String(format: "%.1f", report.wallSeconds)) s wall; report \(url.path)")
        // The per-cycle series in the log (CI keeps no attachment), so a memory verdict can be read from it.
        for c in report.samples {
            print("QA-006 \(report.name) cycle \(c.cycle): high-water \(c.memoryHighWaterBytes), end \(c.memoryEndBytes), "
                  + "pool live \(c.poolLiveBytes), misses \(c.poolMisses), footprint \(c.processFootprintBytes.map { (b: Int) -> String in "\(b)" } ?? "-")")
        }
        return url
    }

    // MARK: - T06 acceptance (US1)

    func testDefaultSoakIsBoundedAndErrorFree() throws {
        let driver = try driver()
        let configuration = RenderSoakConfiguration(name: "qa006-scene-soak", scenes: try scenes(Self.soakSceneNames),
                                                    frames: RenderSoakConfiguration.frames(seconds: 60),
                                                    tolerance: Self.settledTolerance(cycles: 20))
        XCTAssertEqual(configuration.frames, 3_600)
        XCTAssertEqual(configuration.tolerance.warmUpCycles, 10)
        let report = driver.run(configuration)
        try publish(report)
        XCTAssertEqual(report.switches, 119, "120 scenes shown: 119 switches after the first")
        XCTAssertEqual(report.cycles, 20)
        XCTAssertEqual(report.samples.count, 20)
        XCTAssertEqual(report.verdict.measuredCycles, 10)
        XCTAssertEqual(report.dwells.count, 120)
        XCTAssertEqual(report.errorCount, 0, "\(report.errors)")
        XCTAssertTrue(report.verdict.passed, report.verdict.summary)
        XCTAssertLessThanOrEqual(report.verdict.slopeBytesPerCycle, report.verdict.slopeLimitBytesPerCycle)
        XCTAssertLessThanOrEqual(report.verdict.maxMeasuredHighWaterBytes, report.verdict.boundBytes)
        XCTAssertTrue(report.verdict.baselineMismatches.isEmpty, "\(report.verdict.baselineMismatches)")
        XCTAssertTrue(report.dwells.allSatisfy { (d: RenderSoakDwellSample) -> Bool in d.liveScenes == 1 })
        XCTAssertEqual(report.release, RenderSoakRelease(checkedOutTextures: 0, liveObjects: 0))
    }

    // MARK: - T08 negative controls (US2)

    private func leakingSoak(_ leak: RenderSoakLeak) throws -> RenderSoakReport {
        let driver = try driver()
        let names = ["photo-gradient", "spectrum-circular", "material-plasma"]
        let configuration = RenderSoakConfiguration(name: "qa006-leak-\(leak.rawValue)", scenes: try scenes(names),
                                                    frames: 6 * 3 * 30, leak: leak)
        let report = driver.run(configuration)
        try publish(report)
        XCTAssertEqual(report.cycles, 6)
        XCTAssertEqual(report.errorCount, 0, "a leak is not a render error: \(report.errors)")
        XCTAssertEqual(report.verdict.outcome, .fail, report.verdict.summary)
        return report
    }

    func testPooledLeakFailsTheSoak() throws {
        let report = try leakingSoak(.pooledTexturePerCycle)
        XCTAssertTrue(report.verdict.failedRules.contains(.poolBaseline), report.verdict.summary)
        XCTAssertTrue(report.verdict.failedRules.contains(.memorySlope), report.verdict.summary)
        XCTAssertTrue(report.verdict.failedRules.contains(.releaseNotEmpty), "the leaked textures are still checked out")
    }

    func testDeviceLeakFailsTheSoak() throws {
        let report = try leakingSoak(.deviceTexturePerCycle)
        XCTAssertTrue(report.verdict.failedRules.contains(.memorySlope), report.verdict.summary)
        XCTAssertFalse(report.verdict.failedRules.contains(.poolBaseline), "the pool never saw the leak")
    }

    /// Research QA-006-D2a: the settled warm-up passes CI's driver growth (≈190 KB per cycle that stops within the
    /// warm-up) and still fails a steady leak of one 128 × 96 `rgba16Float` texture (98,304 B) per cycle on top of it.
    func testSettledWarmUpPassesDriverGrowthAndCatchesASteadyLeak() {
        let tolerance = Self.settledTolerance(cycles: 20)
        XCTAssertEqual(tolerance.warmUpCycles, 10)
        XCTAssertEqual(Self.settledTolerance(cycles: 6).warmUpCycles, 3)
        XCTAssertEqual(Self.settledTolerance(cycles: 2).warmUpCycles, 2)
        func verdict(leakPerCycle: Int) -> RenderSoakVerdict {
            var recorder = RenderSoakRecorder(tolerance: tolerance)
            for cycle in 0..<20 {
                let driver: Int = 6_766_592 + 188_221 * min(cycle, 9)   // grows, then plateaus inside the warm-up
                let memory: Int = driver + leakPerCycle * cycle
                recorder.record(cycle: RenderSoakCycleSample(cycle: cycle, memoryHighWaterBytes: memory, memoryEndBytes: memory))
            }
            return recorder.verdict()
        }
        XCTAssertTrue(verdict(leakPerCycle: 0).passed, verdict(leakPerCycle: 0).summary)
        let leaking = verdict(leakPerCycle: 98_304)
        XCTAssertEqual(leaking.outcome, .fail, leaking.summary)
        XCTAssertEqual(leaking.failedRules, [.memorySlope], leaking.summary)
    }

    // MARK: - T10 on-demand bench (US4)

    func testOnDemandLongSoak() throws {
        guard let seconds = RenderSoakDriver.requestedSeconds() else {
            throw XCTSkip("Set QA006_SOAK_SECONDS=<simulated seconds> to run the long soak (scripts/run_render_soak.py).")
        }
        let driver = try driver()
        var configuration = RenderSoakConfiguration(name: "qa006-scene-soak-\(Int(seconds))s", scenes: try scenes(Self.soakSceneNames),
                                                    frames: RenderSoakConfiguration.frames(seconds: seconds))
        configuration.tolerance = Self.settledTolerance(cycles: configuration.frames / configuration.cycleFrames)
        let report = driver.run(configuration)
        try publish(report)
        XCTAssertTrue(report.verdict.passed, report.verdict.summary)
    }

    func testRequestedSecondsParsing() {
        XCTAssertNil(RenderSoakDriver.requestedSeconds(environment: [:]))
        XCTAssertNil(RenderSoakDriver.requestedSeconds(environment: ["QA006_SOAK_SECONDS": ""]))
        XCTAssertNil(RenderSoakDriver.requestedSeconds(environment: ["QA006_SOAK_SECONDS": "ten"]))
        XCTAssertNil(RenderSoakDriver.requestedSeconds(environment: ["QA006_SOAK_SECONDS": "-5"]))
        XCTAssertEqual(RenderSoakDriver.requestedSeconds(environment: ["QA006_SOAK_SECONDS": "600"]), 600)
        XCTAssertEqual(RenderSoakDriver.reportDirectory(environment: ["QA006_REPORT_DIR": "/tmp/x"]).path, "/tmp/x")
    }
}
#endif
