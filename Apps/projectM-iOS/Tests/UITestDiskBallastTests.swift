// UITestDiskBallastTests.swift — QA-011 pass 3 (D3): the DEBUG disk ballast (REC-009-T11, REC-015-T17) never left
// "state=filling ballastMB=0" while it extended 43 GB in one step. These host tests check the bounded fill without
// writing more than a few MB: a target above the free space holds at once, a zero budget ends `slow` before writing,
// and a small gap is filled in steps with a progress line each. Simulator results are never device evidence.
#if DEBUG
import XCTest
@testable import projectM_iOS

final class UITestDiskBallastTests: XCTestCase {
    private var url: URL!

    override func setUp() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("BallastTest-\(UUID().uuidString).bin")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
    }

    private func importantFree() throws -> Int64 {
        let r = BallastWriter.readings(url)
        try XCTSkipIf(r.important <= 0 || r.real <= 0, "no volume readings on this host")
        return r.important
    }

    func testATargetAboveTheFreeSpaceHoldsWithoutWriting() throws {
        let free = try importantFree()
        var progress: [String] = []
        let line = BallastWriter(url: url).fill(toFree: free + 10_000_000_000) { progress.append($0) }
        XCTAssertTrue(line.hasPrefix("state=holding ballastMB=0 "), line)
        XCTAssertEqual(progress, [], "nothing was written")
    }

    func testAZeroBudgetEndsSlowBeforeWriting() throws {
        _ = try importantFree()
        var progress: [String] = []
        let line = BallastWriter(url: url).fill(toFree: 1_000_000, budgetSeconds: 0) { progress.append($0) }
        XCTAssertTrue(line.hasPrefix("state=slow ballastMB=0 "), line)
        XCTAssertEqual(progress, [])
        XCTAssertEqual((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? -1, 0)
    }

    /// QA-011 rerun 4 (D3): the ballast aims at the figure the disk guard reads, the smaller of the two capacities.
    func testTheBallastReadsWhatTheGuardReads() throws {
        _ = try importantFree()
        let r = BallastWriter.readings(url)
        XCTAssertEqual(r.reading, min(r.important, r.real))
        let line = BallastWriter(url: url).fill(toFree: r.reading + 10_000_000_000)
        XCTAssertTrue(line.contains(" guardMB="), line)
    }

    /// QA-011 pass 5 (D3): the growth stopped up to a whole 10 MB step above the reserve (guardMB=211) while the guard
    /// stops a low-rate recording only below reserve + about 1.6 MB, so REC-015-T17 ran 150 s without a stop. The last
    /// step is shortened to land within the guard's lowest stop line, never below the reserve or the real floor.
    func testTheLastGrowthStepLandsBelowTheGuardsLowestStopLine() {
        let reserve = UITestDiskBallast.reserveBytes, realFloor = UITestDiskBallast.realFloorBytes, step: Int64 = 10_000_000
        func grown(from reading: Int64) -> Int64 {
            reading - BallastWriter.growthStep(step: step, reading: reading, real: reading, floor: reserve, realFloor: realFloor)
        }
        XCTAssertEqual(BallastWriter.growthStep(step: step, reading: reserve + 500_000_000, real: reserve + 500_000_000,
                                                floor: reserve, realFloor: realFloor), step, "far from the floor: a whole step")
        // The pass 5 case: 9 MB above the reserve, where the old rule refused the step.
        let landed = grown(from: reserve + 9_000_000)
        XCTAssertEqual(landed, reserve + BallastWriter.floorMarginBytes)
        // The guard's lowest stop line: reserve + 10 s at the 1 Mb/s minimum rate with 25 % headroom.
        let lowestStopLine = reserve + 10 * (1_000_000 * 125 + 799) / 800
        XCTAssertLessThan(landed, lowestStopLine, "the guard stops even the lowest-rate recording")
        XCTAssertEqual(BallastWriter.growthStep(step: step, reading: landed, real: landed, floor: reserve, realFloor: realFloor), 0,
                       "at the floor: no more growth")
        XCTAssertEqual(BallastWriter.growthStep(step: step, reading: reserve - 1, real: reserve - 1, floor: reserve, realFloor: realFloor), 0,
                       "never below the reserve")
        XCTAssertEqual(BallastWriter.growthStep(step: step, reading: reserve + 50_000_000, real: realFloor + 3_000_000,
                                                floor: reserve, realFloor: realFloor), 3_000_000, "the real-space floor holds")
    }

    func testTheFillStepIsBoundedSoProgressShows() {
        XCTAssertLessThanOrEqual(BallastWriter.fillStepBytes, 1_000_000_000, "a step a device writes in seconds")
        XCTAssertGreaterThan(UITestDiskBallast.fillBudgetSeconds, 0)
        XCTAssertLessThan(UITestDiskBallast.fillBudgetSeconds + 150, 600, "fill plus the guard's 150 s stays under 10 min")
    }
}
#endif
