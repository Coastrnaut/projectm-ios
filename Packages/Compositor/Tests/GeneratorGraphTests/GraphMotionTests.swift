// SHD-002-T19 (US4; SHD-002-R9, R11): phase integration and the bounded music follower. CPU only;
// runs on Linux.
import GeneratorGraph
import XCTest

final class GraphMotionTests: XCTestCase {
    func testPhaseAccumulatesFromClampedFrameDurations() {
        var m = GraphMotion()
        m.advance(frameDuration: 0.5, bandLevel: 0, speed: 1, musicRate: 1)   // clamped to 0.1 s
        XCTAssertEqual(m.phase, 0.1, accuracy: 1e-12)
        m.advance(frameDuration: .nan, bandLevel: 0, speed: 1, musicRate: 1)
        m.advance(frameDuration: -1, bandLevel: 0, speed: 1, musicRate: 1)
        XCTAssertEqual(m.phase, 0.1, accuracy: 1e-12)
        m.advance(frameDuration: 0.05, bandLevel: 0, speed: -0.5, musicRate: 1)
        XCTAssertEqual(m.phase, 0.075, accuracy: 1e-12)
        m.advance(frameDuration: 0.05, bandLevel: 0, speed: .infinity, musicRate: 1)
        XCTAssertEqual(m.phase, 0.075, accuracy: 1e-12)
        m.reset()
        XCTAssertEqual(m, GraphMotion())
    }

    func testMusicFollowerMovesNoFasterThanItsRate() {
        var m = GraphMotion()
        var previous = 0.0
        for i in 0..<240 {
            m.advance(frameDuration: 1.0 / 60, bandLevel: i % 2 == 0 ? 1 : 0, speed: 0, musicRate: 0.25)
            XCTAssertLessThanOrEqual(abs(m.musicLevel - previous), 0.25 / 60 + 1e-12)
            previous = m.musicLevel
        }
        XCTAssertLessThan(m.musicLevel, 0.01, "alternating bands never build up")
        var steady = GraphMotion()
        for _ in 0..<60 { steady.advance(frameDuration: 1.0 / 60, bandLevel: 1, speed: 0, musicRate: 1) }
        XCTAssertEqual(steady.musicLevel, 1, accuracy: 1e-9, "full level after 1 s at rate 1")
        var clamped = GraphMotion()
        clamped.advance(frameDuration: 0.1, bandLevel: 5, speed: 0, musicRate: 9)
        XCTAssertEqual(clamped.musicLevel, 0.1, accuracy: 1e-12, "rate clamped to 1 per second")
        clamped.advance(frameDuration: 0.1, bandLevel: .nan, speed: 0, musicRate: 1)
        XCTAssertEqual(clamped.musicLevel, 0, accuracy: 1e-12)
    }

    func testBandLevel() {
        let values: [Float] = [0.5, .nan, -1, 2, 0.5]
        let level = values.withUnsafeBufferPointer { GraphMotion.bandLevel($0) }
        XCTAssertEqual(level, (0.5 + 0 + 1 + 0.5) / 4, accuracy: 1e-12)
        let none = [Float]().withUnsafeBufferPointer { GraphMotion.bandLevel($0) }
        XCTAssertEqual(none, 0)
    }
}
