// PlaybackPositionTests.swift — position arithmetic of the transport (AUD-006-T05; AUD-006-R6,
// R8, R9; data-model.md).
import XCTest
@testable import CaptureKit

final class PlaybackPositionTests: XCTestCase {
    func testClamp() {
        XCTAssertEqual(PlaybackPositionMath.clamp(-5, length: 100), 0)
        XCTAssertEqual(PlaybackPositionMath.clamp(0, length: 100), 0)
        XCTAssertEqual(PlaybackPositionMath.clamp(40, length: 100), 40)
        XCTAssertEqual(PlaybackPositionMath.clamp(100, length: 100), 100)
        XCTAssertEqual(PlaybackPositionMath.clamp(101, length: 100), 100)
        XCTAssertEqual(PlaybackPositionMath.clamp(7, length: 0), 0)
        XCTAssertEqual(PlaybackPositionMath.clamp(7, length: -3), 0)
    }

    func testFrameWithoutLoopStopsAtTheEnd() {
        XCTAssertEqual(PlaybackPositionMath.frame(start: 10, elapsed: 0, length: 100, loops: false), 10)
        XCTAssertEqual(PlaybackPositionMath.frame(start: 10, elapsed: 50, length: 100, loops: false), 60)
        XCTAssertEqual(PlaybackPositionMath.frame(start: 10, elapsed: 90, length: 100, loops: false), 100)
        XCTAssertEqual(PlaybackPositionMath.frame(start: 10, elapsed: 5_000, length: 100, loops: false), 100)
        XCTAssertEqual(PlaybackPositionMath.frame(start: 10, elapsed: -4, length: 100, loops: false), 10, "negative elapsed counts as 0")
    }

    func testFrameWithLoopWraps() {
        XCTAssertEqual(PlaybackPositionMath.frame(start: 10, elapsed: 89, length: 100, loops: true), 99)
        XCTAssertEqual(PlaybackPositionMath.frame(start: 10, elapsed: 90, length: 100, loops: true), 0)
        XCTAssertEqual(PlaybackPositionMath.frame(start: 10, elapsed: 95, length: 100, loops: true), 5)
        XCTAssertEqual(PlaybackPositionMath.frame(start: 10, elapsed: 1_095, length: 100, loops: true), 5)
        XCTAssertEqual(PlaybackPositionMath.frame(start: 0, elapsed: 7, length: 0, loops: true), 0)
        XCTAssertEqual(PlaybackPositionMath.frame(start: 0, elapsed: 7, length: 0, loops: false), 0)
    }

    func testFrameFromSeconds() {
        XCTAssertEqual(PlaybackPositionMath.frame(seconds: 2, sampleRate: 44_100, length: 132_300), 88_200)
        XCTAssertEqual(PlaybackPositionMath.frame(seconds: 0.00001, sampleRate: 44_100, length: 132_300), 0, "rounds to the nearest frame")
        XCTAssertEqual(PlaybackPositionMath.frame(seconds: 0.00002, sampleRate: 44_100, length: 132_300), 1)
        XCTAssertEqual(PlaybackPositionMath.frame(seconds: -1, sampleRate: 44_100, length: 132_300), 0)
        XCTAssertEqual(PlaybackPositionMath.frame(seconds: 99, sampleRate: 44_100, length: 132_300), 132_300)
        XCTAssertEqual(PlaybackPositionMath.frame(seconds: .nan, sampleRate: 44_100, length: 132_300), 0)
        XCTAssertEqual(PlaybackPositionMath.frame(seconds: .infinity, sampleRate: 44_100, length: 132_300), 132_300)
        XCTAssertEqual(PlaybackPositionMath.frame(seconds: -.infinity, sampleRate: 44_100, length: 132_300), 0)
        XCTAssertEqual(PlaybackPositionMath.frame(seconds: 1, sampleRate: 0, length: 132_300), 0)
    }

    func testPositionStaysInsideTheTrack() {
        XCTAssertEqual(PlaybackPosition(seconds: 5, durationSeconds: 3).seconds, 3)
        XCTAssertEqual(PlaybackPosition(seconds: -1, durationSeconds: 3).seconds, 0)
        XCTAssertEqual(PlaybackPosition(seconds: .nan, durationSeconds: 3).seconds, 0)
        XCTAssertEqual(PlaybackPosition(seconds: 1, durationSeconds: -2).durationSeconds, 0)
        XCTAssertEqual(PlaybackPosition(seconds: 1, durationSeconds: -2).seconds, 0)
        XCTAssertEqual(PlaybackPosition.zero, PlaybackPosition(seconds: 0, durationSeconds: 0))
        XCTAssertEqual(PlaybackPosition(seconds: 1, durationSeconds: 4).remainingSeconds, 3)
    }
}
