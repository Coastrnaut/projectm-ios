// CaptureUI strings must match contracts/ui-states.md (also cross-checked by scripts/test_scripts.py).
import XCTest
import AudioCore
@testable import CaptureUI

final class UIStringsTests: XCTestCase {
    func testEveryStateHasDistinctText() {
        let texts = AudioState.allCases.map(UIStrings.state)
        XCTAssertEqual(Set(texts).count, texts.count)
        XCTAssertEqual(UIStrings.state(.active), "Active audio")
        XCTAssertEqual(UIStrings.state(.silent), "Audio received — silent")
        XCTAssertEqual(UIStrings.state(.noAudioReceived), "No audio received")
    }

    func testFallbacksNeverLabeledAsSystemCapture() {
        XCTAssertNotEqual(UIStrings.label(.microphone), UIStrings.label(.systemAppCapture))
        XCTAssertNotEqual(UIStrings.label(.inAppPlayback), UIStrings.label(.systemAppCapture))
        XCTAssertFalse(UIStrings.label(.microphone).contains("Capture"))
    }

    func testBannerActionsMatchContract() {
        XCTAssertEqual(BannerAction.actions(for: .permissionDenied), [.openSettings, .chooseSource])
        XCTAssertEqual(BannerAction.actions(for: .endedBySystem), [.restart, .chooseSource])
        XCTAssertEqual(BannerAction.actions(for: .audioRouteChanged), [.resume, .chooseSource])
        XCTAssertEqual(BannerAction.actions(for: .cancelled), [.chooseSource])
        XCTAssertEqual(BannerAction.actions(for: .screenRecordingNotAllowed), [.restart, .chooseSource])
        XCTAssertEqual(UIStrings.message(.screenRecordingNotAllowed), "Screen recording not allowed")
        XCTAssertNotEqual(UIStrings.message(.screenRecordingNotAllowed), UIStrings.message(.unsupportedOS))
    }

    /// FR-004: VoiceOver hears the actual reason a mode is unavailable.
    func testChooserHintNamesTheActualReason() {
        XCTAssertEqual(UIStrings.chooserHint(.unavailable(.screenRecordingNotAllowed), mode: .systemAppCapture),
                       "Screen recording not allowed")
        XCTAssertEqual(UIStrings.chooserHint(.unavailable(.unsupportedOS), mode: .systemAppCapture),
                       "Requires a newer iOS version")
        XCTAssertEqual(UIStrings.chooserHint(.available, mode: .microphone), UIStrings.description(.microphone))
    }

    func testNoThirdPartyAppNamesInStrings() {
        let all = AudioSourceMode.allCases.flatMap { [UIStrings.label($0), UIStrings.description($0)] }
            + AudioState.allCases.map(UIStrings.state)
            + [UIStrings.noAudioHint, UIStrings.prolongedSilenceHint, UIStrings.microphoneExplainer]
        for name in ["Spotify", "Apple Music", "YouTube", "Safari"] {
            XCTAssertFalse(all.contains { $0.contains(name) }, "FR-062: \(name)")
        }
    }
}
