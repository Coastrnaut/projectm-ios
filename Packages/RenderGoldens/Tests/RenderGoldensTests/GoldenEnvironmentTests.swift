// QA-002-T05, T15: the record policy and CI guard, and the suite's decision table (contract G4;
// QA-002-R9, R11, R12). Plain Swift: runs on Linux.
import GoldenImages
import XCTest

final class GoldenEnvironmentTests: XCTestCase {
    func testRecordPolicy() {
        XCTAssertEqual(GoldenRecordPolicy.from(environment: [:]), .compare)
        XCTAssertEqual(GoldenRecordPolicy.from(environment: ["GOLDEN_RECORD": "0"]), .compare)
        XCTAssertEqual(GoldenRecordPolicy.from(environment: ["GOLDEN_RECORD": "1"]), .record)
        XCTAssertEqual(GoldenRecordPolicy.from(environment: ["GOLDEN_RECORD": "1", "CI": "true"]), .refused)
        XCTAssertEqual(GoldenRecordPolicy.from(environment: ["GOLDEN_RECORD": "1", "GITHUB_ACTIONS": "true"]), .refused)
        XCTAssertEqual(GoldenRecordPolicy.from(environment: ["GOLDEN_RECORD": "1", "CI": ""]), .record, "an empty variable is not CI")
        XCTAssertEqual(GoldenRecordPolicy.from(environment: ["CI": "true"]), .compare, "CI compares")
    }

    func testOSVersionIsMajorMinor() {
        let parts = GoldenOS.currentVersion.split(separator: ".")
        XCTAssertEqual(parts.count, 2)
        XCTAssertTrue(parts.allSatisfy { (p: Substring) -> Bool in Int(p) != nil })
    }

    private func result(_ outcome: GoldenComparisonResult.Outcome) -> GoldenComparisonResult {
        GoldenComparisonResult(outcome: outcome, changedPixels: 1, exceedingPixels: outcome == .exceedsTolerance ? 20 : 0,
                               maxChannelDifference: 9, allowedPixels: 12, totalPixels: 12_288)
    }

    private func decide(_ policy: GoldenRecordPolicy, _ comparison: GoldenComparisonResult?, platform: GoldenPlatformClass? = .macOS,
                        osSensitive: Bool = false, recordedOS: String? = "27.2", currentOS: String = "27.2") -> GoldenVerdict {
        GoldenDecision.decide(capture: "c", platform: platform, policy: policy, comparison: comparison, osSensitive: osSensitive,
                              recordedOS: recordedOS, currentOS: currentOS)
    }

    func testDecisionTable() {
        let passing = result(.withinTolerance), failing = result(.exceedsTolerance)
        // Compare.
        guard case .pass = decide(.compare, passing) else { return XCTFail("passing golden") }
        XCTAssertTrue(decide(.compare, failing).isFailure)
        XCTAssertTrue(decide(.compare, result(.sizeMismatch)).isFailure)
        guard case let .fail(missing) = decide(.compare, nil) else { return XCTFail("missing golden must fail") }
        XCTAssertTrue(missing.contains("GOLDEN_RECORD=1"))
        // Record.
        guard case .write = decide(.record, nil) else { return XCTFail("record writes a missing golden") }
        guard case .write = decide(.record, failing) else { return XCTFail("record replaces a failing golden") }
        guard case .pass = decide(.record, passing) else { return XCTFail("record keeps a passing golden") }
        // Refused (CI): always a failure, whatever the golden.
        for comparison in [nil, passing, failing] { XCTAssertTrue(decide(.refused, comparison).isFailure) }
        // No platform class (a device): pending, never passed or failed.
        guard case .pending = decide(.compare, failing, platform: nil) else { return XCTFail("device is pending") }
        guard case .pending = decide(.refused, nil, platform: nil) else { return XCTFail("device is pending") }
    }

    /// QA-002-R12: a text scene compares only on the recorded OS version.
    func testOSSensitiveScenesCompareOnlyOnTheRecordedOS() {
        let failing = result(.exceedsTolerance)
        guard case .notCompared = decide(.compare, failing, osSensitive: true, recordedOS: "27.2", currentOS: "26.5") else {
            return XCTFail("other OS: not compared")
        }
        XCTAssertTrue(decide(.compare, failing, osSensitive: true, recordedOS: "27.2", currentOS: "27.2").isFailure)
        XCTAssertTrue(decide(.compare, failing, osSensitive: false, recordedOS: "27.2", currentOS: "26.5").isFailure,
                      "other scenes compare on every OS")
        XCTAssertTrue(decide(.compare, nil, osSensitive: true, recordedOS: "27.2", currentOS: "26.5").isFailure,
                      "a missing golden still fails")
    }
}
