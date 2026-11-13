// VideoStoreTests.swift — MED-002-T20, T22: the stored video (MED-002-R3, R6 to R8, R14, R18; S4, S6,
// S7). Each test uses its own temporary folder and UserDefaults suite; the picked file is the DEBUG
// fixture writer's 64 × 48, 30 fps, 2 s movie. "Relaunch" is a new store on the same folder and
// defaults.
import AVFoundation
import Foundation
import VideoLayer
import XCTest
@testable import projectM_iOS

@MainActor
final class VideoStoreTests: XCTestCase {
    private struct Sandbox {
        let root: URL
        let videos: URL
        let defaults: UserDefaults
        let suite: String

        func store(limits: VideoImportLimits = .standard) -> VideoStore { VideoStore(directory: videos, defaults: defaults, limits: limits) }

        func cleanUp() {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suite)
        }
    }

    private func makeSandbox() throws -> Sandbox {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VideoStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "VideoStoreTests.\(UUID().uuidString)"
        return Sandbox(root: root, videos: root.appendingPathComponent("Videos"), defaults: try XCTUnwrap(UserDefaults(suiteName: suite)),
                       suite: suite)
    }

    /// A "picked" movie outside the store's folder.
    private func pickedFile(in sandbox: Sandbox, name: String = "picked") async throws -> URL {
        let url = sandbox.root.appendingPathComponent("\(name).mov")
        try await Task.detached { try UITestVideoFixture.writeCounter(to: url) }.value
        return url
    }

    private func files(in folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    // MARK: - Import and relaunch (R3, R6, R8, R18; S4)

    func testImportCopiesIntoTheFolderAndARelaunchResolvesTheSameFile() async throws {
        let sandbox = try makeSandbox()
        defer { sandbox.cleanUp() }
        let picked = try await pickedFile(in: sandbox)
        let stored = try await sandbox.store().importVideo(at: picked)
        XCTAssertEqual(stored.url.deletingLastPathComponent().standardizedFileURL, sandbox.videos.standardizedFileURL)
        XCTAssertEqual(stored.url.lastPathComponent, "\(stored.id.uuidString).mov")
        XCTAssertEqual(sandbox.defaults.string(forKey: AppSettings.videoIDKey), stored.id.uuidString)
        XCTAssertTrue(FileManager.default.fileExists(atPath: picked.path), "the picked original is untouched")
        XCTAssertEqual(files(in: sandbox.videos), [stored.url.lastPathComponent], "one copy, nothing else")
        let audio = try await AVURLAsset(url: stored.url).loadTracks(withMediaType: .audio)
        XCTAssertTrue(audio.isEmpty)
        XCTAssertEqual(sandbox.store().current(), stored, "a relaunch resolves the same copy")
    }

    func testASecondImportReplacesTheFirst() async throws {
        let sandbox = try makeSandbox()
        defer { sandbox.cleanUp() }
        let first = try await sandbox.store().importVideo(at: try await pickedFile(in: sandbox, name: "a"))
        let second = try await sandbox.store().importVideo(at: try await pickedFile(in: sandbox, name: "b"))
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.url.path), "the previous copy is deleted after the new one is saved")
        XCTAssertEqual(files(in: sandbox.videos), [second.url.lastPathComponent])
    }

    func testInvalidOrMissingIdentifiersReadAsNoVideoAndAreCleared() async throws {
        let sandbox = try makeSandbox()
        defer { sandbox.cleanUp() }
        let store = sandbox.store()
        let outside = sandbox.root.appendingPathComponent("secret.mov")
        try Data("x".utf8).write(to: outside)
        for raw in ["../secret", "../secret.mov", "not-a-uuid", UUID().uuidString.lowercased(), UUID().uuidString] {
            sandbox.defaults.set(raw, forKey: AppSettings.videoIDKey)
            XCTAssertNil(store.current(), "\(raw) is no video")
            XCTAssertNil(sandbox.defaults.string(forKey: AppSettings.videoIDKey), "and is cleared")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path), "nothing outside the folder is touched")
        let stored = try await store.importVideo(at: try await pickedFile(in: sandbox))
        try FileManager.default.removeItem(at: stored.url)
        XCTAssertNil(store.current(), "a missing copy reads as no video")
    }

    // MARK: - Remove (R7; S6)

    func testRemoveDeletesTheCopyAndTheIdentifier() async throws {
        let sandbox = try makeSandbox()
        defer { sandbox.cleanUp() }
        let coordinator = VideoCoordinator(store: sandbox.store(), announce: { _ in })
        var shown: [StoredVideo?] = []
        coordinator.onVideoChange = { shown.append($0) }
        await coordinator.importVideo(at: try await pickedFile(in: sandbox), deleteAfterwards: false)
        let stored = try XCTUnwrap(coordinator.video)
        XCTAssertEqual(shown, [stored], "the layer is told")
        XCTAssertEqual(coordinator.summary, "Loading…")
        coordinator.playingSize = (64, 48)
        XCTAssertEqual(coordinator.summary, "64 × 48")
        coordinator.remove()
        XCTAssertNil(coordinator.video)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stored.url.path), "the copy is deleted")
        XCTAssertNil(sandbox.defaults.string(forKey: AppSettings.videoIDKey))
        XCTAssertEqual(files(in: sandbox.videos), [])
        XCTAssertEqual(shown.last, .some(nil), "the layer shows nothing")
        XCTAssertNil(sandbox.store().current(), "a relaunch shows no video")
        XCTAssertEqual(coordinator.summary, "No video")
    }

    // MARK: - Refusals (R5, R6, R14; S7)

    func testARefusedImportShowsTheNoticeAndKeepsTheStoredVideo() async throws {
        let sandbox = try makeSandbox()
        defer { sandbox.cleanUp() }
        var announced: [String] = []
        let coordinator = VideoCoordinator(store: sandbox.store(), announce: { announced.append($0) })
        await coordinator.importVideo(at: try await pickedFile(in: sandbox), deleteAfterwards: false)
        let kept = try XCTUnwrap(coordinator.video)

        // Pictures scrambled, index intact: "couldn't be read".
        var data = try Data(contentsOf: try await pickedFile(in: sandbox, name: "whole"))
        let start = try XCTUnwrap(data.range(of: Data("mdat".utf8))).upperBound
        for i in start..<min(start + 6000, data.count / 2) { data[i] = UInt8(truncatingIfNeeded: i &* 131) }
        let corrupt = sandbox.root.appendingPathComponent("corrupt.mov")
        try data.write(to: corrupt)
        await coordinator.importVideo(at: corrupt, deleteAfterwards: false)
        XCTAssertEqual(coordinator.notice, VideoImportError.damaged.message, "the notice names the reason")
        XCTAssertEqual(announced.last, VideoImportError.damaged.message, "and VoiceOver hears it")
        XCTAssertEqual(coordinator.video, kept, "the stored video is unchanged")
        XCTAssertEqual(sandbox.store().current(), kept)

        let text = sandbox.root.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: text)
        await coordinator.importVideo(at: text, deleteAfterwards: false)
        XCTAssertEqual(coordinator.notice, VideoImportError.notAVideo.message)
        await coordinator.importVideo(at: sandbox.root.appendingPathComponent("gone.mov"), deleteAfterwards: false)
        XCTAssertEqual(coordinator.notice, VideoImportError.unreadable.message)
        XCTAssertEqual(files(in: sandbox.videos), [kept.url.lastPathComponent], "no partial copies are left")
        coordinator.clearNotice()
        XCTAssertNil(coordinator.notice, "Dismiss clears it")
    }

    func testAFileOverTheSizeLimitIsRefusedBeforeItIsCopied() async throws {
        let sandbox = try makeSandbox()
        defer { sandbox.cleanUp() }
        let small = VideoImportLimits(maxFileBytes: 1000, maxLongestSide: 4096, maxFrameRate: 60.5)
        let picked = try await pickedFile(in: sandbox)
        do throws(VideoImportError) {
            _ = try await sandbox.store(limits: small).importVideo(at: picked)
            XCTFail("refused")
        } catch {
            XCTAssertEqual(error, .tooLarge)
        }
        XCTAssertEqual(files(in: sandbox.videos), [])
        XCTAssertNil(sandbox.defaults.string(forKey: AppSettings.videoIDKey))
    }

    func testCancellingThePickerChangesNothing() async throws {
        let sandbox = try makeSandbox()
        defer { sandbox.cleanUp() }
        let coordinator = VideoCoordinator(store: sandbox.store(), announce: { _ in })
        await coordinator.filePicked(.failure(CocoaError(.userCancelled)))
        XCTAssertNil(coordinator.notice)
        XCTAssertNil(coordinator.video)
    }

    func testVideoIsAPersistedChoice() throws {
        let sandbox = try makeSandbox()
        defer { sandbox.cleanUp() }
        XCTAssertEqual(VisualChoice.video.title, "Video")
        XCTAssertFalse(VisualChoice.video.isNative)
        XCTAssertFalse(VisualChoice.video.usesCamera)
        XCTAssertFalse(VisualChoice.video.usesPhoto)
        XCTAssertTrue(VisualChoice.video.usesVideo)
        XCTAssertTrue(VisualChoice.video.replacesProjectM)
        let settings = AppSettings(defaults: sandbox.defaults, systemReduceMotion: false)
        settings.visual = .video
        XCTAssertEqual(AppSettings(defaults: sandbox.defaults, systemReduceMotion: false).visual, .video, "restored after a relaunch (R8)")
        XCTAssertTrue(AppSettings.allKeys.contains(AppSettings.videoIDKey), "the UI-test reset clears it")
        XCTAssertEqual(VideoVisualHost.accessibilityValue(.playing(width: 64, height: 48)), "Video 64 × 48")
        XCTAssertEqual(VideoVisualHost.accessibilityValue(.empty), "No video")
        XCTAssertEqual(VideoVisualHost.accessibilityValue(.failed(.damaged)), "Couldn't play the video")
    }
}
