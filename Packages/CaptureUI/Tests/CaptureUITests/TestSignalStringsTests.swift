// TestSignalStringsTests.swift — the Diagnostics section's strings, the status line with a test
// signal, and a smoke render of a Test Signals row (AUD-016-T17; AUD-016-R13, R16;
// specs/011-aud-016-reference-tone-suite/contracts/ui-strings.md).
import AudioCore
import XCTest
@testable import CaptureUI
#if canImport(SwiftUI)
import SwiftUI
#endif

final class TestSignalStringsTests: XCTestCase {
    func testStringsMatchTheContract() {
        XCTAssertEqual(UIStrings.diagnostics, "Diagnostics")
        XCTAssertEqual(UIStrings.testSignals, "Test Signals")
        XCTAssertEqual(UIStrings.testSignalsRowDetail, "Generated tones, sweeps, pulses and silence for checking the visualizer.")
        XCTAssertEqual(UIStrings.testSignalsFooter,
                       "These test signals are generated on this device for checking the visualizer. They are not music. "
                       + "Lower the volume before you start one. Each plays as In-App Playback and repeats until you stop it.")
        XCTAssertEqual(UIStrings.testSignalHint, "Plays this test signal as In-App Playback.")
    }

    func testStatusLineNamesTheSignalOnlyForInAppPlayback() {
        XCTAssertEqual(UIStrings.sourceStatus(mode: .inAppPlayback, state: .active, signal: "Test tone 1 kHz"),
                       "In-App Playback · Test tone 1 kHz · Active audio")
        XCTAssertEqual(UIStrings.sourceStatus(mode: .inAppPlayback, state: .silent, signal: "Test silence"),
                       "In-App Playback · Test silence · Audio received — silent")
        // Without a signal: feature 001's text, unchanged (FR-013).
        XCTAssertEqual(UIStrings.sourceStatus(mode: .inAppPlayback, state: .active, signal: nil), "In-App Playback · Active audio")
        XCTAssertEqual(UIStrings.sourceStatus(mode: nil, state: .notStarted, signal: nil), "No source · Not started")
        // A signal name is never attached to another mode (Constitution IV).
        XCTAssertEqual(UIStrings.sourceStatus(mode: .microphone, state: .active, signal: "Test tone 1 kHz"), "Microphone · Active audio")
        XCTAssertEqual(UIStrings.sourceStatus(mode: .systemAppCapture, state: .waiting, signal: "Test tone 1 kHz"),
                       "System/App Capture · Waiting")
    }

    func testEveryCatalogNameReadsAsATestSignal() {
        for fixture in ReferenceToneCatalog.fixtures {
            XCTAssertTrue(fixture.name.hasPrefix("Test "), fixture.id)
            XCTAssertFalse(fixture.summary.isEmpty, fixture.id)
        }
    }

    #if canImport(SwiftUI)
    @MainActor
    func testRowRendersAndTheListBuilds() throws {
        for fixture in ReferenceToneCatalog.fixtures {
            let renderer = ImageRenderer(content: TestSignalRow(fixture: fixture).frame(width: 390))
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.cgImage, fixture.id)
            XCTAssertGreaterThan(image.height, 0, fixture.id)
        }
        // Lists cannot be drawn by ImageRenderer; building the bodies checks they evaluate.
        _ = TestSignalListView(fixtures: ReferenceToneCatalog.fixtures, onPlay: { _ in }).body
        _ = TestSignalsSection(fixtures: ReferenceToneCatalog.fixtures, onPlay: { _ in }).body
    }
    #endif
}
