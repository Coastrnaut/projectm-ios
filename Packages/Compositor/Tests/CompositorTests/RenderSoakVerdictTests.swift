// QA-006-T03: the render soak's verdict on synthetic samples (QA-006-R5, R6; QA-006-S3; contract S7).
// Plain Swift: runs on the host and in the Linux shape. Memory figures are in bytes; the warm-up is 2
// cycles and the tolerance the standard one unless a test says otherwise.
import Compositor
import XCTest

final class RenderSoakVerdictTests: XCTestCase {
    private let mib = 1_048_576

    /// Cycles 0..<count with high-water marks from `memory(cycle)`.
    private func recorder(cycles count: Int, memory: (Int) -> Int) -> RenderSoakRecorder {
        var r = RenderSoakRecorder()
        for c in 0..<count {
            let m = memory(c)
            r.record(cycle: RenderSoakCycleSample(cycle: c, memoryHighWaterBytes: m, memoryEndBytes: m))
            r.record(dwell: RenderSoakDwellSample(cycle: c, scene: "a", checkedOutTextures: 3, checkedOutBytes: 300, liveScenes: 1))
        }
        r.record(release: RenderSoakRelease(checkedOutTextures: 0, liveObjects: 0))
        return r
    }

    func testFlatAndNoisyMemoryPass() {
        let flat = recorder(cycles: 10) { (_: Int) -> Int in 20 * self.mib }.verdict()
        XCTAssertEqual(flat.outcome, .pass, flat.summary)
        XCTAssertEqual(flat.slopeBytesPerCycle, 0, accuracy: 1e-9)
        // ±32 KiB alternating noise and a warm-up peak above the steady level.
        let noisy = recorder(cycles: 10) { (c: Int) -> Int in
            c == 0 ? 24 * self.mib : 20 * self.mib + (c % 2 == 0 ? 32_768 : -32_768)
        }.verdict()
        XCTAssertEqual(noisy.outcome, .pass, noisy.summary)
        XCTAssertEqual(noisy.warmUpHighWaterBytes, Double(24 * mib))
    }

    func testARampFailsTheSlopeRule() {
        // 128 KiB per cycle (one 128 × 96 half-float texture is 96 KiB plus alignment): above ε = max(64 KiB, 0.5 % of 20 MiB).
        let v = recorder(cycles: 8) { (c: Int) -> Int in 20 * self.mib + c * 131_072 }.verdict()
        XCTAssertEqual(v.outcome, .fail)
        XCTAssertEqual(v.failedRules, [.memorySlope], v.summary)
        XCTAssertEqual(v.slopeBytesPerCycle, 131_072, accuracy: 1)
        XCTAssertEqual(v.slopeLimitBytesPerCycle, 0.005 * Double(20 * mib + 131_072), accuracy: 0.01)
    }

    func testAStepFailsTheBound() {
        // Flat, then one jump of 4 MiB at the last cycle: the slope over 8 points stays near the limit's
        // order but the bound (20 MiB + 2 MiB) is crossed.
        let v = recorder(cycles: 12) { (c: Int) -> Int in c == 11 ? 24 * self.mib : 20 * self.mib }.verdict()
        XCTAssertTrue(v.failedRules.contains(.memoryBound), v.summary)
        XCTAssertEqual(v.boundBytes, Double(22 * mib))
    }

    func testTooFewCyclesIsInconclusiveNeverAPass() {
        let v = recorder(cycles: 4) { (_: Int) -> Int in 1_000 }.verdict()
        XCTAssertEqual(v.outcome, .inconclusive)
        XCTAssertEqual(v.failedRules, [.tooFewCycles])
        XCTAssertEqual(v.measuredCycles, 2)
        XCTAssertFalse(v.passed)
    }

    func testAnyRenderErrorFails() {
        var r = recorder(cycles: 6) { (_: Int) -> Int in 1_000 }
        for i in 0..<25 { r.record(error: RenderSoakError(frame: i, scene: "a", message: "fault \(i)")) }
        let v = r.verdict()
        XCTAssertEqual(v.failedRules, [.renderErrors])
        XCTAssertEqual(v.errorCount, 25)
        XCTAssertEqual(r.errors.count, RenderSoakRecorder.keptErrors, "the first 20 are kept")
    }

    func testPoolBaselineDriftFailsAndTheWarmUpIsExempt() {
        var r = RenderSoakRecorder()
        for c in 0..<6 {
            r.record(cycle: RenderSoakCycleSample(cycle: c, memoryHighWaterBytes: 1_000, memoryEndBytes: 1_000))
            // Scene "a" changes during the warm-up (allowed), then is stable; scene "b" gains a texture in cycle 4.
            r.record(dwell: RenderSoakDwellSample(cycle: c, scene: "a", checkedOutTextures: c == 0 ? 5 : 3, checkedOutBytes: 300,
                                                  liveScenes: 1))
            r.record(dwell: RenderSoakDwellSample(cycle: c, scene: "b", checkedOutTextures: c >= 4 ? 3 : 2, checkedOutBytes: 200,
                                                  liveScenes: 1))
        }
        let v = r.verdict()
        XCTAssertEqual(v.failedRules, [.poolBaseline], v.summary)
        XCTAssertEqual(v.baselineMismatches.count, 2)
        XCTAssertTrue(v.baselineMismatches[0].hasPrefix("b cycle 4"), v.baselineMismatches[0])
    }

    func testLiveObjectsAndReleaseRules() {
        var r = recorder(cycles: 6) { (_: Int) -> Int in 1_000 }
        r.record(dwell: RenderSoakDwellSample(cycle: 5, scene: "a", checkedOutTextures: 3, checkedOutBytes: 300, liveScenes: 2))
        r.record(release: RenderSoakRelease(checkedOutTextures: 1, liveObjects: 0))
        XCTAssertEqual(r.verdict().failedRules, [.liveObjects, .releaseNotEmpty])
    }

    func testSlopeHelper() {
        XCTAssertEqual(RenderSoakRecorder.slope([]), 0)
        XCTAssertEqual(RenderSoakRecorder.slope([5]), 0)
        XCTAssertEqual(RenderSoakRecorder.slope([1, 3, 5, 7]), 2, accuracy: 1e-12)
        XCTAssertEqual(RenderSoakRecorder.slope([4, 4, 4]), 0, accuracy: 1e-12)
    }

    func testTheReportCarriesTheVerdict() {
        let r = recorder(cycles: 6) { (_: Int) -> Int in 1_000 }
        let report = RenderSoakReport(name: "t", platform: "test", memorySource: "poolEstimate", width: 1, height: 1, frames: 6,
                                      simulatedSeconds: 0.1, wallSeconds: 0, switches: 5, cycles: 6, settings: [:], recorder: r)
        XCTAssertTrue(report.verdict.passed, report.verdict.summary)
        XCTAssertEqual(report.samples.count, 6)
        XCTAssertEqual(report.release, RenderSoakRelease(checkedOutTextures: 0, liveObjects: 0))
    }
}
