// Task T105: what VoiceOver announces on an audio-state change is the indicator's text (FR-070),
// for every state. The screen-reader audit itself (SC-012) is a device check.
import AudioCore
import CaptureUI
import XCTest
@testable import projectM_iOS

final class AccessibilityTests: XCTestCase {
    @MainActor
    func testTheAnnouncementMatchesTheIndicatorForEveryState() {
        for state in AudioState.allCases {
            XCTAssertEqual(SourceStatusIndicator.text(mode: .inAppPlayback, state: state),
                           "In-App Playback · \(UIStrings.state(state))")
        }
        XCTAssertEqual(SourceStatusIndicator.text(mode: nil, state: .notStarted),
                       "No source · \(UIStrings.state(.notStarted))")
    }
}
