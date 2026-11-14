// CueTransitionOverrideAcceptanceTests.swift — SHOW-004-T05, the roadmap acceptance "Cue override wins without altering
// scene default" (SHOW-004-S1; contract O4-O6): two cues show one scene whose default (SCN-007) is a 2 s crossfade; cue A
// gets a Cut override. Stepping into A drives a cut, stepping into B drives the crossfade, and the scene file's bytes and
// both cues' defaults are unchanged after editing and using the override. Also: "Use Scene Default" restores the
// crossfade, the safety rules still resolve the override, the scene lock refuses the edit, Duplicate keeps it, and a
// reopened show keeps it. Temporary store per test; no wall clock.
import Compositor
import Foundation
import SceneFormat
import ShowControl
import ShowStorage
import TextLayer
import XCTest
@testable import projectM_iOS

@MainActor
private final class OverrideSpy: CueTransitionDriving {
    var specs: [SceneTransitionSpec] = []
    var scenes: [String] = []

    func driveTransition(_ spec: SceneTransitionSpec, toScene sceneID: String) {
        specs.append(spec)
        scenes.append(sceneID)
    }
}

@MainActor
final class CueTransitionOverrideAcceptanceTests: XCTestCase {
    private func folder() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CueTransitionOverrideAcceptance-\(UUID().uuidString)",
                                                                                isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func coordinator(_ url: URL, spy: OverrideSpy) throws -> ShowCoordinator {
        let show = ShowCoordinator(store: ShowStore(directory: url), registry: try SceneArchiveService.appRegistry())
        show.applyScene = { (_: SceneDocument, _: [SceneIssue]) -> [String] in [] }
        show.announce = { (_: String) in }
        show.transitionDriver = spy
        return show
    }

    private static func crossfade2s() throws -> ShowCueTransition { try ShowCueTransition(type: .crossfade, durationSeconds: 2) }
    private static func cut() throws -> ShowCueTransition { try ShowCueTransition(type: .cut, durationSeconds: 0) }

    /// A show over `url` with cues A and B showing one stored scene, both with the 2 s crossfade default, at Standby.
    private func twoCuesOfOneScene(_ url: URL, spy: OverrideSpy) throws -> (show: ShowCoordinator, sceneID: String) {
        let show = try coordinator(url, spy: spy)
        let look = ShowLook(visual: .circularSpectrum, bars: 64, orientation: .horizontal, spacing: 0.5, glowEnabled: false,
                            glowIntensity: 0.7, glowRadius: 0.03, glowThreshold: 0.4, text: TextOverlaySpec(message: ""),
                            photoID: nil, videoID: nil)
        let document = ShowSceneSnapshot.document(look, id: UUID().uuidString, name: "Sunrise")
        XCTAssertTrue(show.addScene(document, label: "A"))
        var list = show.list
        try list.append(sceneID: document.id, label: "B")   // a second cue of the same scene (a show file may list it twice)
        for cue in list.cues { try list.setTransition(cue.id, to: try Self.crossfade2s()) }
        show.replaceForUITests(list)
        return (show, document.id)
    }

    func testTheCueOverrideWinsWithoutAlteringTheSceneDefault() throws {
        let url = folder()
        let spy = OverrideSpy()
        let (show, sceneID) = try twoCuesOfOneScene(url, spy: spy)
        let sceneFile = try XCTUnwrap(show.sceneFileURL(sceneID))
        let sceneBytes = try Data(contentsOf: sceneFile)
        let defaults = show.list.cues.map(\.transition)
        let a = show.list.cues[0].id

        XCTAssertTrue(show.setTransitionOverride(a, to: try Self.cut()))
        XCTAssertEqual(show.list.position, .standby, "editing applies nothing")
        XCTAssertTrue(spy.specs.isEmpty)

        show.next()   // into A
        show.next()   // into B
        XCTAssertEqual(spy.scenes, [sceneID, sceneID], "both cues show the same scene")
        XCTAssertEqual(spy.specs[0], CueTransitionResolver.spec(for: try Self.cut()), "the override wins on the edge into A")
        XCTAssertEqual(spy.specs[0].style, .cut)
        XCTAssertTrue(spy.specs[0].isInstant, "a cut: no blend")
        XCTAssertEqual(spy.specs[1], CueTransitionResolver.spec(for: try Self.crossfade2s()), "B uses the scene default")
        XCTAssertEqual(spy.specs[1].durationSeconds, 2)

        XCTAssertEqual(try Data(contentsOf: sceneFile), sceneBytes, "the scene file is byte-identical")
        XCTAssertEqual(show.list.cues.map(\.transition), defaults, "both scene defaults are unchanged")

        // Reopened from disk: the override and the defaults come back as they were.
        let reopened = try coordinator(url, spy: OverrideSpy())
        XCTAssertEqual(reopened.list.cues[0].transitionOverride, try Self.cut())
        XCTAssertEqual(reopened.list.cues.map(\.transition), defaults)

        // "Use Scene Default": stepping into A drives the crossfade again.
        XCTAssertTrue(show.setTransitionOverride(a, to: nil))
        show.go(to: a)
        XCTAssertEqual(spy.specs.last, CueTransitionResolver.spec(for: try Self.crossfade2s()))
        XCTAssertEqual(try Data(contentsOf: sceneFile), sceneBytes)
        XCTAssertEqual(show.list.cues.map(\.transition), defaults)
    }

    func testSafetyLockAndDuplicateApplyToTheOverride() throws {
        let url = folder()
        let spy = OverrideSpy()
        let (show, _) = try twoCuesOfOneScene(url, spy: spy)
        let a = show.list.cues[0].id
        XCTAssertTrue(show.setTransitionOverride(a, to: try Self.cut()))

        show.transitionSafety = { () -> (reduceMotion: Bool, reduceFlashing: Bool) in (reduceMotion: false, reduceFlashing: true) }
        show.go(to: a)
        XCTAssertEqual(spy.specs.last, try SceneTransitionSpec(style: .crossfade, durationSeconds: 0.5, easing: .linear, curve: .linear),
                       "Reduce flashing spreads a Cut override over half a second")
        let fade = try ShowCueTransition(type: .crossfade, durationSeconds: 3)
        XCTAssertTrue(show.setTransitionOverride(a, to: fade))
        show.transitionSafety = { () -> (reduceMotion: Bool, reduceFlashing: Bool) in (reduceMotion: true, reduceFlashing: false) }
        show.go(to: show.list.cues[1].id)
        show.go(to: a)
        XCTAssertEqual(spy.specs.last, .cut, "Reduce Motion makes an override a cut")

        let suite = "CueTransitionOverride-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        let lock = SceneLock(defaults: defaults)
        show.sceneLock = lock
        lock.lock()
        XCTAssertFalse(show.setTransitionOverride(a, to: nil), "an override edit while locked is refused")
        XCTAssertEqual(show.list.cues[0].transitionOverride, fade)
        XCTAssertEqual(show.editorMessage, SceneLock.refusalMessage)
        lock.unlock()

        let copy = try XCTUnwrap(show.duplicateScene(of: a))
        XCTAssertEqual(copy.transitionOverride, fade, "Duplicate keeps the override")
        XCTAssertEqual(copy.transition, try Self.crossfade2s(), "and the scene default")
    }
}
