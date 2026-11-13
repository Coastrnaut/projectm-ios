// AUD-016-T19: a test signal is prepared as an In-App Playback item alone in its play order, and
// the source-and-state indicator (and its VoiceOver announcements) name the signal only while one
// plays (AUD-016-R14, R16, R17). The end-to-end flow is TestSignalsUITests.
import AudioCore
import CaptureKit
import CaptureUI
import XCTest
@testable import projectM_iOS

@MainActor
final class TestSignalCoordinatorTests: XCTestCase {
    func testASignalIsAnOrderOfOne() throws {
        let fixture = try XCTUnwrap(ReferenceToneCatalog.fixture(id: "pulse-132"))
        let (order, item) = AppCoordinator.testSignalPlayback(fixture)
        XCTAssertEqual(item, PlaybackItem.tone(fixture))
        XCTAssertEqual(item.title, "Test pulses 132 BPM")
        XCTAssertEqual(order.items, [item])
        XCTAssertEqual(order.item(after: item.id), item, "Next track starts the same signal again")
        XCTAssertEqual(order.item(before: item.id), item, "Previous track starts the same signal again")
    }

    func testIndicatorNamesTheSignal() {
        XCTAssertEqual(SourceStatusIndicator.text(mode: .inAppPlayback, state: .active, signal: "Test tone 1 kHz"),
                       "In-App Playback · Test tone 1 kHz · Active audio")
        XCTAssertEqual(SourceStatusIndicator.text(mode: .inAppPlayback, state: .active), "In-App Playback · Active audio")
        XCTAssertEqual(SourceStatusIndicator.text(mode: .microphone, state: .active, signal: "Test tone 1 kHz"), "Microphone · Active audio")
        XCTAssertEqual(SourceStatusIndicator.holdAnnouncement(mode: .inAppPlayback, state: .interrupted, reason: .interrupted,
                                                              signal: "Test silence"),
                       "In-App Playback · Test silence · Interrupted. \(UIStrings.playbackInterruptedDetail)")
    }

    func testTheSignalNameComesOnlyFromAToneItem() throws {
        let fixture = try XCTUnwrap(ReferenceToneCatalog.fixture(id: "sine-1k"))
        XCTAssertEqual(AppCoordinator.signalName(mode: .inAppPlayback, item: .tone(fixture)), "Test tone 1 kHz")
        XCTAssertNil(AppCoordinator.signalName(mode: .inAppPlayback, item: AudioLibraryCoordinator.referenceItem))
        XCTAssertNil(AppCoordinator.signalName(mode: .inAppPlayback, item: nil))
        XCTAssertNil(AppCoordinator.signalName(mode: .microphone, item: .tone(fixture)))
    }
}
