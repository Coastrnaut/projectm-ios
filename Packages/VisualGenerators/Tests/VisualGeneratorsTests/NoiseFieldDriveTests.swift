// NoiseFieldDriveTests.swift — VIS-013-T07 (VIS-013-R5, R7, R8, S2): the bands move warp and brightness smoothly to
// their documented values on frame time, brightness never exceeds 0.8, the drift follows the injected clock (bounded,
// never backwards), Reduce Motion halves drift and band warp, and bad bands read as silence. Pure Swift.
import XCTest
@testable import VisualGenerators

final class NoiseFieldDriveTests: XCTestCase {
    private func run(_ drive: inout NoiseFieldDrive, groups: MandalaBandGroups, frames: Range<Int>,
                     configuration: NoiseFieldConfiguration = NoiseFieldConfiguration()) {
        for f in frames {
            drive.advance(groups: groups, timeNanoseconds: UInt64(f) * 1_000_000_000 / 60, frameDuration: 1.0 / 60,
                          configuration: configuration)
        }
    }

    func testSilenceAndFullBandsSettleToTheirValues() {
        var drive = NoiseFieldDrive()
        run(&drive, groups: .silence, frames: 0..<120)
        XCTAssertEqual(drive.warp, 0.5, accuracy: 0.005)
        XCTAssertEqual(drive.brightness, 0.5, accuracy: 0.005)
        run(&drive, groups: MandalaBandGroups(low: 1, mid: 1, high: 1), frames: 120..<300)
        XCTAssertEqual(drive.warp, 1.5, accuracy: 0.015)
        XCTAssertEqual(drive.brightness, 0.8, accuracy: 0.008)
        run(&drive, groups: MandalaBandGroups(low: 9, mid: 9, high: 9), frames: 300..<600)
        XCTAssertLessThanOrEqual(drive.brightness, 0.8, "never above ACC-012's cap")
    }

    func testSmoothingFollowsFrameTimeNotFrameCount() {
        var fast = NoiseFieldDrive(), slow = NoiseFieldDrive()
        let loud = MandalaBandGroups(low: 1, mid: 1, high: 1)
        for f in 0..<24 {   // 0.2 s at 120 Hz
            fast.advance(groups: loud, timeNanoseconds: UInt64(f) * 1_000_000_000 / 120, frameDuration: 1.0 / 120,
                         configuration: NoiseFieldConfiguration())
        }
        for f in 0..<12 {   // 0.2 s at 60 Hz
            slow.advance(groups: loud, timeNanoseconds: UInt64(f) * 1_000_000_000 / 60, frameDuration: 1.0 / 60,
                         configuration: NoiseFieldConfiguration())
        }
        XCTAssertEqual(fast.brightness, slow.brightness, accuracy: 1e-9)
        let expected: Double = 0.5 + 0.3 * (1 - exp(-0.2 / 0.25))
        XCTAssertEqual(slow.brightness, expected, accuracy: 1e-9)
    }

    func testDriftFollowsTheClockBoundedAndNeverBackwards() {
        var drive = NoiseFieldDrive()
        let c = NoiseFieldConfiguration()
        drive.advance(groups: .silence, timeNanoseconds: 5_000_000_000, frameDuration: 0, configuration: c)
        XCTAssertEqual(drive.phase, 0, "the first frame is the anchor")
        drive.advance(groups: .silence, timeNanoseconds: 6_000_000_000, frameDuration: 1, configuration: c)
        XCTAssertEqual(drive.phase, 0.12, accuracy: 1e-12)
        drive.advance(groups: .silence, timeNanoseconds: 4_000_000_000, frameDuration: 0, configuration: c)
        XCTAssertEqual(drive.phase, 0.12, accuracy: 1e-12, "time going backwards does nothing")
        drive.advance(groups: .silence, timeNanoseconds: 60_000_000_000, frameDuration: 54, configuration: c)
        XCTAssertEqual(drive.phase, 0.24, accuracy: 1e-12, "a long gap advances at most 1 s")
        drive.reset()
        XCTAssertEqual(drive, NoiseFieldDrive())
    }

    func testReduceMotionHalvesDriftAndBandWarp() {
        var drive = NoiseFieldDrive()
        let c = NoiseFieldConfiguration(reduceMotion: true)
        run(&drive, groups: MandalaBandGroups(low: 1, mid: 0, high: 0), frames: 0..<301, configuration: c)
        XCTAssertEqual(drive.warp, 1.0, accuracy: 0.01)
        XCTAssertEqual(drive.phase, 0.06 * 5, accuracy: 1e-9)
    }

    func testBadBandsReadAsSilenceAndConfigurationClamps() {
        let bad: [Float] = [.nan, -.infinity, -3, .nan, .nan, .nan]
        let groups: MandalaBandGroups = bad.withUnsafeBufferPointer { (b: UnsafeBufferPointer<Float>) -> MandalaBandGroups in
            MandalaBandGroups.from(b)
        }
        let target: (warp: Double, brightness: Double) = NoiseFieldDrive.targets(groups, configuration: NoiseFieldConfiguration())
        XCTAssertEqual(target.warp, 0.5)
        XCTAssertEqual(target.brightness, 0.5)
        let c = NoiseFieldConfiguration(frequency: .nan, octaves: 40, seed: 70_000)
        XCTAssertEqual(c.frequency, 4)
        XCTAssertEqual(c.octaves, 6)
        XCTAssertEqual(c.seed, 1301)
    }
}
