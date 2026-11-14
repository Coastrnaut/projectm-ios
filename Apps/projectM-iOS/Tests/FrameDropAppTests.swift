// FrameDropAppTests.swift — PERF-007-T08, T10 (specs/192-perf-007-frame-drop-telemetry): the device counter attached by
// the app, driven with injected display-link times and presented times (no wall clock), the
// attachment's sessions per visual, display and overlay (PERF-007-R6), the external display's output change, the
// overlay's "frames" lines and the export conversion.
import Diagnostics
import FrameRecording
import FrameTiming
import Metal
import PresentationLifecycle
import UIKit
import XCTest
@testable import projectM_iOS

/// A visual that only holds what it was given.
@MainActor
private final class FakeCountedVisual: FrameDropCounted {
    var frameDrops: FrameDropCounter?
    let measuresPresentation: Bool
    init(measuresPresentation: Bool) { self.measuresPresentation = measuresPresentation }
}

/// An injected display clock: the frame loop's tick times and the display's presented reports (what Metal's presented
/// handler delivers on a device; the simulator SDK has none), so no test depends on the wall clock.
private struct InjectedDisplay {
    let period: Double
    var start: Double = 500

    func tick(_ slot: Int) -> (timestamp: Double, target: Double) {
        let timestamp: Double = start + Double(slot) * period
        return (timestamp, timestamp + period)
    }
}

@MainActor
final class FrameDropAppTests: XCTestCase {
    private let period: Double = 1.0 / 60

    /// The device counter attached by the app, driven with an injected clock: exact counts, a duplicated presented
    /// callback counted once.
    func testDeviceCountersWithAnInjectedClock() throws {
        let attachment = FrameDropAttachment()
        let visual = FakeCountedVisual(measuresPresentation: true)
        attachment.sync(overlayShown: true, target: visual, external: false)
        let counter: FrameDropCounter = try XCTUnwrap(visual.frameDrops)
        XCTAssertTrue(counter === attachment.device)
        let display = InjectedDisplay(period: period)
        var tickets: [FrameDropTicket] = []
        for slot in [0, 1, 2, 4, 5] {   // slot 3 missed
            let tick = display.tick(slot)
            tickets.append(try XCTUnwrap(counter.submit(counter.session, timestamp: tick.timestamp, targetTimestamp: tick.target)))
        }
        counter.presented(tickets[0], presentedTime: tickets[0].targetTime)
        counter.presented(tickets[0], presentedTime: tickets[0].targetTime)            // a duplicated callback
        counter.presented(tickets[1], presentedTime: tickets[1].targetTime + 0.2 * period)
        counter.presented(tickets[2], presentedTime: tickets[2].targetTime + 0.75 * period)   // late
        counter.presented(tickets[3], presentedTime: tickets[3].targetTime)
        counter.presented(tickets[4], presentedTime: 0)                               // never shown
        XCTAssertEqual(attachment.device.counts(),
                       FrameDropCounts(submitted: 5, skipped: 1, presented: 4, late: 1, discarded: 1, stale: 0))
        XCTAssertEqual(attachment.lines(recording: nil),
                       ["frames device: presented 4, late 1, skipped 1, submitted 5, discarded 1"])
        XCTAssertEqual(attachment.external.counts().submitted, 0, "the external counter never saw a frame")
    }

    /// Sessions: overlay on, visual change, display change; a late report of the old session is not counted.
    func testSessionsFollowTheVisualTheDisplayAndTheOverlay() throws {
        let attachment = FrameDropAttachment()
        let first = FakeCountedVisual(measuresPresentation: true)
        let second = FakeCountedVisual(measuresPresentation: false)   // projectM-like
        attachment.sync(overlayShown: false, target: first, external: false)
        XCTAssertNil(first.frameDrops, "overlay off: no counting work")
        XCTAssertEqual(attachment.lines(recording: nil), [])

        attachment.sync(overlayShown: true, target: first, external: false)
        XCTAssertEqual(attachment.sessionsBegun, 1)
        let old: FrameDropTicket = try XCTUnwrap(first.frameDrops?.submit(attachment.device.session, timestamp: 10, targetTimestamp: 10 + period))
        attachment.sync(overlayShown: true, target: first, external: false)
        XCTAssertEqual(attachment.sessionsBegun, 1, "the same visual on the same display keeps its session")
        XCTAssertEqual(attachment.device.counts().submitted, 1)

        attachment.sync(overlayShown: true, target: second, external: false)
        XCTAssertNil(first.frameDrops)
        XCTAssertTrue(second.frameDrops === attachment.device)
        XCTAssertEqual(attachment.sessionsBegun, 2)
        attachment.device.presented(old, presentedTime: 10 + period)   // the old session's report arrives late
        XCTAssertEqual(attachment.device.counts(), FrameDropCounts(submitted: 0, skipped: 0, stale: 1))
        XCTAssertEqual(attachment.lines(recording: nil),
                       ["frames device: presented unavailable, late unavailable, skipped 0, submitted 0, discarded unavailable"])

        attachment.sync(overlayShown: true, target: second, external: true)   // moved to the external display
        XCTAssertTrue(second.frameDrops === attachment.external)
        XCTAssertEqual(attachment.output, .external)
        XCTAssertEqual(attachment.sessionsBegun, 3)
        _ = attachment.external.submit(attachment.external.session, timestamp: 20, targetTimestamp: 20 + period)
        XCTAssertEqual(attachment.external.counts().submitted, 1)
        XCTAssertEqual(attachment.device.counts().submitted, 0, "the device counter stops changing")

        attachment.sync(overlayShown: false, target: second, external: true)
        XCTAssertNil(second.frameDrops)
        XCTAssertNil(attachment.output)
        attachment.sync(overlayShown: true, target: second, external: true)
        XCTAssertEqual(attachment.sessionsBegun, 4, "turning the overlay on again begins a new session")
        XCTAssertEqual(attachment.external.counts().submitted, 0)
    }

    /// The external display coordinator reports each move between displays at once (inside the call).
    func testTheExternalDisplayReportsEveryOutputChange() {
        let coordinator = ExternalDisplayCoordinator()
        var changes = 0
        coordinator.onVisualOutputChange = { () -> Void in changes += 1 }
        let device = VisualSlotView(role: .device)
        device.frame = CGRect(x: 0, y: 0, width: 200, height: 400)
        let external = VisualSlotView(role: .external)
        external.frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        coordinator.registerDeviceSlot(device)
        coordinator.show(UIView())
        coordinator.visualizerActive(true)
        XCTAssertEqual(changes, 0)
        coordinator.externalConnected(id: "a", slot: external, geometry: ExternalDisplayGeometry(width: 1920, height: 1080, scale: 1),
                                      foreground: true)
        XCTAssertTrue(coordinator.showsVisualExternally)
        XCTAssertEqual(changes, 1)
        coordinator.externalDisconnected(id: "a")
        XCTAssertEqual(changes, 2)
    }

    func testRecordingLineLiveThenFinishedOnlyWithinTheCountingSession() {
        let attachment = FrameDropAttachment()
        attachment.sync(overlayShown: true, target: FakeCountedVisual(measuresPresentation: true), external: false)
        var statistics = RecordingStatistics()
        statistics.written = 15
        statistics.droppedSlots = 5
        XCTAssertEqual(attachment.lines(recording: (statistics, false)).count, 1, "a recording from before the overlay: no line")
        let live: [String] = attachment.lines(recording: (statistics, true))
        XCTAssertEqual(live.last, "frames recording: presented 15, late unavailable, skipped 5")
        XCTAssertEqual(attachment.lines(recording: (statistics, false)).last, live.last, "finished while counting: kept")
        attachment.stop()
        attachment.sync(overlayShown: true, target: FakeCountedVisual(measuresPresentation: true), external: false)
        XCTAssertEqual(attachment.lines(recording: (statistics, false)).count, 1, "a new session drops the finished recording")
    }

    func testOverlaySeparatesTheFramesLines() {
        let lines: [String] = ["audio 0.05/0.09", "frames device: presented 1, late 0, skipped 0, submitted 1, discarded 0",
                               "over budget: render cpu 14.00 ms > 13.33 ms", "frames recording: presented 2, late unavailable, skipped 0"]
        let split = PerformanceOverlay.splitFrameDrops(lines)
        XCTAssertEqual(split.plain, ["audio 0.05/0.09", "over budget: render cpu 14.00 ms > 13.33 ms"])
        XCTAssertEqual(split.frames.count, 2)
    }

    func testMetalPathsMeasurePresentationAndExportConversion() throws {
        #if targetEnvironment(simulator)
        XCTAssertFalse(metalPresentationReported, "the simulator SDK reports no presented time: unavailable, never 0")
        #else
        XCTAssertTrue(metalPresentationReported)
        #endif
        if let device = MTLCreateSystemDefaultDevice() {
            let host = try NativeSpectrumHost.make(device: device, reader: nil, barCount: .b32)
            XCTAssertEqual(host.measuresPresentation, metalPresentationReported)
            XCTAssertNil(host.frameDrops, "no counting until the overlay attaches a counter")
        }
        let exported = AppCoordinator.exportFrameDrops([
            (.device, FrameDropCounts(submitted: 300, skipped: 2, stale: 1)),
            (.recording, FrameDropCounts.recording(written: 15, droppedSlots: 5)),
        ])
        XCTAssertEqual(exported.outputs, [.init(output: "device", submitted: 300, skipped: 2, stale: 1),
                                          .init(output: "recording", skipped: 5, presented: 15)])
    }
}
