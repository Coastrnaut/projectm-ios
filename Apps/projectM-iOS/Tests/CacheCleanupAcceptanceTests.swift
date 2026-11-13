// CacheCleanupAcceptanceTests.swift — FILE-010-T04, T05, T06, T09: the row's acceptance, "Cleanup removes
// cache only and all saved scenes remain loadable" (FILE-010-S1, S2), on a fixture container laid out by
// `StorageLocations.make` with user data written through the app's own stores; the Storage screen model's
// confirm, cancel and nothing-to-clear paths (FILE-010-R2, R6); and the in-use provider (R5).
// Each test uses its own temporary container; no clock, no network.
import Foundation
import LocalPortability
import SceneFormat
import ShowControl
import ShowStorage
import XCTest
@testable import projectM_iOS

/// A container with user data in every protected folder and items in every cache folder.
private struct CleanupFixture {
    let container: URL
    let locations: StorageLocations
    let sceneStore: SceneAutosaveStore
    let showStore: ShowStore
    let firstScene: SceneDocument
    let secondScene: SceneDocument
    let showScenes: [SceneDocument]
    let offeredRecording: URL
    let leftoverRecording: URL
    let photo: URL

    static func sceneID(_ n: Int) -> String {
        UUID(uuidString: String(format: "5CE7E000-0000-4000-8000-%012d", n))?.uuidString ?? ""
    }

    init() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("FILE010-\(UUID().uuidString)", isDirectory: true)
        let support = base.appendingPathComponent("Library/Application Support", isDirectory: true)
        let layout = StorageLocations.make(applicationSupport: support,
                                           temporary: base.appendingPathComponent("tmp", isDirectory: true),
                                           caches: base.appendingPathComponent("Library/Caches", isDirectory: true),
                                           container: base)
        container = base
        locations = layout
        func root(_ category: StorageCategory, _ index: Int = 0) -> URL { (layout.roots[category] ?? [])[index] }
        func write(_ size: Int, _ byte: UInt8, to url: URL) throws {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data((0..<size).map { (i: Int) -> UInt8 in byte &+ UInt8(i % 199) }).write(to: url)
        }

        // User data.
        let photoFile = root(.photos).appendingPathComponent("photo.heic")
        photo = photoFile
        try write(4_000, 1, to: photoFile)
        try write(9_000, 2, to: root(.videos).appendingPathComponent("video.mov"))
        let scenes = SceneAutosaveStore(directory: root(.scenes))
        try fm.createDirectory(at: root(.scenes), withIntermediateDirectories: true)
        let first = SceneAutosaveFixtures.document(bars: 16), second = SceneAutosaveFixtures.document(bars: 32)
        try scenes.save(first.encoded())
        try scenes.save(second.encoded())   // the first becomes the backup
        sceneStore = scenes
        firstScene = first
        secondScene = second
        let shows = ShowStore(directory: support.appendingPathComponent(StorageLocations.showFolderName, isDirectory: true))
        let snapshots = [1, 2].map { (n: Int) -> SceneDocument in
            SceneDocument(id: Self.sceneID(n), name: "Show scene \(n)",
                          layers: [SceneLayer(instance: 1, content: n == 1 ? .circularSpectrum : .linearSpectrum)])
        }
        var list = ShowCueList(name: "Acceptance")
        for (n, scene) in snapshots.enumerated() {
            try shows.saveScene(scene)
            try list.append(sceneID: scene.id, label: "Cue \(n + 1)")
        }
        try shows.save(list)
        showStore = shows
        showScenes = snapshots
        try write(3_000, 3, to: root(.presets, 0).appendingPathComponent("preset.json"))
        try write(1_000, 4, to: root(.presets, 1).appendingPathComponent("collections.json"))
        try write(6_000, 5, to: root(.importedAudio).appendingPathComponent("track.m4a"))
        try write(500, 6, to: support.deletingLastPathComponent().appendingPathComponent("Preferences/settings.plist"))

        // Caches and intermediates, in all five folders.
        let offered = root(.recordings).appendingPathComponent("offered.mov")
        let leftover = root(.recordings).appendingPathComponent("leftover.mov")
        try write(2_000, 7, to: offered)
        try write(2_500, 8, to: leftover)
        offeredRecording = offered
        leftoverRecording = leftover
        try write(700, 9, to: root(.sharesAndExports, 0).appendingPathComponent("UUID-1/share.png"))
        try write(800, 10, to: root(.sharesAndExports, 1).appendingPathComponent("scene.pmscene"))
        try write(900, 11, to: root(.sharesAndExports, 2).appendingPathComponent("UUID-2/presets.zip"))
        try write(1_100, 12, to: root(.caches).appendingPathComponent("com.apple.metal/shaders.data"))
        try fm.createSymbolicLink(at: root(.caches).appendingPathComponent("photo-link"), withDestinationURL: photoFile)
        try fm.createSymbolicLink(at: root(.sharesAndExports, 0).appendingPathComponent("support-link"), withDestinationURL: support)
    }

    func remove() { try? FileManager.default.removeItem(at: container) }

    /// Every regular file outside the cache folders, with its bytes.
    func userFiles() throws -> [String: Data] {
        let cacheRoots = StorageCategory.cleanable.flatMap { (category: StorageCategory) -> [URL] in locations.roots[category] ?? [] }
            .map { (url: URL) -> String in url.resolvingSymlinksInPath().path + "/" }
        var files: [String: Data] = [:]
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let walker = FileManager.default.enumerator(at: container, includingPropertiesForKeys: keys) else { return files }
        for case let url as URL in walker {
            let path = url.resolvingSymlinksInPath().path
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  !cacheRoots.contains(where: { (root: String) -> Bool in path.hasPrefix(root) }) else { continue }
            files[path] = try Data(contentsOf: url)
        }
        return files
    }

    func contents(_ category: StorageCategory) -> [String] {
        (locations.roots[category] ?? []).flatMap { (url: URL) -> [String] in
            ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted()
        }
    }
}

@MainActor
final class CacheCleanupAcceptanceTests: XCTestCase {
    // FILE-010-S1, S2: the acceptance.
    func testCleanupRemovesCacheOnlyAndEverySavedSceneStillLoads() throws {
        let fixture = try CleanupFixture()
        defer { fixture.remove() }
        let before = try fixture.userFiles()
        XCTAssertEqual(before.count, 11, "photo, video, scene main + backup, show + 2 scenes, preset, collections, audio, preferences")

        let cleaner = CacheCleaner()
        let inUse: Set<String> = [fixture.offeredRecording.path]
        let plan = try cleaner.plan(fixture.locations.cleanupRequest(inUse: inUse))
        XCTAssertTrue(plan.refused.isEmpty, "\(plan.refused)")
        XCTAssertEqual(plan.usage(.recordings).contentBytes, 2_500)
        XCTAssertEqual(plan.usage(.sharesAndExports).contentBytes, 2_400)
        XCTAssertEqual(plan.usage(.caches).contentBytes, 1_100)
        let result = cleaner.execute(plan, inUse: inUse)
        XCTAssertTrue(result.failed.isEmpty, "\(result.failed)")
        XCTAssertEqual(result.removed.count, 7, "leftover, share folder, share link, scene archive, preset export folder, metal folder, photo link")

        // User data byte-identical.
        XCTAssertEqual(try fixture.userFiles(), before)
        // Caches gone; the in-use recording kept; the cache folders themselves stay.
        XCTAssertEqual(fixture.contents(.recordings), ["offered.mov"])
        XCTAssertEqual(fixture.contents(.sharesAndExports), [])
        XCTAssertEqual(fixture.contents(.caches), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.leftoverRecording.path))

        // Every saved scene loads: SCN-002 main and backup, SHOW-001 snapshots (SCN-001 decode).
        let registry = try SceneAutosaveFixtures.registry()
        let main = SceneAutosaveStore(directory: fixture.sceneStore.directory).load(registry: registry, assets: nil)
        XCTAssertEqual(main.source, .main)
        XCTAssertEqual(main.document, fixture.secondScene)
        let backupFolder = fixture.container.appendingPathComponent("backup-check", isDirectory: true)
        try FileManager.default.createDirectory(at: backupFolder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture.sceneStore.backup,
                                         to: backupFolder.appendingPathComponent(SceneAutosaveStore.backupName))
        let backup = SceneAutosaveStore(directory: backupFolder).load(registry: registry, assets: nil)
        XCTAssertEqual(backup.source, .backup)
        XCTAssertEqual(backup.document, fixture.firstScene)
        let show = fixture.showStore.load()
        XCTAssertNil(show.refusal)
        XCTAssertEqual(show.unreadableScenes, [])
        XCTAssertEqual(show.list.cues.count, 2)
        for (cue, scene) in zip(show.list.cues, fixture.showScenes) {
            XCTAssertEqual(try fixture.showStore.scene(cue.sceneID).document, scene)
        }
    }

    // FILE-010-T04: the protected folders are the stores' own; only cleanable categories are requested.
    func testProtectedRootsAreTheUserDataFoldersAndTheRequestHoldsOnlyCaches() throws {
        func path(_ url: URL) -> String { url.standardizedFileURL.resolvingSymlinksInPath().path }
        let locations = StorageLocations.standard()
        let protected = locations.protectedRoots.map(path)
        XCTAssertTrue(protected.contains(path(try ShowStore.defaultDirectory())), "the SHOW-001 folder")
        XCTAssertTrue(protected.contains(path(try SceneAutosaveStore.defaultDirectory())))
        XCTAssertTrue(protected.contains(path(try PhotoStore.defaultDirectory())))
        XCTAssertTrue(protected.contains { (p: String) -> Bool in p.hasSuffix("/Library/Preferences") })
        let request = locations.cleanupRequest(inUse: [])
        XCTAssertEqual(Set(request.cacheRoots.keys), StorageCategory.cleanable)
        for (_, roots) in request.cacheRoots {
            for root in roots { XCTAssertFalse(protected.contains(path(URL(fileURLWithPath: root))), root) }
        }
    }

    // FILE-010-R2, R5, R6: Cancel removes nothing; Clear removes and measures again; a clear survives
    // leaving the screen; afterwards only in-use files are left ("nothing to clear").
    func testTheModelConfirmsClearsAndReportsNothingLeft() async throws {
        let fixture = try CleanupFixture()
        defer { fixture.remove() }
        let offered = fixture.offeredRecording.path
        let model = StorageUsageModel(locations: fixture.locations, filesInUse: { () -> Set<String> in [offered] })
        model.refresh()
        _ = try await model.work?.value
        await Task.yield()
        XCTAssertTrue(model.canClearCaches || model.report == nil)

        model.prepareCleanup()
        XCTAssertTrue(model.isPlanningCleanup)
        await model.cleanupWork?.value
        guard case .confirm(let plan) = model.cleanupPrompt else { return XCTFail("a plan to confirm: \(String(describing: model.cleanupPrompt))") }
        XCTAssertEqual(plan.keptInUse, [fixture.offeredRecording.resolvingSymlinksInPath().path])
        XCTAssertTrue(StorageUsageView.confirmationMessage(plan).hasSuffix("settings are kept. Files in use are kept."))
        model.dismissCleanup()   // Cancel
        XCTAssertNil(model.cleanupPrompt)
        XCTAssertEqual(fixture.contents(.recordings), ["leftover.mov", "offered.mov"], "Cancel removes nothing")

        model.prepareCleanup()
        await model.cleanupWork?.value
        guard case .confirm(let again) = model.cleanupPrompt else { return XCTFail("a plan to confirm") }
        model.confirmCleanup(again)
        XCTAssertTrue(model.isClearing)
        XCTAssertFalse(model.canClearCaches)
        model.cancel()   // leaving the screen stops a measurement, not the clear
        await model.cleanupWork?.value
        XCTAssertFalse(model.isClearing)
        XCTAssertEqual(fixture.contents(.recordings), ["offered.mov"])
        XCTAssertEqual(fixture.contents(.caches), [])
        let result = try XCTUnwrap(model.lastCleanup)
        XCTAssertEqual(result.removed.count, 7)
        XCTAssertGreaterThanOrEqual(result.bytesFreed, 6_000)
        let report = try await XCTUnwrap(model.work).value
        XCTAssertEqual(report.usage(.caches).contentBytes, 0)
        XCTAssertEqual(report.usage(.recordings).contentBytes, 2_000)

        model.prepareCleanup()
        await model.cleanupWork?.value
        XCTAssertEqual(model.cleanupPrompt, .nothingToClear(keptInUse: true))
        model.dismissCleanup()
    }

    // FILE-010-R5: the in-use lists of the recording and preset-export coordinators start empty.
    func testIdleCoordinatorsHoldNoFilesInUse() {
        let recording = VideoRecordingCoordinator(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("FILE010-rec-\(UUID().uuidString)", isDirectory: true),
                                                  debugDirectory: nil, checkInterval: nil, storageCheckInterval: nil,
                                                  context: { () -> VideoRecordingCoordinator.Context in
            VideoRecordingCoordinator.Context(source: nil, visualShown: false, outputLive: false, paused: false)
        })
        XCTAssertEqual(recording.filesInUse, [])
    }
}
