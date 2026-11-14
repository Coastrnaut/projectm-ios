// SlideshowTests.swift — MED-006-T11, T13, T15, T17, T18 (app): the slideshow's store and its
// protection from the photo (FILE-008), the coordinator on an injected clock (the acceptance: five
// fixture pictures follow the saved order and timing mode, survive a relaunch and a scene round trip),
// the tempo rule, list edits, announcements, backup and erase. Each test has its own folder and
// defaults suite; no wall clock.
import Foundation
import ImageLayer
import LibraryBackup
import LocalPortability
import PerformanceControl
import SceneFormat
import XCTest
@testable import projectM_iOS

@MainActor
final class SlideshowTests: XCTestCase {
    private static let second: UInt64 = 1_000_000_000

    private struct Sandbox {
        let root: URL
        let defaults: UserDefaults
        let suite: String
        var photosFolder: URL { root.appendingPathComponent("Photos", isDirectory: true) }
        var photos: PhotoStore { PhotoStore(directory: photosFolder, defaults: defaults) }
        var store: SlideshowStore { SlideshowStore(photos: photos) }

        func cleanUp() {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suite)
        }
    }

    private func makeSandbox() throws -> Sandbox {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SlideshowTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "SlideshowTests.\(UUID().uuidString)"
        return Sandbox(root: root, defaults: try XCTUnwrap(UserDefaults(suiteName: suite)), suite: suite)
    }

    /// Five solid fixture pictures (red, green, blue, yellow, magenta) as picked files.
    private func pickedFiles(_ sandbox: Sandbox, count: Int = 5) throws -> [URL] {
        try (0..<count).map { (n: Int) throws -> URL in
            let color: (UInt8, UInt8, UInt8) = UITestPhotoFixture.slideshowColors[n % UITestPhotoFixture.slideshowColors.count]
            let url = sandbox.root.appendingPathComponent("picked\(n).png")
            try XCTUnwrap(UITestPhotoFixture.png(alpha: false, color: color)).write(to: url)
            return url
        }
    }

    /// A coordinator holding the five fixture pictures (imported through the real path).
    private func coordinator(_ sandbox: Sandbox, spoken: SpokenBox = SpokenBox()) async throws -> SlideshowCoordinator {
        let c = SlideshowCoordinator(store: sandbox.store, announce: { (text: String) -> Void in spoken.texts.append(text) })
        await c.importImages(at: try pickedFiles(sandbox), deleteAfterwards: false, alreadyFailed: 0)
        XCTAssertEqual(c.settings.slides.count, 5)
        return c
    }

    final class SpokenBox { var texts: [String] = [] }

    /// Ticks at 60 Hz for `duration`; returns each new slide's position.
    private func play(_ c: SlideshowCoordinator, from start: UInt64, for duration: UInt64, grid: SlideshowBeatGrid? = nil,
                      floor: UInt64 = SlideshowSafetyFloor.nanoseconds(flashesPerSecond: 3)) -> [Int] {
        var shown: [Int] = []
        var t: UInt64 = start
        while t <= start + duration {
            if c.tick(now: t, grid: grid, floorNanoseconds: floor) != nil { shown.append(c.shownIndex) }
            t += 16_666_667
        }
        return shown
    }

    // MARK: - The acceptance (MED-006-S1 to S3)

    /// "Five-image fixture follows saved ordering and timing mode": the saved order and mode drive the
    /// picture shown, and both survive a relaunch.
    func testFiveFixturePicturesFollowTheSavedOrderAndModeAndSurviveARelaunch() async throws {
        let sandbox = try makeSandbox()
        defer { sandbox.cleanUp() }
        let c = try await coordinator(sandbox)
        let imported: [UUID] = c.settings.slides
        // Save the order 2, 0, 4, 1, 3 and Time 3 s.
        c.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)          // 2 0 1 3 4
        c.move(fromOffsets: IndexSet(integer: 4), toOffset: 2)          // 2 0 4 1 3
        let saved: [UUID] = [imported[2], imported[0], imported[4], imported[1], imported[3]]
        XCTAssertEqual(c.settings.slides, saved)
        c.setSeconds(3)
        c.setEnabled(true)
        XCTAssertTrue(c.isActive)
        XCTAssertEqual(c.currentURL, sandbox.store.url(for: saved[0]), "the first slide of the saved order")
        XCTAssertEqual(c.nextURL, sandbox.store.url(for: saved[1]), "the next one is decoded ahead")

        // Relaunch: a new coordinator on the same folder and defaults.
        let relaunched = SlideshowCoordinator(store: sandbox.store)
        XCTAssertEqual(relaunched.settings, c.settings, "order and mode persisted")
        relaunched.restartPlayback()
        var urls: [URL?] = [relaunched.currentURL]
        var t: UInt64 = 50 * Self.second
        while t <= 50 * Self.second + 30 * Self.second {
            if let url = relaunched.tick(now: t, grid: nil, floorNanoseconds: Self.second) { urls.append(url) }
            t += 1_000_000   // 1 ms ticks: changes land exactly every 3 s
        }
        let expected: [URL?] = (0..<11).map { (n: Int) -> URL? in sandbox.store.url(for: saved[n % 5]) }
        XCTAssertEqual(urls, expected, "every 3 s, in the saved order, over two cycles")

        // Beats mode, saved and relaunched: every 2 beats of a steady 120 BPM grid.
        relaunched.setMode(.beats)
        relaunched.setBeats(2)
        let beats = SlideshowCoordinator(store: sandbox.store)
        XCTAssertEqual(beats.settings.mode, .beats)
        XCTAssertEqual(beats.settings.beats, 2)
        beats.restartPlayback()
        let grid = try XCTUnwrap(SlideshowBeatGrid(periodNanoseconds: Self.second / 2, anchorNanoseconds: 0))
        XCTAssertEqual(play(beats, from: 1, for: 10 * Self.second, grid: grid), [1, 2, 3, 4, 0, 1, 2, 3, 4], "a change every second (2 beats)")
    }

    /// S3: the saved order and mode survive a scene round trip (capture, change, restore), for autosave
    /// documents and show cues; a scene of another visual leaves the slideshow alone.
    func testOrderAndModeSurviveASceneRoundTrip() async throws {
        let sandbox = try makeSandbox()
        defer { sandbox.cleanUp() }
        let c = try await coordinator(sandbox)
        let ids: [UUID] = c.settings.slides
        c.move(fromOffsets: IndexSet(integer: 4), toOffset: 0)
        c.setEnabled(true)
        c.setMode(.beats)
        c.setBeats(8)
        let sceneOrder: [UUID] = c.settings.slides
        let registry = try SceneArchiveService.appRegistry()

        var inputs = SceneAutosaveFixtures.inputs(visual: .photo)
        inputs.photoID = nil
        inputs.slideshow = c.sceneValue
        let captured = SceneAutosaveCapture.document(inputs, carry: SceneAutosaveFixtures.carry, liveBindings: nil).document
        let asset = try XCTUnwrap(captured.assets[SceneAutosaveCapture.photoKey], "a slideshow alone writes the photo asset")
        XCTAssertEqual(asset.kind, .photo(storeID: sceneOrder[0].uuidString), "its store ID is the first slide")
        let folder = SceneAutosaveFixtures.folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try SceneAutosaveStore(directory: folder).save(captured.encoded())
        let load = SceneAutosaveStore(directory: folder).load(registry: registry, assets: nil)
        let document = try XCTUnwrap(load.document)
        let values = SceneAutosaveCapture.restoredValues(document, live: try XCTUnwrap(load.result).state, registry: registry)

        // Change everything, then restore.
        c.move(fromOffsets: IndexSet(integer: 0), toOffset: 5)
        c.setMode(.time)
        c.setEnabled(false)
        XCTAssertNotEqual(c.settings.slides, sceneOrder)
        c.restore(try XCTUnwrap(values.slideshow).value)
        XCTAssertEqual(c.settings.slides, sceneOrder, "the scene's order")
        XCTAssertEqual(c.settings.mode, .beats)
        XCTAssertEqual(c.settings.beats, 8)
        XCTAssertTrue(c.settings.enabled)

        // A show cue carries it too.
        let look = ShowLook(visual: .photo, bars: 64, orientation: .vertical, spacing: 0.2, glowEnabled: false, glowIntensity: 0.5,
                            glowRadius: 0.5, glowThreshold: 0.5, text: inputs.text, photoID: nil, videoID: nil,
                            slideshow: SceneSlideshow(enabled: true, storeIDs: [ids[1].uuidString, ids[0].uuidString], mode: "time",
                                                      seconds: 9, beats: 4))
        let cue = ShowSceneSnapshot.document(look, id: UUID().uuidString, name: "Cue")
        let apply = ShowSceneSnapshot.apply(of: cue, warnings: [], registry: registry)
        c.restore(try XCTUnwrap(apply.slideshow).value)
        XCTAssertEqual(Array(c.settings.slides.prefix(2)), [ids[1], ids[0]], "named slides first, in the scene's order")
        XCTAssertEqual(Set(c.settings.slides), Set(ids), "a restore never adds or removes pictures")
        XCTAssertEqual(c.settings.seconds, 9)

        // Other visuals' scenes have no photo layer: nothing to restore. An absent field turns it off.
        let plain = SceneAutosaveCapture.document(SceneAutosaveFixtures.inputs(visual: .circularSpectrum), carry: SceneAutosaveFixtures.carry,
                                                  liveBindings: nil).document
        XCTAssertNil(SceneSlideshowBridge.restore(in: plain))
        c.restore(nil)
        XCTAssertFalse(c.settings.enabled)
        XCTAssertEqual(c.settings.slides.count, 5)
    }

    // MARK: - Tempo (S4, R6)

    func testOnlyAManualOrStableTempoWithAPhaseGivesABeatGrid() {
        let estimate = TempoEstimate(bpm: 120, confidence: 0.9, beatNanoseconds: 5 * Self.second)
        var source = TempoSource()
        source.updateEstimate(estimate)
        let snapshot: TempoSnapshot = source.snapshot
        XCTAssertNotNil(SlideshowCoordinator.grid(snapshot: snapshot, readout: .stable(bpm: 120)))
        XCTAssertNotNil(SlideshowCoordinator.grid(snapshot: snapshot, readout: .manual(bpm: 120)))
        XCTAssertNil(SlideshowCoordinator.grid(snapshot: snapshot, readout: .uncertain(bpm: 120)), "uncertain: Time rules")
        XCTAssertNil(SlideshowCoordinator.grid(snapshot: snapshot, readout: .searching), "searching: Time rules")
        XCTAssertNil(SlideshowCoordinator.grid(snapshot: .none, readout: .stable(bpm: 120)), "no phase: Time rules")
        let grid = SlideshowCoordinator.grid(snapshot: snapshot, readout: .stable(bpm: 120))
        XCTAssertEqual(grid?.periodNanoseconds, Self.second / 2)
        XCTAssertEqual(grid?.anchorNanoseconds, 5 * Self.second)
    }

    // MARK: - Edits, protection, announcements (S7, R2, R11, R13)

    func testEditsKeepTheShownPictureAndReleaseRemovedReferences() async throws {
        let sandbox = try makeSandbox()
        defer { sandbox.cleanUp() }
        let spoken = SpokenBox()
        let c = try await coordinator(sandbox, spoken: spoken)
        XCTAssertEqual(spoken.texts.last, "Added 5 pictures to the slideshow.")
        let ids: [UUID] = c.settings.slides
        XCTAssertEqual(sandbox.photos.folder.payloadNames().count, 5, "five different pictures, five payloads")
        c.setEnabled(true)
        var playbackChanges = 0
        c.onPlaybackChange = { () -> Void in playbackChanges += 1 }
        _ = play(c, from: 0, for: 5 * Self.second + Self.second / 2)   // one change: shows ids[1]
        XCTAssertEqual(c.shownIndex, 1)

        c.moveDown(ids[1])
        XCTAssertEqual(c.settings.slides[2], ids[1])
        XCTAssertEqual(c.currentURL, sandbox.store.url(for: ids[1]), "moving keeps the shown picture")
        XCTAssertEqual(spoken.texts.last, "Picture 3 of 5")
        c.moveUp(ids[1])
        XCTAssertEqual(c.settings.slides, ids)

        let removedURL = try XCTUnwrap(sandbox.store.url(for: ids[1]))
        c.remove(ids[1])
        XCTAssertNil(sandbox.photos.existingFile(for: ids[1]), "the reference is released")
        XCTAssertFalse(FileManager.default.fileExists(atPath: removedURL.path), "an unshared payload is deleted")
        XCTAssertEqual(c.currentURL, sandbox.store.url(for: ids[2]), "removing the shown picture shows its successor")
        XCTAssertEqual(playbackChanges, 1)
        XCTAssertEqual(spoken.texts.last, "Picture removed from the slideshow.")

        // A new photo and Remove Photo release no slide, even one sharing its picture.
        let photo = try sandbox.photos.importImage(at: try pickedFiles(sandbox, count: 1)[0])   // same bytes as slide 0
        XCTAssertTrue(sandbox.photos.folder.sharesPayload(photo.id, ids[0]))
        _ = try sandbox.photos.importImage(at: try pickedFiles(sandbox, count: 3)[2])          // same bytes as slide 2
        sandbox.photos.remove()
        for id in c.settings.slides {
            XCTAssertNotNil(sandbox.photos.existingFile(for: id), "slide \(id) survives a new photo and Remove Photo")
        }

        c.clear()
        XCTAssertEqual(c.settings.slides, [])
        XCTAssertFalse(c.isActive)
        XCTAssertEqual(sandbox.photos.folder.payloadNames().count, 0, "every picture left the device")
        XCTAssertEqual(spoken.texts.last, "Slideshow cleared.")
    }

    func testTheTwentyPictureLimitAndUnresolvedIdentifiers() async throws {
        let sandbox = try makeSandbox()
        defer { sandbox.cleanUp() }
        let spoken = SpokenBox()
        let c = SlideshowCoordinator(store: sandbox.store, announce: { (text: String) -> Void in spoken.texts.append(text) })
        let files: [URL] = try pickedFiles(sandbox, count: 5)
        let many: [URL] = Array(repeating: files, count: 5).flatMap { (batch: [URL]) -> [URL] in batch }   // 25
        await c.importImages(at: many, deleteAfterwards: false, alreadyFailed: 0)
        XCTAssertEqual(c.settings.slides.count, 20)
        XCTAssertEqual(c.notice, SlideshowCoordinator.fullMessage, "the rest are refused with a notice")
        XCTAssertEqual(sandbox.photos.folder.payloadNames().count, 5, "equal pictures share payloads")
        // A reference released behind the store's back is dropped on the next read.
        try sandbox.photos.folder.release([c.settings.slides[0]])
        XCTAssertEqual(sandbox.store.settings().slides.count, 19)
        XCTAssertEqual(SlideshowStore.protectedIDs(sandbox.defaults).count, 19, "the cleaned value was saved")
    }

    // MARK: - Backup and erase (S7, R10)

    func testBackupIncludesAndEraseRemovesTheSlideshow() async throws {
        XCTAssertEqual(LibrarySettingsPolicy.slideshowKey, SlideshowStore.key)
        XCTAssertTrue(AppSettings.allKeys.contains(SlideshowStore.key), "the UI tests' reset clears it")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SlideshowBackup-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "SlideshowBackup.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let folders = LibraryFolders(root: root.appendingPathComponent("lib", isDirectory: true))
        let store = SlideshowStore(photos: PhotoStore(directory: folders.url(.photos), defaults: defaults))
        let sandbox = Sandbox(root: root, defaults: defaults, suite: suite)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let c = SlideshowCoordinator(store: store)
        await c.importImages(at: try pickedFiles(sandbox, count: 2), deleteAfterwards: false, alreadyFailed: 0)
        c.setEnabled(true)

        let contents = try LibraryContentsReader.read(folders: folders, settings: LibrarySettingsBridge.read(defaults), videos: 0, importedAudio: 0)
        XCTAssertNotNil(contents.settings[SlideshowStore.key], "the slideshow setting is backed up")
        let names: Set<String> = Set(contents.photos.keys.map { (name: String) -> String in String(name.prefix(36)) })
        XCTAssertEqual(names, Set(c.settings.slides.map(\.uuidString)), "and every slide picture")

        let backup = LibraryBackupCoordinator(folders: folders, defaults: defaults, temporaryRoot: root.appendingPathComponent("temp"))
        let model = backup.erase
        model.openSheet()
        model.toggle(.media)
        model.requestErase()
        LibraryBackupCoordinator.finishPendingRestore(defaults: defaults, folders: folders)
        XCTAssertNil(defaults.object(forKey: SlideshowStore.key), "Photos and videos erase removes the setting")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folders.url(.photos).path), "and the pictures")
        XCTAssertEqual(SlideshowCoordinator(store: store).settings, .off)
    }
}
