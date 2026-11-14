// AUD-012-T12: the app side of the source switch (AUD-012-R1, R7, R9, R14; contract C5).
import AudioCore
import CaptureUI
import XCTest
@testable import projectM_iOS

@MainActor
final class SourceSwitchAppTests: XCTestCase {
    func testSwitchTargetsAreTheOtherAvailableModes() {
        let all: [AudioSourceMode: SourceAvailability] = [.systemAppCapture: .available, .microphone: .available,
                                                         .inAppPlayback: .available]
        XCTAssertEqual(AppCoordinator.switchTargets(current: .inAppPlayback, availability: all), [.systemAppCapture, .microphone])
        let noCapture: [AudioSourceMode: SourceAvailability] = [.systemAppCapture: .unavailable(.unsupportedOS),
                                                               .microphone: .available, .inAppPlayback: .available]
        XCTAssertEqual(AppCoordinator.switchTargets(current: .microphone, availability: noCapture), [.inAppPlayback],
                       "System/App Capture is not offered where it is unavailable (iOS 26, D3)")
        XCTAssertEqual(AppCoordinator.switchTargets(current: nil, availability: noCapture), [.microphone, .inAppPlayback])
    }

    func testTheIndicatorNamesNoSourceWhileSwitching() {
        let switching = SourceStatusIndicator.text(mode: .systemAppCapture, state: .active, signal: nil, switching: true)
        XCTAssertEqual(switching, "Switching source…")
        XCTAssertFalse(switching.contains("System/App Capture"))
        XCTAssertEqual(SourceStatusIndicator.text(mode: .microphone, state: .waiting, signal: nil, switching: false),
                       UIStrings.sourceStatus(mode: .microphone, state: .waiting, signal: nil), "unchanged outside a switch")
    }

    func testTheSwitchControlStrings() {
        XCTAssertEqual(UIStrings.switchSource, "Switch Source")
        XCTAssertEqual(UIStrings.switchingSource, "Switching source…")
    }

    func testTheSanitizedLineIsACountOnlyAndHiddenAtZero() {
        XCTAssertNil(PerformanceOverlay.sanitizedLine(0))
        XCTAssertEqual(PerformanceOverlay.sanitizedLine(1), "sanitized: 1 sample")
        XCTAssertEqual(PerformanceOverlay.sanitizedLine(12), "sanitized: 12 samples")
    }
}
