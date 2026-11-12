// ImportStringsTests.swift — the strings of AUD-001
// (specs/003-aud-001-import-drm-free-audio-files/contracts/ui-strings.md; also cross-checked by
// scripts/test_scripts.py).
import CaptureKit
import Foundation
import XCTest
@testable import CaptureUI

final class ImportStringsTests: XCTestCase {
    private func track(_ title: String, seconds: Double = 185) -> ImportedTrack {
        let digest = String(repeating: "ab", count: 32)
        return ImportedTrack(id: UUID(), title: title, originalFileName: "\(title).wav", sha256: digest, fileName: "\(digest).wav",
                             byteCount: 10, durationSeconds: seconds, sampleRate: 44_100, channelCount: 2,
                             importedAt: Date(timeIntervalSince1970: 0))
    }

    func testEveryImportErrorHasItsMessage() {
        XCTAssertEqual(UIStrings.message(AudioImportError.notAudio), "This file isn't a supported audio file.")
        XCTAssertEqual(UIStrings.message(AudioImportError.unreadable), "This audio file can't be read. It may be damaged.")
        XCTAssertEqual(UIStrings.message(AudioImportError.protectedContent), "This file is copy-protected (DRM) and can't be imported.")
        XCTAssertEqual(UIStrings.message(AudioImportError.tooLarge(limitBytes: 500 * 1024 * 1024)),
                       "This file is too large. The limit is 500 MB.")
        XCTAssertEqual(UIStrings.message(AudioImportError.unsupportedChannelCount(6)), "Only mono and stereo audio can be imported.")
        XCTAssertEqual(UIStrings.message(AudioImportError.insufficientStorage), "There isn't enough storage on this device.")
        XCTAssertEqual(UIStrings.message(AudioImportError.sourceUnavailable), "This file couldn't be opened.")
        XCTAssertEqual(UIStrings.message(AudioImportError.libraryUnavailable), "Your audio library isn't available.")
    }

    func testSizeLimitText() {
        XCTAssertEqual(UIStrings.byteLimit(500 * 1024 * 1024), "500 MB")
        XCTAssertEqual(UIStrings.byteLimit(1024 * 1024), "1 MB")
        XCTAssertEqual(UIStrings.byteLimit(100_000), "97 KB")
        XCTAssertEqual(UIStrings.byteLimit(10), "1 KB")
    }

    func testLibraryUnavailableMessages() {
        XCTAssertEqual(UIStrings.message(AudioLibraryState.Unavailable.newerFormat),
                       "Your audio library was saved by a newer version of the app. Update the app to use it.")
        XCTAssertEqual(UIStrings.message(AudioLibraryState.Unavailable.storage), "Your audio library couldn't be opened.")
    }

    func testImportSummary() {
        XCTAssertNil(UIStrings.importSummary([]), "a cancelled picker says nothing")
        XCTAssertEqual(UIStrings.importSummary([.imported(track("A"))]), "Imported 1 track.")
        XCTAssertEqual(UIStrings.importSummary([.imported(track("A")), .imported(track("B"))]), "Imported 2 tracks.")
        XCTAssertEqual(UIStrings.importSummary([.duplicate(track("Song"))]), "“Song” is already in your library.")
        XCTAssertEqual(UIStrings.importSummary([.failed(fileName: "notes.txt", .notAudio)]),
                       "“notes.txt”: This file isn't a supported audio file.")
        let mixed: [AudioImportOutcome] = [
            .failed(fileName: "bad.wav", .unreadable),
            .imported(track("A")),
            .duplicate(track("Song")),
            .imported(track("B")),
            .failed(fileName: "big.wav", .tooLarge(limitBytes: 500 * 1024 * 1024)),
        ]
        XCTAssertEqual(UIStrings.importSummary(mixed), """
        Imported 2 tracks.
        “bad.wav”: This audio file can't be read. It may be damaged.
        “Song” is already in your library.
        “big.wav”: This file is too large. The limit is 500 MB.
        """)
    }

    func testAlertOnlyWhenSomethingWasNotImported() {
        XCTAssertFalse(UIStrings.importNeedsAlert([]))
        XCTAssertFalse(UIStrings.importNeedsAlert([.imported(track("A")), .imported(track("B"))]))
        XCTAssertTrue(UIStrings.importNeedsAlert([.imported(track("A")), .duplicate(track("A"))]))
        XCTAssertTrue(UIStrings.importNeedsAlert([.failed(fileName: "x", .notAudio)]))
    }

    func testDurationText() {
        XCTAssertEqual(UIStrings.duration(0.4), "0:00")
        XCTAssertEqual(UIStrings.duration(5), "0:05")
        XCTAssertEqual(UIStrings.duration(185.9), "3:05")
        XCTAssertEqual(UIStrings.duration(3600), "1:00:00")
        XCTAssertEqual(UIStrings.duration(3725), "1:02:05")
        XCTAssertEqual(UIStrings.duration(.nan), "0:00")
        XCTAssertEqual(UIStrings.duration(-3), "0:00")
    }

    func testSpokenDuration() {
        XCTAssertEqual(UIStrings.spokenDuration(185), "3 minutes 5 seconds")
        XCTAssertEqual(UIStrings.spokenDuration(61), "1 minute 1 second")
        XCTAssertEqual(UIStrings.spokenDuration(180), "3 minutes")
        XCTAssertEqual(UIStrings.spokenDuration(0.2), "0 seconds")
        XCTAssertEqual(UIStrings.spokenDuration(3725), "1 hour 2 minutes 5 seconds")
        XCTAssertEqual(UIStrings.spokenDuration(7200), "2 hours")
    }

    func testTrackAccessibilityLabel() {
        XCTAssertEqual(UIStrings.trackAccessibilityLabel(track("Song", seconds: 185)), "Song, 3 minutes 5 seconds")
    }

    func testSectionTextsAndTruthfulLabeling() {
        XCTAssertEqual(UIStrings.yourAudio, "Your Audio")
        XCTAssertEqual(UIStrings.importAudio, "Import Audio…")
        XCTAssertEqual(UIStrings.importing, "Importing…")
        XCTAssertEqual(UIStrings.noImportedAudio, "No imported audio yet.")
        XCTAssertEqual(UIStrings.remove, "Remove")
        XCTAssertEqual(UIStrings.importAlertTitle, "Import Audio")
        XCTAssertEqual(UIStrings.ok, "OK")
        // Constitution IV: imported tracks are In-App Playback and are described that way.
        XCTAssertTrue(UIStrings.importedAudioFooter.contains(UIStrings.label(.inAppPlayback)))
        XCTAssertTrue(UIStrings.importedTrackHint.contains(UIStrings.label(.inAppPlayback)))
        XCTAssertFalse(UIStrings.importedAudioFooter.contains("Capture"))
    }
}
