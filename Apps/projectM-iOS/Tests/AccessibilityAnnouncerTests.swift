// AccessibilityAnnouncerTests.swift — ACC-004-T03 (ACC-004-R7, S3, S4; data-model "AnnouncementGate").
// The gate takes times as input and the announcer gets a fake clock and a manual scheduler, so no
// test waits or reads the wall clock.
import XCTest
@testable import projectM_iOS

final class AccessibilityAnnouncerTests: XCTestCase {
    /// A clock the test advances by hand.
    @MainActor private final class FakeClock {
        var now: Double
        init(now: Double) { self.now = now }
    }

    // MARK: - Gate

    func testASingleSubmissionIsSpokenAtOnce() {
        var gate = AnnouncementGate()
        XCTAssertEqual(gate.submit("Preset: A", kind: .preset, now: 10), .speak)
        XCTAssertNil(gate.windowClosed(kind: .preset, now: 11), "nothing pending: the window just closes")
        XCTAssertEqual(gate.submit("Preset: B", kind: .preset, now: 11.2), .speak, "a new burst speaks at once")
    }

    func testABurstOfTwoSpeaksBothTheSecondAfterTheWindow() {
        var gate = AnnouncementGate()
        XCTAssertEqual(gate.submit("Preset: A", kind: .preset, now: 0), .speak)
        XCTAssertEqual(gate.submit("Preset: B", kind: .preset, now: 0.3), .wait(until: 1.0))
        XCTAssertEqual(gate.windowClosed(kind: .preset, now: 1.0), "Preset: B")
        XCTAssertNil(gate.windowClosed(kind: .preset, now: 2.0))
    }

    func testABurstOfFiveSpeaksAtMostTwiceEndingWithTheLatest() {
        var gate = AnnouncementGate()
        var spoken: [String] = []
        for (i, t) in [0.0, 0.2, 0.4, 0.6, 0.8].enumerated() {
            if gate.submit("Preset: \(i)", kind: .preset, now: t) == .speak { spoken.append("Preset: \(i)") }
        }
        if let text = gate.windowClosed(kind: .preset, now: 1.0) { spoken.append(text) }
        XCTAssertNil(gate.windowClosed(kind: .preset, now: 2.0))
        XCTAssertEqual(spoken, ["Preset: 0", "Preset: 4"])
    }

    func testAnIdenticalRepeatIsDroppedWithinTwoSecondsAndSpokenAfter() {
        var gate = AnnouncementGate()
        XCTAssertEqual(gate.submit("Visualization paused", kind: .playback, now: 0), .speak)
        _ = gate.windowClosed(kind: .playback, now: 1)
        XCTAssertEqual(gate.submit("Visualization paused", kind: .playback, now: 1.5), .drop)
        XCTAssertEqual(gate.submit("Visualization paused", kind: .playback, now: 2.5), .speak)
    }

    func testReturningToTheSpokenStateInsideTheWindowSpeaksNothingMore() {
        var gate = AnnouncementGate()
        XCTAssertEqual(gate.submit("Output blacked out", kind: .output, now: 0), .speak)
        XCTAssertEqual(gate.submit("Output restored", kind: .output, now: 0.2), .wait(until: 1))
        XCTAssertEqual(gate.submit("Output blacked out", kind: .output, now: 0.4), .drop)
        XCTAssertNil(gate.windowClosed(kind: .output, now: 1), "the latest state was already spoken")
    }

    func testKindsAreLimitedIndependently() {
        var gate = AnnouncementGate()
        XCTAssertEqual(gate.submit("Preset: A", kind: .preset, now: 0), .speak)
        XCTAssertEqual(gate.submit("Output blacked out", kind: .output, now: 0.1), .speak, "a preset burst never holds a blackout")
        XCTAssertEqual(gate.submit("Preset: B", kind: .preset, now: 0.2), .wait(until: 1))
        XCTAssertTrue(gate.hasPending(.preset))
        XCTAssertFalse(gate.hasPending(.output))
    }

    // MARK: - Announcer

    @MainActor
    func testTheAnnouncerPostsLeadingAndTrailingThroughItsScheduler() {
        let clock = FakeClock(now: 100)
        var posted: [String] = []
        var scheduled: [(Double, @MainActor () -> Void)] = []
        let announcer = AccessibilityAnnouncer(post: { (text: String) in posted.append(text) },
                                               now: { () -> Double in clock.now },
                                               schedule: { (delay: Double, action: @escaping @MainActor () -> Void) in
                                                   scheduled.append((delay, action))
                                               })
        for name in ["A", "B", "C"] {
            announcer.announce(AccessibilityAnnouncer.presetText(name), kind: .preset)
            clock.now += 0.1
        }
        XCTAssertEqual(posted, ["Preset: A"])
        XCTAssertEqual(scheduled.count, 1)
        XCTAssertEqual(scheduled.first?.0, AnnouncementGate.window)
        clock.now = 101
        let close = scheduled.removeFirst().1
        close()
        XCTAssertEqual(posted, ["Preset: A", "Preset: C"])
        XCTAssertEqual(announcer.lastSpoken, "preset|Preset: C")
        XCTAssertEqual(scheduled.count, 1, "the trailing text opens a new window")
        clock.now = 102
        scheduled.removeFirst().1()
        XCTAssertEqual(posted.count, 2)
        XCTAssertTrue(scheduled.isEmpty)
        announcer.announce("", kind: .preset)
        XCTAssertEqual(posted.count, 2, "empty text is never posted")
    }

    func testTexts() {
        XCTAssertEqual(AccessibilityAnnouncer.presetText("Fumbling Foo"), "Preset: Fumbling Foo")
        XCTAssertEqual(AccessibilityAnnouncer.pausedText(true), "Visualization paused")
        XCTAssertEqual(AccessibilityAnnouncer.pausedText(false), "Visualization resumed")
        XCTAssertEqual(AccessibilityAnnouncer.blackoutText(true), "Output blacked out")
        XCTAssertEqual(AccessibilityAnnouncer.blackoutText(false), "Output restored")
        XCTAssertEqual(AccessibilityAnnouncer.recordingText(true), "Recording started")
        XCTAssertEqual(AccessibilityAnnouncer.recordingText(false), "Recording stopped")
        XCTAssertEqual(AccessibilityAnnouncer.favoriteText("X", added: true), "Added to favorites: X")
        XCTAssertEqual(AccessibilityAnnouncer.favoriteText("X", added: false), "Removed from favorites: X")
    }
}
