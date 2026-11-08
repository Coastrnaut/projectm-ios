// ViewRenderTests.swift — smoke tests for the views shown by the T033 previews, plus a check that
// the preview fixtures cover every StopReason case.
//
// What ImageRenderer can show here: each view body evaluates without trapping, lays out, and
// produces a non-empty bitmap; and adding a message line or an action row makes the layout taller.
// It cannot show that a given string is drawn (the size comes from layout, and ImageRenderer draws
// placeholders for platform-backed controls), so string and action correctness is checked by
// UIStringsTests and scripts/test_scripts.py, not here. The chooser is a List, which ImageRenderer
// cannot draw, so CaptureLabUITests checks it in the running app instead.
#if canImport(SwiftUI)
import AudioCore
import CoreGraphics
import SwiftUI
import XCTest
@testable import CaptureUI

@MainActor
final class ViewRenderTests: XCTestCase {
    /// Exhaustiveness witness: one distinct kind per StopReason case, named after the case.
    /// Adding a StopReason case stops `init(_:)` compiling; adding the matching kind (as the
    /// naming requires) then makes `testFixturesCoverEveryStopReason` fail until
    /// `PreviewFixtures.stopReasons` contains the new case. The compiler cannot stop a new case
    /// from being mapped onto an existing kind; the raw-value check below catches that for every
    /// case that has a fixture.
    private enum ReasonKind: String, CaseIterable {
        case cancelled, permissionDenied, microphoneUnavailable, inAppPlaybackFailed, interrupted,
             audioRouteChanged, endedBySystem, unsupportedOS, error

        init(_ reason: StopReason) {
            switch reason {
            case .cancelled: self = .cancelled
            case .permissionDenied: self = .permissionDenied
            case .microphoneUnavailable: self = .microphoneUnavailable
            case .inAppPlaybackFailed: self = .inAppPlaybackFailed
            case .interrupted: self = .interrupted
            case .audioRouteChanged: self = .audioRouteChanged
            case .endedBySystem: self = .endedBySystem
            case .unsupportedOS: self = .unsupportedOS
            case .error: self = .error
            }
        }
    }

    func testFixturesCoverEveryStopReason() {
        let kinds = PreviewFixtures.stopReasons.map(ReasonKind.init)
        XCTAssertEqual(Set(kinds).count, kinds.count, "duplicate StopReason in fixtures")
        let missing = Set(ReasonKind.allCases).subtracting(kinds).map(\.rawValue).sorted()
        XCTAssertEqual(missing, [], "PreviewFixtures.stopReasons is missing these StopReason cases")
        for reason in PreviewFixtures.stopReasons {
            XCTAssertEqual(ReasonKind(reason).rawValue, reason.code, "witness maps \(reason.code) to the wrong kind")
        }
    }

    func testBannerSmokeRendersEveryStopReason() {
        for reason in PreviewFixtures.stopReasons {
            assertSmokeRenders(StatusBanner(mode: .systemAppCapture, state: PreviewFixtures.state(for: reason),
                                            reason: reason, prolongedSilence: false) { _ in },
                               name: "banner \(reason.code)")
        }
    }

    func testBannerSmokeRendersEveryState() {
        for state in AudioState.allCases {
            assertSmokeRenders(StatusBanner(mode: .microphone, state: state, reason: nil,
                                            prolongedSilence: state == .silent) { _ in },
                               name: "banner \(state.rawValue)")
        }
    }

    func testMicrophoneExplainerSmokeRenders() {
        assertSmokeRenders(MicrophoneExplainerView(onContinue: {}, onCancel: {}), name: "explainer")
    }

    /// Layout only: a banner with a StopReason (message line and action row) is taller than the same
    /// banner without one, and each hint (no audio, prolonged silence) adds a line. This shows the
    /// optional rows take part in layout, not which text they draw.
    func testOptionalBannerRowsAddHeight() throws {
        for reason in PreviewFixtures.stopReasons {
            let state = PreviewFixtures.state(for: reason)
            let with = try height(StatusBanner(mode: .systemAppCapture, state: state, reason: reason,
                                               prolongedSilence: false) { _ in })
            let without = try height(StatusBanner(mode: .systemAppCapture, state: state, reason: nil,
                                                  prolongedSilence: false) { _ in })
            XCTAssertGreaterThan(with, without, "banner \(reason.code): message/action rows add no height")
        }
        let noAudio = try height(StatusBanner(mode: .microphone, state: .noAudioReceived, reason: nil,
                                              prolongedSilence: false) { _ in })
        let waiting = try height(StatusBanner(mode: .microphone, state: .waiting, reason: nil,
                                              prolongedSilence: false) { _ in })
        XCTAssertGreaterThan(noAudio, waiting, "no-audio hint adds no height")
        let longSilence = try height(StatusBanner(mode: .microphone, state: .silent, reason: nil,
                                                  prolongedSilence: true) { _ in })
        let silence = try height(StatusBanner(mode: .microphone, state: .silent, reason: nil,
                                              prolongedSilence: false) { _ in })
        XCTAssertGreaterThan(longSilence, silence, "prolonged-silence hint adds no height")
    }

    /// Smoke test: the body evaluates without trapping and ImageRenderer returns a non-empty bitmap.
    private func assertSmokeRenders(_ view: some View, name: String,
                                    file: StaticString = #filePath, line: UInt = #line) {
        let image = render(view)
        XCTAssertNotNil(image, "\(name): ImageRenderer returned no image", file: file, line: line)
        XCTAssertGreaterThan(image?.width ?? 0, 0, "\(name): empty image", file: file, line: line)
        XCTAssertGreaterThan(image?.height ?? 0, 0, "\(name): empty image", file: file, line: line)
    }

    private func height(_ view: some View, file: StaticString = #filePath, line: UInt = #line) throws -> Int {
        try XCTUnwrap(render(view), "ImageRenderer returned no image", file: file, line: line).height
    }

    private func render(_ view: some View) -> CGImage? {
        let renderer = ImageRenderer(content: view.frame(width: 390))
        renderer.scale = 1
        return renderer.cgImage
    }
}
#endif
