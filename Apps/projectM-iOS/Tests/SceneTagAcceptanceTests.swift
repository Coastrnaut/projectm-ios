// SceneTagAcceptanceTests.swift — SCN-005-T11, T13: the roadmap acceptance in the app ("Tag changes
// update results and persist offline"; SCN-005-S1, S3). Scenes are tagged through ShowCoordinator, the
// switcher's entries are filtered by chips (AND) and text, a tag change updates the results at once,
// and a coordinator reloaded from the same store (local files only) gives the same tags and results.
// Also: refusals change nothing and announce, a duplicate copies tags, removing a scene's last cue
// drops its tags, a vanished chip is ignored, and an unreadable scene keeps its tags and can be tagged.
// Each store is a fresh temporary folder; nothing reads the wall clock.
import Foundation
import ParameterGraph
import SceneFormat
import ShowControl
import ShowStorage
import TextLayer
import XCTest
@testable import projectM_iOS

@MainActor
final class SceneTagAcceptanceTests: XCTestCase {
    private func folder() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SceneTagAcceptanceTests-\(UUID().uuidString)",
                                                                                isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func look(_ visual: VisualChoice) -> ShowLook {
        ShowLook(visual: visual, bars: 64, orientation: .horizontal, spacing: 0.5, glowEnabled: false, glowIntensity: 0.7,
                 glowRadius: 0.03, glowThreshold: 0.4, text: TextOverlaySpec(message: ""), photoID: nil, videoID: nil)
    }

    private final class Log {
        var spoken: [String] = []
    }

    /// Three cues ("Opening", "Build", "Finale") over a store at `url`.
    private func show(at url: URL, log: Log) throws -> (ShowCoordinator, [String]) {
        let show = coordinator(at: url, log: log)
        var ids: [String] = []
        let cues: [(VisualChoice, String)] = [(.circularSpectrum, "Opening"), (.linearSpectrum, "Build"), (.circularSpectrum, "Finale")]
        for (visual, label) in cues {
            let document = ShowSceneSnapshot.document(look(visual), id: UUID().uuidString, name: label)
            ids.append(document.id)
            XCTAssertTrue(show.addScene(document, label: label))
        }
        return (show, ids)
    }

    private func coordinator(at url: URL, log: Log) -> ShowCoordinator {
        let show = ShowCoordinator(store: ShowStore(directory: url), registry: try? SceneArchiveService.appRegistry())
        show.applyScene = { (_: SceneDocument, _: [SceneIssue]) -> [String] in [] }
        show.announce = { (_: String) in }
        show.announceLibrary = { (message: String) in log.spoken.append(message) }
        return show
    }

    /// The labels the switcher lists for `tags` and `query`.
    private func listed(_ show: ShowCoordinator, tags: Set<String>, query: String = "") -> [String] {
        let rows = SceneSwitcherEntry.entries(list: show.list, sceneNames: show.sceneNames, unreadable: show.unreadableScenes)
        return SceneSwitcherFilter.results(rows, query: query, tags: tags).map(\.label)
    }

    // MARK: - The acceptance (SCN-005-S1)

    func testTagChangesUpdateResultsAndPersistOffline() throws {
        let url = folder()
        let log = Log()
        let (show, ids) = try show(at: url, log: log)
        let (opening, build, finale) = (ids[0], ids[1], ids[2])
        let showBefore = show.list.cues

        // Tag, then filter.
        XCTAssertTrue(show.addTag("Intro", toScene: opening))
        XCTAssertTrue(show.addTag("intro", toScene: finale))
        XCTAssertTrue(show.addTag("Loud", toScene: finale))
        XCTAssertEqual(show.tags(ofScene: finale), ["Intro", "Loud"], "the show's spelling is adopted")
        XCTAssertEqual(show.tagVocabulary, ["Intro", "Loud"])
        XCTAssertEqual(listed(show, tags: ["Intro"]), ["Opening", "Finale"])
        XCTAssertEqual(listed(show, tags: ["Intro", "Loud"]), ["Finale"], "chips combine with AND")
        XCTAssertEqual(listed(show, tags: [], query: "lou"), ["Finale"], "search matches tags")
        XCTAssertEqual(show.list.cues, showBefore, "tagging never changes a cue")
        XCTAssertEqual(show.list.positionText, "Standby", "and never moves the position")

        // Change a tag: the results update at once.
        XCTAssertTrue(show.removeTag("INTRO", fromScene: opening))
        XCTAssertEqual(listed(show, tags: ["Intro"]), ["Finale"])
        XCTAssertTrue(show.addTag("Intro", toScene: build))
        XCTAssertEqual(listed(show, tags: ["Intro"]), ["Build", "Finale"])
        XCTAssertEqual(log.spoken.last, "Tagged Build Intro.")

        // Reload from disk (local files only): the same tags and the same results.
        let again = coordinator(at: url, log: Log())
        XCTAssertEqual(again.tags(ofScene: finale), ["Intro", "Loud"])
        XCTAssertEqual(again.tags(ofScene: build), ["Intro"])
        XCTAssertEqual(again.tags(ofScene: opening), [])
        XCTAssertEqual(listed(again, tags: ["Intro"]), ["Build", "Finale"])
        XCTAssertEqual(listed(again, tags: ["Intro", "Loud"]), ["Finale"])
        XCTAssertNil(again.editorMessage)
        XCTAssertEqual(ShowStore(directory: url).load().warnings, [])
    }

    // MARK: - Rules and refusals (SCN-005-S3)

    func testRefusedTagsChangeNothingAndAreAnnounced() throws {
        let url = folder()
        let log = Log()
        let (show, ids) = try show(at: url, log: log)
        XCTAssertTrue(show.addTag("Intro", toScene: ids[0]))
        let bytes = try Data(contentsOf: ShowStore(directory: url).showFile)
        XCTAssertFalse(show.addTag("  INTRO ", toScene: ids[0]))
        XCTAssertEqual(show.editorMessage, "The scene is already tagged Intro.")
        XCTAssertEqual(log.spoken.last, "The scene is already tagged Intro.")
        XCTAssertFalse(show.addTag(String(repeating: "x", count: 41), toScene: ids[0]))
        XCTAssertEqual(show.editorMessage, "A tag is 1 to 40 characters on one line.")
        for n in 2...16 { XCTAssertTrue(show.addTag("t\(n)", toScene: ids[0])) }
        let full = try Data(contentsOf: ShowStore(directory: url).showFile)
        XCTAssertFalse(show.addTag("t17", toScene: ids[0]))
        XCTAssertEqual(show.editorMessage, "A scene has at most 16 tags.")
        XCTAssertEqual(try Data(contentsOf: ShowStore(directory: url).showFile), full, "a refusal writes nothing")
        XCTAssertNotEqual(bytes, full)
    }

    // MARK: - Duplicate, delete, vanished chips, unreadable scenes

    func testADuplicateCopiesTagsAndRemovingTheLastCueDropsThem() throws {
        let url = folder()
        let (show, ids) = try show(at: url, log: Log())
        XCTAssertTrue(show.addTag("Intro", toScene: ids[0]))
        let copy = try XCTUnwrap(show.duplicateScene(of: show.list.cues[0].id))
        XCTAssertEqual(show.tags(ofScene: copy.sceneID), ["Intro"])
        XCTAssertEqual(listed(show, tags: ["Intro"]), ["Opening", "Opening copy"])

        show.remove(show.list.cues[0].id)
        show.remove(copy.id)
        XCTAssertEqual(show.tagVocabulary, [], "the tag left with its scenes")
        let model = SceneSwitcherModel(now: { () -> Double in 0 })
        model.toggleTag("Intro", vocabulary: ["Intro"])
        model.pruneTags(vocabulary: show.tagVocabulary)
        XCTAssertEqual(model.selectedTags, [], "a vanished chip is dropped")
        XCTAssertFalse(String(decoding: try Data(contentsOf: ShowStore(directory: url).showFile), as: UTF8.self).contains("sceneTags"))
    }

    func testAnUnreadableSceneKeepsItsTagsAndCanBeTagged() throws {
        let url = folder()
        let (show, ids) = try show(at: url, log: Log())
        XCTAssertTrue(show.addTag("Intro", toScene: ids[0]))
        try Data("not a scene".utf8).write(to: ShowStore(directory: url).sceneFile(ids[0]))
        let again = coordinator(at: url, log: Log())
        XCTAssertTrue(again.unreadableScenes.contains(ids[0]))
        XCTAssertEqual(again.tags(ofScene: ids[0]), ["Intro"])
        XCTAssertTrue(again.addTag("Broken", toScene: ids[0]))
        XCTAssertEqual(listed(again, tags: ["Broken"]), ["Opening"])
    }
}
