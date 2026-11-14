// ScenePreviewAcceptanceTests.swift — SCN-006-T08: the roadmap acceptance in the app ("Preview
// corresponds to saved scene and invalidates after edit"; SCN-006-S1 to S3). ShowCoordinator and
// ScenePreviewModel are wired as AppCoordinator wires them, over temporary folders, with an injected
// capture that returns a known picture per scene state (the applied scene's name and file hash) and an
// injected settle (no clock).
//
// 1. Save S: its preview equals the captured picture and is keyed to S's content hash.
// 2. Edit S (a parameter changes and the file is saved): the old preview and file are gone, S shows the
//    placeholder, and the next apply's capture is keyed to the new hash. Rename invalidates too.
// 3. Neighbours are untouched. Removing S's cue prunes it. Relaunch keeps previews. A second apply
//    captures nothing; a look edited or another scene applied during the settle drops the capture.
import Foundation
import ParameterGraph
import PresetLibrary
import SceneFormat
import ShowControl
import ShowStorage
import TextLayer
import XCTest
@testable import projectM_iOS

@MainActor
final class ScenePreviewAcceptanceTests: XCTestCase {
    /// The live output as the fake capture sees it.
    @MainActor
    private final class Live {
        var document: SceneDocument?
        var look: ShowLook?
        var canCapture = true
        var captures = 0
        var tasks: [Task<Bool, Never>] = []
        var changes: [Task<Void, Never>] = []
        /// Runs during the settle (simulates the user acting while the picture settles).
        var duringSettle: (@MainActor () -> Void)?

        /// The known picture of the live state: the applied scene's name and file hash.
        func picture() -> Data? {
            captures += 1
            guard let document else { return nil }
            return Data("PNG:\(document.name):\(ScenePreviewKey.contentHash(of: Data(document.encoded())))".utf8)
        }

        func drain() async {
            for task in changes { await task.value }
            changes.removeAll()
        }
    }

    private struct Rig {
        let show: ShowCoordinator
        let previews: ScenePreviewModel
        let live: Live
        let ids: [String]
    }

    private func folder(_ name: String) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ScenePreviewAcceptance-\(name)-\(UUID().uuidString)",
                                                                                isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func look(_ visual: VisualChoice, bars: Int = 64) -> ShowLook {
        ShowLook(visual: visual, bars: bars, orientation: .horizontal, spacing: 0.5, glowEnabled: false, glowIntensity: 0.7,
                 glowRadius: 0.03, glowThreshold: 0.4, text: TextOverlaySpec(message: ""), photoID: nil, videoID: nil)
    }

    /// A coordinator and preview model over `showURL` and `cacheURL`, wired like AppCoordinator.
    private func rig(show showURL: URL, cache cacheURL: URL, live: Live = Live()) -> (ShowCoordinator, ScenePreviewModel) {
        let show = ShowCoordinator(store: ShowStore(directory: showURL), registry: try? SceneArchiveService.appRegistry())
        show.announce = { (_: String) in }
        let previews = ScenePreviewModel(
            store: ScenePreviewStore(directory: cacheURL),
            capture: { @MainActor () async -> Data? in live.picture() },
            sceneFile: { [weak show] (id: String) -> URL? in show?.sceneFileURL(id) },
            context: { [weak show] () -> ScenePreviewContext in
                ScenePreviewContext(appliedSceneID: show?.appliedSceneID, look: live.look, canCapture: live.canCapture)
            },
            sleep: { (_: Duration) async in await MainActor.run { live.duringSettle?() } })
        show.applyScene = { (document: SceneDocument, _: [SceneIssue]) -> [String] in
            live.document = document
            live.tasks.append(previews.sceneApplied(document.id))
            return []
        }
        show.sceneFilesChanged = { (ids: Set<String>) in live.changes.append(previews.scenesChanged(ids)) }
        show.previews = previews
        return (show, previews)
    }

    /// Three scenes saved as Add Current Scene does (each captured at once).
    private func savedShow() async throws -> Rig {
        let live = Live()
        let (show, previews) = rig(show: folder("show"), cache: folder("cache"), live: live)
        var ids: [String] = []
        let looks: [(VisualChoice, String)] = [(.circularSpectrum, "Opening"), (.linearSpectrum, "Build"), (.circularSpectrum, "Finale")]
        for (visual, name) in looks {
            let document = ShowSceneSnapshot.document(look(visual), id: UUID().uuidString, name: name)
            live.document = document   // the output shows the look being saved
            XCTAssertTrue(show.addScene(document, label: name))
            await live.drain()
            let stored = await previews.sceneSaved(document.id).value
            XCTAssertTrue(stored, "\(name) captured on save")
            ids.append(document.id)
        }
        return Rig(show: show, previews: previews, live: live, ids: ids)
    }

    private func fileHash(_ rig: Rig, _ id: String) throws -> String {
        ScenePreviewKey.contentHash(of: try Data(contentsOf: XCTUnwrap(rig.show.sceneFileURL(id))))
    }

    private func storedBytes(_ previews: ScenePreviewModel, _ id: String) async -> Data? {
        guard let key = previews.key(forScene: id), let url = await previews.store.cachedURL(for: key) else { return nil }
        return try? Data(contentsOf: url)
    }

    private func applied(_ rig: Rig, _ index: Int) async -> Bool {
        rig.show.go(to: rig.show.list.cues[index].id)
        guard let task = rig.live.tasks.last else { return false }
        return await task.value
    }

    // MARK: - Acceptance

    func testSavedPreviewIsTheCapturedPictureKeyedToTheSceneFile() async throws {
        let rig = try await savedShow()
        let s = rig.ids[0]
        let hash = try fileHash(rig, s)
        let bytes = await storedBytes(rig.previews, s)
        XCTAssertEqual(bytes, Data("PNG:Opening:\(hash)".utf8), "the preview is the captured picture of the saved scene")
        let entries = await rig.previews.store.entries(forScene: s)
        XCTAssertEqual(entries.map(\.contentHash), [hash], "keyed to S's content hash")
        let image = await rig.previews.image(forScene: s)
        XCTAssertNil(image, "fake bytes are not a picture; the key and bytes are what is checked")
    }

    func testEditInvalidatesOnlyThatSceneAndTheNextApplyIsKeyedToTheNewHash() async throws {
        let rig = try await savedShow()
        let s = rig.ids[0]
        let oldHash = try fileHash(rig, s)
        let oldURL = await rig.previews.store.cachedURL(for: ScenePreviewKey(sceneID: s, contentHash: oldHash))
        let neighbours: [Data?] = [await storedBytes(rig.previews, rig.ids[1]), await storedBytes(rig.previews, rig.ids[2])]

        // Edit S: a parameter changes (64 → 16 bars) and the file is saved; the writer reports it.
        let edited = ShowSceneSnapshot.document(look(.circularSpectrum, bars: 16), id: s, name: "Opening")
        try XCTUnwrap(rig.show.store).saveScene(edited)
        rig.show.sceneFilesChanged([s])
        await rig.live.drain()

        let newHash = try fileHash(rig, s)
        XCTAssertNotEqual(newHash, oldHash)
        let left = await rig.previews.store.entries(forScene: s)
        XCTAssertEqual(left.count, 0, "the old preview is gone")
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(oldURL).path), "with its file")
        let placeholder = await storedBytes(rig.previews, s)
        XCTAssertNil(placeholder, "S shows the placeholder until it is shown again")
        let after: [Data?] = [await storedBytes(rig.previews, rig.ids[1]), await storedBytes(rig.previews, rig.ids[2])]
        XCTAssertEqual(after, neighbours, "neighbours untouched")
        XCTAssertTrue(after.allSatisfy { $0 != nil })

        // Shown again: the capture is keyed to the new hash and shows the edited scene.
        let captured = await applied(rig, 0)
        XCTAssertTrue(captured)
        let entries = await rig.previews.store.entries(forScene: s)
        XCTAssertEqual(entries.map(\.contentHash), [newHash])
        let bytes = await storedBytes(rig.previews, s)
        XCTAssertEqual(bytes, Data("PNG:Opening:\(newHash)".utf8))

        // SCN-003 Rename rewrites the file, so it invalidates too.
        XCTAssertTrue(rig.show.renameScene(of: rig.show.list.cues[0].id, to: "Intro"))
        await rig.live.drain()
        let renamed = await rig.previews.store.entries(forScene: s)
        XCTAssertEqual(renamed.count, 0)
    }

    func testRemovingTheLastCuePrunesThePreview() async throws {
        let rig = try await savedShow()
        let s = rig.ids[1]
        rig.show.remove(rig.show.list.cues[1].id)
        await rig.live.drain()
        let entries = await rig.previews.store.entries(forScene: s)
        XCTAssertEqual(entries.count, 0)
        let count = await rig.previews.store.entryCount
        XCTAssertEqual(count, 2)
    }

    func testPlaceholderUntilAppliedThenOneCaptureAndRelaunchKeepsIt() async throws {
        let showURL = folder("show"), cacheURL = folder("cache")
        let live = Live()
        let (show, previews) = rig(show: showURL, cache: cacheURL, live: live)
        let document = ShowSceneSnapshot.document(look(.linearSpectrum), id: UUID().uuidString, name: "Build")
        XCTAssertTrue(show.addScene(document, label: "Build"))   // added without a capture (e.g. imported)
        let other = ShowSceneSnapshot.document(look(.circularSpectrum), id: UUID().uuidString, name: "Other")
        XCTAssertTrue(show.addScene(other, label: "Other"))
        await live.drain()
        let none = await storedBytes(previews, document.id)
        XCTAssertNil(none, "placeholder when missing")

        show.go(to: show.list.cues[0].id)
        let first = await live.tasks.last?.value
        XCTAssertEqual(first, true, "captured after the settle")
        XCTAssertEqual(live.captures, 1)
        show.go(to: show.list.cues[1].id)
        _ = await live.tasks.last?.value
        show.go(to: show.list.cues[0].id)
        let second = await live.tasks.last?.value
        XCTAssertEqual(second, false, "a scene with a preview is not captured again")
        XCTAssertEqual(live.captures, 2, "one capture per scene")

        // Relaunch: new coordinator and model over the same folders.
        let (show2, previews2) = rig(show: showURL, cache: cacheURL)
        await previews2.reconcile(sceneIDs: show2.list.sceneIDs).value
        let bytes = await storedBytes(previews2, document.id)
        let hash = ScenePreviewKey.contentHash(of: try Data(contentsOf: XCTUnwrap(show2.sceneFileURL(document.id))))
        XCTAssertEqual(bytes, Data("PNG:Build:\(hash)".utf8), "the preview survives a relaunch")
    }

    func testCaptureIsDroppedWhenTheLookChangesOrAnotherSceneIsAppliedDuringTheSettle() async throws {
        let live = Live()
        let (show, previews) = rig(show: folder("show"), cache: folder("cache"), live: live)
        for name in ["A", "B"] {
            XCTAssertTrue(show.addScene(ShowSceneSnapshot.document(look(.circularSpectrum), id: UUID().uuidString, name: name), label: name))
        }
        await live.drain()
        live.look = look(.circularSpectrum)
        live.duringSettle = { live.look = self.look(.circularSpectrum, bars: 16) }   // the user edits a setting
        show.go(to: show.list.cues[0].id)
        let edited = await live.tasks.last?.value
        XCTAssertEqual(edited, false)
        XCTAssertEqual(live.captures, 0)

        live.duringSettle = nil
        live.canCapture = false   // blacked out or paused
        show.go(to: show.list.cues[1].id)
        let blackedOut = await live.tasks.last?.value
        XCTAssertEqual(blackedOut, false)

        live.canCapture = true
        live.duringSettle = {   // another scene applied during the settle (once)
            live.duringSettle = nil
            show.go(to: show.list.cues[0].id)
        }
        show.go(to: show.list.cues[1].id)
        let replaced = await live.tasks[live.tasks.count - 2].value
        XCTAssertEqual(replaced, false, "a later apply cancels the pending capture")
        _ = await live.tasks.last?.value
        let count = await previews.store.entryCount
        XCTAssertLessThanOrEqual(count, 1)
    }

    func testPreviewPictureIsCroppedAndScaled() throws {
        var rgba = [UInt8](repeating: 0, count: 40 * 30 * 4)
        for i in stride(from: 0, to: rgba.count, by: 4) { rgba[i] = 255; rgba[i + 3] = 255 }
        let png = try XCTUnwrap(ScenePreviewCapture.png(rgba: rgba, width: 40, height: 30))
        let image = try XCTUnwrap(UIImage(data: png))
        XCTAssertEqual(image.size.width * image.scale, CGFloat(ScenePreviewStore.width))
        XCTAssertEqual(image.size.height * image.scale, CGFloat(ScenePreviewStore.height))
        XCTAssertEqual(ScenePreviewCapture.centreCrop(width: 1179, height: 2556), CGRect(x: 0, y: 947, width: 1179, height: 663))
        XCTAssertEqual(ScenePreviewCapture.centreCrop(width: 1920, height: 1080), CGRect(x: 0, y: 0, width: 1920, height: 1080))
    }
}
