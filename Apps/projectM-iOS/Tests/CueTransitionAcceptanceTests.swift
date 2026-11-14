// CueTransitionAcceptanceTests.swift — SCN-007-T10, the roadmap acceptance "Reopening scene restores transition
// settings exactly" (SCN-007-S1): each cue gets a distinct transition (type, duration, easing including a custom
// curve), the show is saved, a new coordinator loads it from disk, the values are exactly equal (bit-identical
// durations, the same curve), and stepping to each cue drives a transition-driver spy with exactly those
// settings before the scene is applied. Also: no transition is a cut, an unknown type is a cut, Duplicate copies
// the transition, and the safety resolution (SCN-007-R6). Temporary store per test; no wall clock.
import Compositor
import Foundation
import ParameterGraph
import SceneFormat
import ShowControl
import ShowStorage
import TextLayer
import XCTest
@testable import projectM_iOS

@MainActor
private final class TransitionSpy: CueTransitionDriving {
    var events: [String] = []
    var specs: [SceneTransitionSpec] = []

    func driveTransition(_ spec: SceneTransitionSpec, toScene sceneID: String) {
        events.append("transition " + sceneID)
        specs.append(spec)
    }
}

@MainActor
final class CueTransitionAcceptanceTests: XCTestCase {
    private func folder() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CueTransitionAcceptanceTests-\(UUID().uuidString)",
                                                                                isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func look(_ visual: VisualChoice) -> ShowLook {
        ShowLook(visual: visual, bars: 64, orientation: .horizontal, spacing: 0.5, glowEnabled: false, glowIntensity: 0.7,
                 glowRadius: 0.03, glowThreshold: 0.4, text: TextOverlaySpec(message: ""), photoID: nil, videoID: nil)
    }

    /// A coordinator over `url` whose applies are logged after the spy's transitions.
    private func coordinator(_ url: URL, spy: TransitionSpy) throws -> ShowCoordinator {
        let show = ShowCoordinator(store: ShowStore(directory: url), registry: try SceneArchiveService.appRegistry())
        show.applyScene = { (document: SceneDocument, _: [SceneIssue]) -> [String] in
            spy.events.append("apply " + document.id)
            return []
        }
        show.announce = { (_: String) in }
        show.transitionDriver = spy
        return show
    }

    static let transitions: [ShowCueTransition?] = [
        nil,
        try? ShowCueTransition(type: .crossfade, durationSeconds: 1.5, easing: .easeOut(exponent: 2)),
        try? ShowCueTransition(type: .dipToBlack, durationSeconds: 0.1 + 0.2,
                               easing: .piecewise([CurvePoint(x: 0.2, y: 0.05), CurvePoint(x: 0.8, y: 0.9)])),
        try? ShowCueTransition(type: .crossfade, durationSeconds: 9.9, easing: .exponential(strength: 20)),
        try? ShowCueTransition(type: .cut, durationSeconds: 2, easing: .easeIn(exponent: 3)),
    ]

    func testReopeningTheShowRestoresTransitionsExactlyAndApplyDrivesThem() throws {
        let url = folder()
        let first = try coordinator(url, spy: TransitionSpy())
        var ids: [String] = []
        for n in 0..<Self.transitions.count {
            let document = ShowSceneSnapshot.document(look(n % 2 == 0 ? .circularSpectrum : .linearSpectrum),
                                                      id: UUID().uuidString, name: "Cue \(n + 1)")
            ids.append(document.id)
            XCTAssertTrue(first.addScene(document, label: "Cue \(n + 1)"))
        }
        for (index, transition) in Self.transitions.enumerated() where transition != nil {
            XCTAssertTrue(first.setTransition(first.list.cues[index].id, to: transition))
        }
        XCTAssertEqual(first.list.position, .standby, "setting transitions applies nothing")

        // Reopen: a new coordinator loads the show folder from disk.
        let spy = TransitionSpy()
        let reopened = try coordinator(url, spy: spy)
        XCTAssertEqual(reopened.list, first.list)
        for (index, expected) in Self.transitions.enumerated() {
            let restored = reopened.list.cues[index].transition
            XCTAssertEqual(restored, expected, "cue \(index + 1)")
            XCTAssertEqual(restored?.type, expected?.type)
            XCTAssertEqual(restored?.durationSeconds.bitPattern, expected?.durationSeconds.bitPattern, "cue \(index + 1): bit-identical")
            XCTAssertEqual(restored?.easing, expected?.easing, "cue \(index + 1): the same curve")
        }

        // Applying each cue drives exactly its settings, before the scene.
        for _ in Self.transitions { reopened.next() }
        XCTAssertEqual(spy.specs.count, Self.transitions.count)
        XCTAssertEqual(spy.events, ids.flatMap { (id: String) -> [String] in ["transition " + id, "apply " + id] },
                       "each transition is driven just before its scene is applied")
        XCTAssertEqual(spy.specs[0], .cut, "no transition: today's instant change")
        let styles: [SceneTransitionStyle?] = [nil, .crossfade, .dipToBlack, .crossfade, .cut]
        for index in 1..<Self.transitions.count {
            let expected = try XCTUnwrap(Self.transitions[index])
            let spec = spy.specs[index]
            XCTAssertEqual(spec.style, styles[index], "cue \(index + 1)")
            XCTAssertEqual(spec.durationSeconds.bitPattern, expected.durationSeconds.bitPattern, "cue \(index + 1)")
            XCTAssertEqual(spec.curve, expected.easing, "cue \(index + 1)")
            XCTAssertEqual(SceneTransitionClock(spec: spec).curve, expected.easing, "the bus's clock gets the curve")
        }
        XCTAssertTrue(spy.specs[4].isInstant, "a cut stays a cut")
    }

    func testAnUnknownTypeAppliesAsACutAndDuplicateCopiesTheTransition() throws {
        let url = folder()
        let spy = TransitionSpy()
        let show = try coordinator(url, spy: spy)
        show.makeSceneID = { () -> String in "C0B1E5CE-0000-4000-8000-0000000000AB" }
        let document = ShowSceneSnapshot.document(look(.circularSpectrum), id: UUID().uuidString, name: "One")
        XCTAssertTrue(show.addScene(document, label: "One"))
        let unknown = try ShowCueTransition(type: .unknown("wipeLeft"), durationSeconds: 2)
        XCTAssertTrue(show.setTransition(show.list.cues[0].id, to: unknown))
        show.next()
        XCTAssertEqual(spy.specs, [.cut])
        let copy = try XCTUnwrap(show.duplicateScene(of: show.list.cues[0].id))
        XCTAssertEqual(copy.transition, unknown)
    }

    func testSafetyResolution() throws {
        let fade = try ShowCueTransition(type: .crossfade, durationSeconds: 2, easing: .easeIn(exponent: 2))
        let shortDip = try ShowCueTransition(type: .dipToBlack, durationSeconds: 0.2, easing: .easeOut(exponent: 2))
        let cut = try ShowCueTransition(type: .cut, durationSeconds: 3)
        XCTAssertEqual(CueTransitionResolver.resolved(fade, reduceMotion: true, reduceFlashing: true), .cut, "Reduce Motion wins")
        XCTAssertEqual(CueTransitionResolver.resolved(fade, reduceMotion: false, reduceFlashing: true),
                       CueTransitionResolver.spec(for: fade), "long enough: unchanged")
        let lengthenedCut = CueTransitionResolver.resolved(cut, reduceMotion: false, reduceFlashing: true)
        XCTAssertEqual(lengthenedCut, try SceneTransitionSpec(style: .crossfade, durationSeconds: 0.5, easing: .linear, curve: .linear))
        XCTAssertEqual(CueTransitionResolver.resolved(nil, reduceMotion: false, reduceFlashing: true), lengthenedCut,
                       "the default instant change is lengthened too")
        let dip = CueTransitionResolver.resolved(shortDip, reduceMotion: false, reduceFlashing: true)
        XCTAssertEqual(dip.style, .dipToBlack)
        XCTAssertEqual(dip.durationSeconds, 0.5)
        XCTAssertEqual(dip.curve, .easeOut(exponent: 2))
        XCTAssertEqual(CueTransitionResolver.resolved(shortDip, reduceMotion: false, reduceFlashing: false),
                       CueTransitionResolver.spec(for: shortDip), "no safety setting: exact")
        XCTAssertEqual(CueTransitionResolver.summary(try ShowCueTransition(type: .crossfade, durationSeconds: 1.5, easing: .easeOut(exponent: 2))),
                       "Crossfade 1.5 s, Ease Out")
        XCTAssertEqual(CueTransitionResolver.summary(try ShowCueTransition(type: .dipToBlack, durationSeconds: 0.75, easing: .logarithmic(strength: 9))),
                       "Dip to Black 0.75 s, Custom (log:9.0)")
        XCTAssertNil(CueTransitionResolver.summary(nil))
        for style in SceneTransitionStyle.allCases {
            XCTAssertNotNil(ShowTransitionType(text: style.rawValue).flatMap(CueTransitionResolver.style), "\(style) maps")
        }
    }
}
