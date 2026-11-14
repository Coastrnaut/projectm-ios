// FrameDropCounterTests.swift — PERF-007-T03, T04 (specs/192-perf-007-frame-drop-telemetry; contract C1, C2). Pure
// Swift, runs on Linux. Every time is injected (display-link timestamps and presented times in seconds): no wall clock.
import Dispatch
import FrameTiming
import XCTest

final class FrameDropCounterTests: XCTestCase {
    /// 60 Hz.
    private let period: Double = 1.0 / 60

    /// Submits a frame at refresh slot `slot` (timestamp = slot × period, target one period later).
    private func submit(_ counter: FrameDropCounter, slot: Int, session: FrameDropSession? = nil) -> FrameDropTicket? {
        let timestamp: Double = 100 + Double(slot) * period
        return counter.submit(session ?? counter.session, timestamp: timestamp, targetTimestamp: timestamp + period)
    }

    // MARK: - Acceptance (PERF-007-S1)

    /// Spec US1 scenario 1 plus duplicates: exact counts, every duplicate counted once.
    func testInjectedSequenceGivesExactCountsAndDuplicatesCountOnce() throws {
        let counter = FrameDropCounter()
        counter.beginSession(measuresPresentation: true)
        // Frames 1-5 at slots 0, 1, 2, 4, 5: slot 3 is missed.
        let tickets: [FrameDropTicket] = try [0, 1, 2, 4, 5].map { (slot: Int) -> FrameDropTicket in
            try XCTUnwrap(submit(counter, slot: slot))
        }
        XCTAssertEqual(tickets.map(\.frameID), [1, 2, 3, 4, 5])
        // A repeated display-link timestamp (slot 5 again) is no frame and no slot.
        XCTAssertNil(submit(counter, slot: 5))
        // Frame 3 shown 0.6 intervals after its target (late); frame 5 never shown.
        counter.presented(tickets[0], presentedTime: tickets[0].targetTime)
        counter.presented(tickets[1], presentedTime: tickets[1].targetTime + 0.4 * period)   // within half an interval
        counter.presented(tickets[2], presentedTime: tickets[2].targetTime + 0.6 * period)
        counter.presented(tickets[3], presentedTime: tickets[3].targetTime - 0.001)           // early: not late
        counter.presented(tickets[4], presentedTime: 0)
        // Duplicates of every report.
        for ticket in tickets { counter.presented(ticket, presentedTime: ticket.targetTime + period) }
        counter.presented(tickets[2], presentedTime: tickets[2].targetTime + 0.6 * period)
        XCTAssertEqual(counter.counts(), FrameDropCounts(submitted: 5, skipped: 1, presented: 4, late: 1, discarded: 1, stale: 0))
    }

    func testOutOfOrderReportsWithinTheWindowCountOnce() throws {
        let counter = FrameDropCounter()
        counter.beginSession(measuresPresentation: true)
        let tickets: [FrameDropTicket] = try (0..<20).map { (slot: Int) -> FrameDropTicket in try XCTUnwrap(submit(counter, slot: slot)) }
        // 20 first, then 19 down to 4 (within 16 below 20), each twice; 1-3 are too old once 20 was counted.
        counter.presented(tickets[19], presentedTime: tickets[19].targetTime)
        for index in stride(from: 18, through: 0, by: -1) {
            counter.presented(tickets[index], presentedTime: tickets[index].targetTime)
            counter.presented(tickets[index], presentedTime: tickets[index].targetTime)
        }
        counter.presented(tickets[19], presentedTime: tickets[19].targetTime)
        XCTAssertEqual(counter.counts().presented, 17, "frames 4-20 once each; 1-3 fell out of the 16-frame window")
        XCTAssertEqual(counter.counts().submitted, 20)
        XCTAssertEqual(counter.counts().skipped, 0)
    }

    /// Presented reports on several threads at once, each frame reported four times: each frame counts once.
    func testConcurrentDuplicateReportsCountOnce() throws {
        let counter = FrameDropCounter()
        counter.beginSession(measuresPresentation: true)
        let tickets: [FrameDropTicket] = try (0..<200).map { (slot: Int) -> FrameDropTicket in try XCTUnwrap(submit(counter, slot: slot)) }
        DispatchQueue.concurrentPerform(iterations: 800) { (index: Int) -> Void in
            let ticket: FrameDropTicket = tickets[index / 4]
            counter.presented(ticket, presentedTime: ticket.targetTime)
        }
        let counts: FrameDropCounts = counter.counts()
        // In-order delivery is not guaranteed across threads; a frame more than 16 behind the newest may be refused,
        // never counted twice.
        XCTAssertLessThanOrEqual(try XCTUnwrap(counts.presented), 200)
        XCTAssertGreaterThan(try XCTUnwrap(counts.presented), 0)
        // Delivered in order from many threads (each frame's four reports race each other): exactly once each.
        let ordered = FrameDropCounter()
        ordered.beginSession(measuresPresentation: true)
        let orderedTickets: [FrameDropTicket] = try (0..<200).map { (slot: Int) -> FrameDropTicket in try XCTUnwrap(submit(ordered, slot: slot)) }
        for ticket in orderedTickets {
            DispatchQueue.concurrentPerform(iterations: 4) { (_: Int) -> Void in ordered.presented(ticket, presentedTime: ticket.targetTime) }
        }
        XCTAssertEqual(ordered.counts().presented, 200)
    }

    // MARK: - Sessions (PERF-007-S2)

    func testANewSessionZeroesEveryCountAndIgnoresTheOldSessionsLateReports() throws {
        let counter = FrameDropCounter()
        let first: FrameDropSession = counter.beginSession(measuresPresentation: true)
        let old1 = try XCTUnwrap(submit(counter, slot: 0))
        let old2 = try XCTUnwrap(submit(counter, slot: 3))
        counter.presented(old1, presentedTime: old1.targetTime)
        XCTAssertEqual(counter.counts().submitted, 2)
        let second: FrameDropSession = counter.beginSession(measuresPresentation: true)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(counter.counts(), FrameDropCounts(submitted: 0, skipped: 0, presented: 0, late: 0, discarded: 0, stale: 0))
        // The old session's reports arrive late, and its frame thread submits once more with the old token.
        counter.presented(old2, presentedTime: old2.targetTime + 2 * period)
        counter.presented(old1, presentedTime: old1.targetTime)
        XCTAssertNil(submit(counter, slot: 10, session: first))
        // A new frame of the new session: its ID restarts at 1 and is counted normally.
        let fresh = try XCTUnwrap(submit(counter, slot: 11))
        XCTAssertEqual(fresh.frameID, 1)
        counter.presented(fresh, presentedTime: fresh.targetTime)
        XCTAssertEqual(counter.counts(), FrameDropCounts(submitted: 1, skipped: 0, presented: 1, late: 0, discarded: 0, stale: 3))
    }

    func testAReportForAFrameNeverSubmittedIsStale() {
        let counter = FrameDropCounter()
        let session = counter.beginSession(measuresPresentation: true)
        counter.presented(FrameDropTicket(session: session, frameID: 9, targetTime: 1, refreshInterval: period), presentedTime: 1)
        XCTAssertEqual(counter.counts().presented, 0)
        XCTAssertEqual(counter.counts().stale, 1)
    }

    func testNoSessionCountsNothing() {
        let counter = FrameDropCounter()
        XCTAssertNil(submit(counter, slot: 0))
        XCTAssertEqual(counter.counts().submitted, 0)
    }

    // MARK: - Separation and unavailable (PERF-007-S3, S4)

    func testOutputsNeverAffectEachOther() throws {
        let device = FrameDropCounter()
        let external = FrameDropCounter()
        device.beginSession(measuresPresentation: true)
        external.beginSession(measuresPresentation: true)
        let ticket = try XCTUnwrap(submit(device, slot: 0))
        device.presented(ticket, presentedTime: ticket.targetTime)
        // A device ticket reported to the external counter (same generation number): never issued there → stale.
        external.presented(ticket, presentedTime: ticket.targetTime)
        _ = try XCTUnwrap(submit(external, slot: 0))
        _ = try XCTUnwrap(submit(external, slot: 2))
        XCTAssertEqual(device.counts(), FrameDropCounts(submitted: 1, skipped: 0, presented: 1, late: 0, discarded: 0, stale: 0))
        XCTAssertEqual(external.counts().submitted, 2)
        XCTAssertEqual(external.counts().skipped, 1)
        XCTAssertEqual(external.counts().presented, 0)
    }

    func testAPathWithoutPresentationReportsUnavailable() throws {
        let counter = FrameDropCounter()
        counter.beginSession(measuresPresentation: false)
        _ = try XCTUnwrap(submit(counter, slot: 0))
        _ = try XCTUnwrap(submit(counter, slot: 3))
        let counts: FrameDropCounts = counter.counts()
        XCTAssertEqual(counts, FrameDropCounts(submitted: 2, skipped: 2, presented: nil, late: nil, discarded: nil, stale: 0))
        XCTAssertEqual(counts.line(for: .device),
                       "frames device: presented unavailable, late unavailable, skipped 2, submitted 2, discarded unavailable")
    }

    func testRecordingCountsAndLine() {
        let counts = FrameDropCounts.recording(written: 15, droppedSlots: 5)
        XCTAssertEqual(counts, FrameDropCounts(skipped: 5, presented: 15))
        XCTAssertEqual(counts.line(for: .recording), "frames recording: presented 15, late unavailable, skipped 5")
    }

    func testAnInvalidIntervalInfersNoSlotsAndNoLateness() throws {
        let counter = FrameDropCounter()
        let session = counter.beginSession(measuresPresentation: true)
        _ = try XCTUnwrap(counter.submit(session, timestamp: 1, targetTimestamp: 1))
        let ticket = try XCTUnwrap(counter.submit(session, timestamp: 2, targetTimestamp: .nan))
        counter.presented(ticket, presentedTime: 5)
        XCTAssertEqual(counter.counts(), FrameDropCounts(submitted: 2, skipped: 0, presented: 1, late: 0, discarded: 0, stale: 0))
    }
}
