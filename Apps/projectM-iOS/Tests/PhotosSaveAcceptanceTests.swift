// PhotosSaveAcceptanceTests.swift — REC-011-T10, T11, T14: the roadmap acceptance "Permission denial leaves local
// original intact and shows error" (REC-011-S1) with injected access and saver: denied, restricted and a failed save
// each leave the offered recording byte-identical, still offered and at its path, and present the error; granted
// saves exactly once (S2); not-determined requests once; no access call happens without the user's tap (S3).
// The recording is REC-010's generated 64×64 H.264 fixture; no clock, no Photos library.
import FrameCapture
import Foundation
import Photos
import XCTest
@testable import projectM_iOS

@MainActor
final class PhotosSaveAcceptanceTests: XCTestCase {
    /// Counts every call; answers `state` (and `answer` to a request).
    private final class FakeAccess: PhotosAccessProviding {
        var state: PhotosAccess
        var answer: PhotosAccess
        var statusCalls = 0
        var requestCalls = 0

        init(_ state: PhotosAccess, answer: PhotosAccess? = nil) {
            self.state = state
            self.answer = answer ?? state
        }

        func status() -> PhotosAccess {
            statusCalls += 1
            return state
        }

        func request() async -> PhotosAccess {
            requestCalls += 1
            state = answer
            return answer
        }
    }

    /// Records each item; throws when `failing`.
    private final class FakeSaver: PhotosSaving {
        var failing = false
        var saved: [PhotosSaveItem] = []
        /// While set, `save` waits until `release()` (the double-tap test).
        var gate: CheckedContinuation<Void, Never>?
        var holds = false

        func save(_ item: PhotosSaveItem) async throws {
            saved.append(item)
            if holds { await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in gate = c } }
            if failing { throw CocoaError(.fileWriteUnknown) }
        }

        func release() {
            gate?.resume()
            gate = nil
        }
    }

    private struct Offered {
        let recording: VideoRecordingCoordinator
        let url: URL
        let bytes: Data
        let store: RecordingLibraryStore
    }

    /// A finished recording offered by REC-003's coordinator in a temporary container.
    private func offeredRecording(_ label: String) throws -> Offered {
        let container = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotosSaveTests-\(label)-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: container) }
        let temp = container.appendingPathComponent("tmp/Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        let store = RecordingLibraryStore(directory: container.appendingPathComponent("RecordingLibrary", isDirectory: true))
        let recording = VideoRecordingCoordinator(directory: temp, debugDirectory: nil, checkInterval: nil, storageCheckInterval: nil,
                                                  library: store) { () -> VideoRecordingCoordinator.Context in
            VideoRecordingCoordinator.Context(source: nil, visualShown: false, outputLive: false, paused: false)
        }
        let url = temp.appendingPathComponent("Visualizer Recording 1.mp4")
        try FileManager.default.copyItem(at: RecordingLibraryFixture.template(), to: url)   // after the init's sweep
        recording.offerForTests(url)
        return Offered(recording: recording, url: url, bytes: try Data(contentsOf: url), store: store)
    }

    private func assertOriginalIntact(_ o: Offered, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(o.recording.offered, o.url, "still offered", file: file, line: line)
        XCTAssertEqual(try Data(contentsOf: o.url), o.bytes, "byte-identical at its path", file: file, line: line)
        XCTAssertEqual(o.store.scan().count, 0, "nothing moved into the library", file: file, line: line)
    }

    private static let frame = CapturedFrame(format: .png, width: 2, height: 2, hasAlpha: false, data: Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]))

    // MARK: - REC-011-S1: the roadmap acceptance

    func testDenialLeavesTheOriginalIntactAndShowsTheError() async throws {
        let o = try offeredRecording("denied")
        let access = FakeAccess(.denied)
        let saver = FakeSaver()
        let photos = PhotosSaveCoordinator(access: access, saver: saver)
        XCTAssertTrue(photos.save(.recording(o.url)))
        await photos.waitForSave()
        XCTAssertEqual(photos.lastOutcome, .denied)
        XCTAssertEqual(photos.notice, "Photos access is off. To save to Photos, allow adding photos for projectM in Settings. The file is still in the app.")
        XCTAssertTrue(photos.noticeOffersSettings, "Open Settings")
        XCTAssertTrue(saver.saved.isEmpty, "nothing is added")
        XCTAssertEqual(access.requestCalls, 0, "iOS already answered; no new request")
        XCTAssertNil(photos.saving)
        try assertOriginalIntact(o)
    }

    func testRestrictedAndFailedSavesLeaveTheOriginalIntactAndShowTheError() async throws {
        let o = try offeredRecording("restricted")
        let restricted = PhotosSaveCoordinator(access: FakeAccess(.restricted), saver: FakeSaver())
        restricted.save(.recording(o.url))
        await restricted.waitForSave()
        XCTAssertEqual(restricted.lastOutcome, .restricted)
        XCTAssertEqual(restricted.notice, "Saving to Photos is restricted on this device. The file is still in the app.")
        XCTAssertTrue(restricted.noticeOffersSettings)
        try assertOriginalIntact(o)

        let saver = FakeSaver()
        saver.failing = true
        let failing = PhotosSaveCoordinator(access: FakeAccess(.granted), saver: saver)
        failing.save(.recording(o.url))
        await failing.waitForSave()
        XCTAssertEqual(failing.lastOutcome, .failed)
        XCTAssertEqual(failing.notice, "The file couldn't be saved to Photos. It is still in the app.")
        XCTAssertFalse(failing.noticeOffersSettings)
        XCTAssertEqual(saver.saved, [.recording(o.url)], "one attempt")
        XCTAssertEqual(failing.savedCount, 0)
        try assertOriginalIntact(o)
    }

    /// iOS asks (not determined) and the user declines: denied, original intact.
    func testDeclinedPromptLeavesTheOriginalIntact() async throws {
        let o = try offeredRecording("declined")
        let access = FakeAccess(.notDetermined, answer: .denied)
        let saver = FakeSaver()
        let photos = PhotosSaveCoordinator(access: access, saver: saver)
        photos.save(.recording(o.url))
        await photos.waitForSave()
        XCTAssertEqual(access.requestCalls, 1)
        XCTAssertEqual(photos.lastOutcome, .denied)
        XCTAssertTrue(saver.saved.isEmpty)
        try assertOriginalIntact(o)
    }

    // MARK: - REC-011-S2: granted saves exactly once

    func testGrantedSavesExactlyOnceAndKeepsTheOffers() async throws {
        let o = try offeredRecording("granted")
        let access = FakeAccess(.notDetermined, answer: .granted)
        let saver = FakeSaver()
        let photos = PhotosSaveCoordinator(access: access, saver: saver)
        photos.save(.recording(o.url))
        await photos.waitForSave()
        XCTAssertEqual(access.requestCalls, 1, "asked once, inside the tap")
        XCTAssertEqual(saver.saved, [.recording(o.url)], "exactly one save, from the file itself")
        XCTAssertEqual(photos.lastOutcome, .saved)
        XCTAssertEqual(photos.notice, "Saved to Photos.")
        XCTAssertFalse(photos.noticeOffersSettings)
        XCTAssertEqual(photos.savedCount, 1)
        try assertOriginalIntact(o)

        // A frame: its encoded bytes under the name its file would get; access is not requested again.
        let date = Date(timeIntervalSince1970: 1_794_000_000)
        photos.save(CaptureResultPanels.photosItem(frame: Self.frame, date: date))
        await photos.waitForSave()
        XCTAssertEqual(access.requestCalls, 1)
        XCTAssertEqual(saver.saved.count, 2)
        XCTAssertEqual(saver.saved.last, .frame(data: Self.frame.data, format: .png,
                                                name: CapturedFrameDocument.defaultFilename(for: .png, date: date)))
    }

    /// A second tap while a save runs is ignored; the item's key is busy until the save ends (REC-011-R10).
    func testASecondTapWhileSavingIsIgnored() async throws {
        let o = try offeredRecording("double")
        let saver = FakeSaver()
        saver.holds = true
        let photos = PhotosSaveCoordinator(access: FakeAccess(.granted), saver: saver)
        XCTAssertTrue(photos.save(.recording(o.url)))
        XCTAssertTrue(photos.isSaving(PhotosSaveItem.key(for: o.url)))
        XCTAssertFalse(photos.isSaving(.frame))
        XCTAssertFalse(photos.save(.recording(o.url)), "ignored while saving")
        while saver.gate == nil { await Task.yield() }
        saver.release()
        await photos.waitForSave()
        XCTAssertEqual(saver.saved.count, 1)
        XCTAssertFalse(photos.isSaving)
    }

    func testStatusMapping() {
        XCTAssertEqual(PhotosAccess.from(.notDetermined), .notDetermined)
        XCTAssertEqual(PhotosAccess.from(.authorized), .granted)
        XCTAssertEqual(PhotosAccess.from(.limited), .granted)
        XCTAssertEqual(PhotosAccess.from(.denied), .denied)
        XCTAssertEqual(PhotosAccess.from(.restricted), .restricted)
        XCTAssertEqual(PhotosAccess.allCases.map(\.permissionState), [.notDetermined, .granted, .denied, .restricted])
    }

    // MARK: - REC-011-S3: no access call without the user's tap

    func testNoAccessCallAtCreationOfferKeepOrLibraryRefresh() async throws {
        let access = FakeAccess(.notDetermined)
        let photos = PhotosSaveCoordinator(access: access, saver: FakeSaver())
        let o = try offeredRecording("quiet")   // a recording finished and offered
        let model = RecordingLibraryModel(store: o.store)
        model.photos = photos
        _ = try XCTUnwrap(o.recording.keepOffered())   // Keep
        model.refresh()                                 // opening Recordings
        await model.waitForLoads()
        XCTAssertEqual(model.count, 1)
        XCTAssertNil(photos.notice)
        XCTAssertEqual(access.statusCalls, 0)
        XCTAssertEqual(access.requestCalls, 0)
    }

    /// The real Photos API is used in one file only, so no other code path can query or request access.
    func testPhotosLibraryIsUsedOnlyByTheCoordinator() throws {
        let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let app = tests.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: app.appendingPathComponent("Coordinators").path) else {
            throw XCTSkip("sources not reachable from this test bundle")
        }
        var users: [String] = []
        let files = FileManager.default.enumerator(at: app, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift", !url.path.contains("/Tests/") else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            if text.contains("PHPhotoLibrary") || text.contains("PHAssetCreationRequest") { users.append(url.lastPathComponent) }
        }
        XCTAssertEqual(users, ["PhotosSaveCoordinator.swift"])
    }
}
