// SHD-001-T14 (US3; SHD-001-R5, R10): motion is integrated from frame durations and music changes
// only speed, through a slew-limited level. CPU only; runs on Linux.
import ProceduralMaterials
import XCTest

final class MaterialMotionTests: XCTestCase {
    private let dt = 1.0 / 60

    func testPhaseAccumulatesSpeedTimesDuration() {
        var m = MaterialMotion()
        for _ in 0..<60 { m.advance(frameDuration: dt, bandLevel: 0, speed: 0.5, reactivity: 1) }
        XCTAssertEqual(m.phase, 0.5, accuracy: 1e-9)
        XCTAssertEqual(m.audioLevel, 0)
        m.advance(frameDuration: dt, bandLevel: 0, speed: -0.5, reactivity: 0)
        XCTAssertEqual(m.phase, 0.5 - 0.5 * dt, accuracy: 1e-9)
    }

    func testDurationIsClampedAndNonFiniteInputsReadZero() {
        var m = MaterialMotion()
        m.advance(frameDuration: 5, bandLevel: 0, speed: 1, reactivity: 0)
        XCTAssertEqual(m.phase, 0.1, accuracy: 1e-12, "a stall never jumps the picture")
        m.advance(frameDuration: .nan, bandLevel: .nan, speed: 1, reactivity: 1)
        m.advance(frameDuration: -1, bandLevel: 1, speed: 1, reactivity: 1)
        m.advance(frameDuration: dt, bandLevel: 0, speed: .infinity, reactivity: .nan)
        XCTAssertEqual(m.phase, 0.1, accuracy: 1e-12)
        XCTAssertEqual(m.audioLevel, 0)
    }

    func testLevelRiseAndFallAreSlewLimited() {
        var m = MaterialMotion()
        m.advance(frameDuration: dt, bandLevel: 1, speed: 0, reactivity: 1)
        XCTAssertEqual(m.audioLevel, 4 * dt, accuracy: 1e-12)
        for _ in 0..<20 { m.advance(frameDuration: dt, bandLevel: 1, speed: 0, reactivity: 1) }
        XCTAssertEqual(m.audioLevel, 1, "reached within 0.25 s")
        m.advance(frameDuration: dt, bandLevel: 0, speed: 0, reactivity: 1)
        XCTAssertEqual(m.audioLevel, 1 - dt, accuracy: 1e-12)
        m.advance(frameDuration: dt, bandLevel: 7, speed: 0, reactivity: 1)
        XCTAssertLessThanOrEqual(m.audioLevel, 1)
    }

    func testMusicAtMostDoublesTheSpeed() {
        var m = MaterialMotion()
        for _ in 0..<30 { m.advance(frameDuration: dt, bandLevel: 1, speed: 0, reactivity: 1) }
        XCTAssertEqual(m.speedMultiplier(reactivity: 1), 2)
        XCTAssertEqual(m.speedMultiplier(reactivity: 5), 2)
        XCTAssertEqual(m.speedMultiplier(reactivity: 0.25), 1.25)
        let before = m.phase
        m.advance(frameDuration: dt, bandLevel: 1, speed: 1, reactivity: 1)
        XCTAssertEqual(m.phase - before, 2 * dt, accuracy: 1e-12)
        m.reset()
        XCTAssertEqual(m, MaterialMotion())
    }

    func testBandLevelIgnoresNaNAndClamps() {
        func level(_ v: [Float]) -> Double { v.withUnsafeBufferPointer { MaterialMotion.bandLevel($0) } }
        XCTAssertEqual(level([]), 0)
        XCTAssertEqual(level([0.2, 0.4]), 0.3, accuracy: 1e-6)
        XCTAssertEqual(level([.nan, 0.5, .infinity]), 0.5, accuracy: 1e-6)
        XCTAssertEqual(level([5, -1]), 0.5, accuracy: 1e-6)
        XCTAssertEqual(level([.nan]), 0)
    }
}
