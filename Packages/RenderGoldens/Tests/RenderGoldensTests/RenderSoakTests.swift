// QA-006-T06, T08, T10 (US1, US2, US4; QA-006-R1 to R10; QA-006-S1, S2): the scene render soak.
// * Acceptance: six QA-002 scenes switched 60 times in 30 s of simulated time (crossfades and cuts on
//   CMP-014's bus, one shared pool) with seeded fixture bands: zero render errors, a flat memory slope,
//   no step above the bound, pool checkouts at each scene's baseline after every switch, one scene alive
//   per dwell end, nothing left after release.
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
        return url
    }

    // MARK: - T06 acceptance (US1)

    func testDefaultSoakIsBoundedAndErrorFree() throws {
        let driver = try driver()
        let configuration = RenderSoakConfiguration(name: "qa006-scene-soak", scenes: try scenes(Self.soakSceneNames),
                                                    frames: RenderSoakConfiguration.frames(seconds: 30))
        XCTAssertEqual(configuration.frames, 1_800)
        let report = driver.run(configuration)
        try publish(report)
        XCTAssertEqual(report.switches, 59, "60 scenes shown: 59 switches after the first")
        XCTAssertEqual(report.cycles, 10)
        XCTAssertEqual(report.samples.count, 10)
        XCTAssertEqual(report.dwells.count, 60)
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

    // MARK: - T10 on-demand bench (US4)

    func testOnDemandLongSoak() throws {
        guard let seconds = RenderSoakDriver.requestedSeconds() else {
            throw XCTSkip("Set QA006_SOAK_SECONDS=<simulated seconds> to run the long soak (scripts/run_render_soak.py).")
        }
        let driver = try driver()
        let configuration = RenderSoakConfiguration(name: "qa006-scene-soak-\(Int(seconds))s", scenes: try scenes(Self.soakSceneNames),
                                                    frames: RenderSoakConfiguration.frames(seconds: seconds))
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
