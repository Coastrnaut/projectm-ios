// StereoPhaseWarningTests.swift — ANL-013-T12 (ANL-013-R7, R8; S6; contract C5): the phase-inversion
// warning in the source status, its throttled announcements through the status-event router (X3a, X3b),
// the overlay line, and the native visual's report of warning changes. Fake clocks only.
import Metal
import XCTest
@testable import projectM_iOS

@MainActor
final class StereoPhaseWarningTests: XCTestCase {
    private final class Clock {
        var now: Double = 1_000
    }

    private func makePresenter(_ clock: Clock, spoken: @escaping (String) -> Void,
                               log: @escaping (StatusEvent) -> Void = { (_: StatusEvent) -> Void in }) -> StereoPhaseWarningPresenter {
        let announcer = AccessibilityAnnouncer(post: { (text: String) -> Void in spoken(text) },
                                               now: { () -> Double in clock.now },
                                               schedule: { (_: Double, _: @escaping @MainActor () -> Void) -> Void in })
        let router = StatusEventRouter(announcer: announcer, schedule: { (_: Double, _: @escaping @MainActor () -> Void) -> Void in })
        let presenter = StereoPhaseWarningPresenter(now: { () -> Double in clock.now })
        presenter.post = { (event: StatusEvent) -> Void in
            log(event)
            router.post(event)
        }
        return presenter
    }

    func testRaiseIsAnnouncedOnceIn30SecondsAndAnAnnouncedRaiseClears() {
        let clock = Clock()
        var spoken: [String] = []
        var ids: [String] = []
        let presenter = makePresenter(clock, spoken: { (text: String) -> Void in spoken.append(text) },
                                      log: { (event: StatusEvent) -> Void in ids.append(event.id) })
        presenter.update(true)
        XCTAssertTrue(presenter.isRaised)
        XCTAssertEqual(spoken, ["Stereo channels look phase-inverted"])
        clock.now += 5
        presenter.update(false)
        XCTAssertEqual(spoken.last, "Stereo phase normal")
        clock.now += 5
        presenter.update(true)   // 10 s after the first raise: shown, not announced
        presenter.update(true)   // no change: nothing
        XCTAssertTrue(presenter.isRaised)
        clock.now += 5
        presenter.update(false)   // its raise was not announced: no clear announcement
        XCTAssertEqual(ids, ["X3a", "X3b"])
        clock.now += 30
        presenter.update(true)
        XCTAssertEqual(ids, ["X3a", "X3b", "X3a"], "30 s later the raise is announced again")
        XCTAssertEqual(spoken.count, 3)
    }

    func testStatusRowsSourceTextAndOverlayLine() {
        let raised = StatusEventCatalog.stereoPhase(raised: true)
        XCTAssertEqual(raised.id, "X3a")
        XCTAssertEqual(raised.kind, .source)
        XCTAssertEqual(raised.cause, .system)
        XCTAssertEqual(raised.presentation, .persistent)
        let cleared = StatusEventCatalog.stereoPhase(raised: false)
        XCTAssertEqual(cleared.id, "X3b")
        XCTAssertEqual(cleared.presentation, .caption)

        let plain = SourceStatusIndicator.text(mode: .inAppPlayback, state: .active)
        let warned = SourceStatusIndicator.text(mode: .inAppPlayback, state: .active, phaseWarning: true)
        XCTAssertEqual(warned, plain + " · Stereo channels look phase-inverted")
        XCTAssertEqual(SourceStatusIndicator.text(mode: .inAppPlayback, state: .active, switching: true, phaseWarning: true),
                       SourceStatusIndicator.text(mode: .inAppPlayback, state: .active, switching: true))

        XCTAssertEqual(StereoPhaseWarningPresenter.overlayLine(correlation: 0.981, raised: false), "stereo: r 0.98")
        XCTAssertEqual(StereoPhaseWarningPresenter.overlayLine(correlation: -0.97, raised: true), "stereo: r -0.97 phase-inverted")
        XCTAssertEqual(StereoPhaseWarningPresenter.overlayLine(correlation: .nan, raised: false), "stereo: r 0.00")
    }

    func testTheNativeVisualReportsWarningChanges() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let host = try NativeSpectrumHost.make(device: device, reader: nil, barCount: .b32)
        var reports: [Bool] = []
        host.onPhaseWarningChange = { (raised: Bool) -> Void in reports.append(raised) }
        host.setPhaseInverted(true)
        host.setPhaseInverted(true)
        host.setPhaseInverted(false)
        XCTAssertEqual(reports, [true, false], "only changes are reported")
        XCTAssertFalse(host.phaseInverted)
    }
}
