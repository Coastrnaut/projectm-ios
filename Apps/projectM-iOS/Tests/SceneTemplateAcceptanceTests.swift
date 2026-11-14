// SceneTemplateAcceptanceTests.swift — SCN-011-T07, T09: the roadmap acceptance in the app ("Template
// instantiation creates independent local copy"; SCN-011-S1 to S3). Templates come from the app bundle's
// `SceneTemplates/` folder and are added through ShowCoordinator into a fresh temporary show store:
// 1. the same template twice gives two distinct scene IDs and two files;
// 2. editing copy 1 and saving leaves copy 2 and the bundled template byte-identical;
// 3. deleting copy 1's cue leaves copy 2 loadable.
// Also: every bundled template validates against the app's registry with no warnings and needs no repair
// report; adding applies nothing and keeps the position; Show Starter adds two cues with a crossfade; a show
// without room refuses with nothing written. Nothing reads the wall clock.
import Foundation
import ParameterGraph
import SceneFormat
import ShowControl
import ShowStorage
import TextLayer
import XCTest
@testable import projectM_iOS

@MainActor
final class SceneTemplateAcceptanceTests: XCTestCase {
    private final class Log {
        var spoken: [String] = []
        var applied = 0
        var changedFiles: [Set<String>] = []
    }

    private func folder() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SceneTemplateAcceptanceTests-\(UUID().uuidString)",
                                                                                isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func coordinator(at url: URL, log: Log) -> ShowCoordinator {
        let show = ShowCoordinator(store: ShowStore(directory: url), registry: try? SceneArchiveService.appRegistry())
        show.applyScene = { (_: SceneDocument, _: [SceneIssue]) -> [String] in log.applied += 1; return [] }
        show.announce = { (_: String) in }
        show.announceLibrary = { (message: String) in log.spoken.append(message) }
        show.sceneFilesChanged = { (ids: Set<String>) in log.changedFiles.append(ids) }
        return show
    }

    private func template(_ id: String) throws -> SceneTemplate {
        try XCTUnwrap(ShowCoordinator.bundledTemplates().template(id), "\(id) is bundled")
    }

    func testTheBundleOffersEveryTemplateAndEachValidatesWithoutWarnings() throws {
        let catalog = ShowCoordinator.bundledTemplates()
        XCTAssertEqual(catalog.skipped, [])
        XCTAssertEqual(catalog.templates.count, 5)
        let registry = try SceneArchiveService.appRegistry()
        let none = StoredMediaAvailability(photos: [], videos: [])
        for scene in catalog.templates.flatMap(\.scenes) {
            let loaded = try scene.document.liveState(registry: registry, assets: none)
            XCTAssertEqual(loaded.warnings, [], "\(scene.label) validates without warnings")
            let report = SceneRepairReport(document: scene.document, decodeWarnings: [], registry: registry, assets: none)
            XCTAssertFalse(report.needsReview, "\(scene.label) opens without a repair report")
            let apply = ShowSceneSnapshot.apply(of: scene.document, warnings: [], registry: registry)
            XCTAssertEqual(apply.omittedKinds, [], "every layer is drawn")
            XCTAssertNotEqual(apply.visual, .projectM, "a native visual")
        }
        let title = try template("title-card")
        let apply = ShowSceneSnapshot.apply(of: title.scenes[0].document, warnings: [], registry: registry)
        XCTAssertEqual(apply.visual, .text)
        XCTAssertEqual(apply.text?.message, "Your Title Here")
    }

    // MARK: - The acceptance (SCN-011-S1, S2)

    func testTemplateInstantiationCreatesIndependentLocalCopies() throws {
        let url = folder()
        let log = Log()
        let show = coordinator(at: url, log: log)
        let pulse = try template("pulse-rings")
        let templateFile = pulse.scenes[0].file
        let templateBytes = try Data(contentsOf: templateFile)

        // 1. Twice: two distinct scene IDs, two separate files, two cues; nothing applied, Standby kept.
        let first = try XCTUnwrap(show.addTemplate(pulse))
        let second = try XCTUnwrap(show.addTemplate(pulse))
        XCTAssertEqual(show.list.cues.map(\.label), ["Pulse Rings", "Pulse Rings"])
        let (one, two) = (first[0].sceneID, second[0].sceneID)
        XCTAssertNotEqual(one, two)
        XCTAssertFalse([one, two].contains(pulse.scenes[0].document.id), "never the template's ID")
        let store = ShowStore(directory: url)
        XCTAssertEqual(store.storedSceneIDs(), [one, two])
        XCTAssertNotEqual(store.sceneFile(one), store.sceneFile(two))
        XCTAssertEqual(show.tags(ofScene: one), ["template"])
        XCTAssertNil(show.list.activeCue, "the position stays")
        XCTAssertEqual(log.applied, 0, "adding applies nothing")
        XCTAssertEqual(log.changedFiles, [[one], [two]], "SCN-006 hears of each copy")
        XCTAssertEqual(log.spoken, ["Added Pulse Rings from templates.", "Added Pulse Rings from templates."])
        let twoBytes = try Data(contentsOf: store.sceneFile(two))

        // 2. Edit copy 1 (a parameter) and save it: copy 2 and the bundled template are byte-identical.
        var edited = try store.scene(one).document
        edited.parameters["effect.bloom.intensity"] = .continuous(0.2)
        try store.saveScene(edited)
        XCTAssertTrue(show.renameScene(of: first[0].id, to: "My Rings"))
        XCTAssertEqual(try store.scene(one).document.parameters["effect.bloom.intensity"], .continuous(0.2))
        XCTAssertEqual(try Data(contentsOf: store.sceneFile(two)), twoBytes, "copy 2 untouched")
        XCTAssertEqual(try Data(contentsOf: templateFile), templateBytes, "the template untouched")

        // 3. Delete copy 1: copy 2 still loads, and still shows.
        show.remove(first[0].id)
        XCTAssertEqual(store.storedSceneIDs(), [two], "copy 1's file went with its cue")
        XCTAssertEqual(try store.scene(two).document.name, "Pulse Rings")
        XCTAssertTrue(show.go(to: second[0].id).moved)
        XCTAssertEqual(show.appliedSceneID, two)
        XCTAssertEqual(try Data(contentsOf: templateFile), templateBytes)
    }

    // MARK: - Show Starter (US2)

    func testShowStarterAddsTwoCuesWithACrossfadeIntoTheSecond() throws {
        let show = coordinator(at: folder(), log: Log())
        let cues = try XCTUnwrap(show.addTemplate(try template("show-starter")))
        XCTAssertEqual(cues.map(\.label), ["Opening", "Welcome"])
        XCTAssertEqual(show.list.cues.map(\.label), ["Opening", "Welcome"])
        XCTAssertNil(show.list.cues[0].transition)
        XCTAssertEqual(show.list.cues[1].transition?.type, .crossfade)
        XCTAssertEqual(show.list.cues[1].transition?.durationSeconds, 1.5)
        XCTAssertEqual(Set(show.list.sceneIDs).count, 2)
    }

    func testAShowWithoutRoomRefusesAndWritesNothing() throws {
        let url = folder()
        let log = Log()
        let show = coordinator(at: url, log: log)
        let pulse = try template("pulse-rings")
        _ = try XCTUnwrap(show.addTemplate(pulse))
        var full = show.list
        while full.cues.count < ShowCueList.maximumCues - 1 {
            _ = try full.append(sceneID: show.list.cues[0].sceneID, label: "Again")
        }
        show.replaceForUITests(full)
        let store = ShowStore(directory: url)
        let showBytes = try Data(contentsOf: store.showFile)
        let stored = store.storedSceneIDs()

        XCTAssertNil(show.addTemplate(try template("show-starter")), "two cues do not fit in one free slot")
        XCTAssertEqual(show.list.cues.count, ShowCueList.maximumCues - 1)
        XCTAssertEqual(store.storedSceneIDs(), stored, "no scene file written")
        XCTAssertEqual(try Data(contentsOf: store.showFile), showBytes, "the show file unchanged")
        XCTAssertEqual(log.spoken.last, ShowEditError.tooManyCues(limit: ShowCueList.maximumCues).description)
    }
}
