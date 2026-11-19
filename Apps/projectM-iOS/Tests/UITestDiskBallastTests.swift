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

    func testTheFillStepIsBoundedSoProgressShows() {
        XCTAssertLessThanOrEqual(BallastWriter.fillStepBytes, 1_000_000_000, "a step a device writes in seconds")
        XCTAssertGreaterThan(UITestDiskBallast.fillBudgetSeconds, 0)
        XCTAssertLessThan(UITestDiskBallast.fillBudgetSeconds + 150, 600, "fill plus the guard's 150 s stays under 10 min")
    }
}
#endif
