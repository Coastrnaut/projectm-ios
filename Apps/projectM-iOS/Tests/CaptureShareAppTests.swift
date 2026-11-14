// CaptureShareAppTests.swift — REC-012-T08: the share-file lifecycle (copy made with the original's
// bytes and descriptive name; completed, cancelled and failed shares delete the copy and keep the
// original; leftovers swept at launch; excluded activities; outcome mapping) and an offered still
// surviving context changes. Simulator results are never device evidence (Constitution X).
import FrameCapture
import UIKit
import XCTest
@testable import projectM_iOS

@MainActor
private final class OneShotSource: FrameCaptureSource {
    var pending: (@MainActor (CapturedPixels?) -> Void)?
    func captureFrame(_ handler: @escaping @MainActor (CapturedPixels?) -> Void) { pending = handler }
    func cancelCapture() { pending = nil }
}

@MainActor
private final class ShareContextBox {
    var value: FrameCaptureCoordinator.Context
    init(_ value: FrameCaptureCoordinator.Context) { self.value = value }
}

@MainActor
final class CaptureShareAppTests: XCTestCase {
    private static let png = CapturedFrame(format: .png, width: 2, height: 1, hasAlpha: false, data: Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]))
    private static let date = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeStore() -> ShareFileStore {
        ShareFileStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("rec012-\(UUID().uuidString)", isDirectory: true))
    }

    /// An "original" recording in its own temporary folder.
    private func makeRecording() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("rec012-rec-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Visualizer Recording 2026-11-13 at 14.05.32.mp4")
        try Data([0, 0, 0, 24, 0x66, 0x74, 0x79, 0x70]).write(to: url)
        return url
    }

    private func waitUntil(_ description: String, timeout: TimeInterval = 10, _ condition: @escaping @MainActor () -> Bool) {
        let done = expectation(description: description)
        var fulfilled = false
        let timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { (_: Timer) in
            MainActor.assumeIsolated {
                if !fulfilled, condition() {
                    fulfilled = true
                    done.fulfill()
                }
            }
        }
        wait(for: [done], timeout: timeout)
        timer.invalidate()
    }

    // MARK: - The acceptance (REC-012-S1, S2)

    /// A cancelled share deletes the copy and its folder; the original still is untouched.
    func testCancelledFrameShareCleansTheCopyAndKeepsTheOriginal() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let share = CaptureShareCoordinator(store: store, simulation: true)
        XCTAssertTrue(share.shareFrame(Self.png, date: Self.date))
        let request = try XCTUnwrap(share.request)
        XCTAssertEqual(request.kind, .frame)
        XCTAssertEqual(request.url.lastPathComponent, CapturedFrameDocument.defaultFilename(for: .png, date: Self.date))
        XCTAssertTrue(request.url.lastPathComponent.hasPrefix("Visualizer Frame ") && request.url.pathExtension == "png")
        XCTAssertEqual(request.url.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL,
                       store.directory.standardizedFileURL, "<Sharing>/<UUID>/<name>")
        XCTAssertEqual(try Data(contentsOf: request.url), Self.png.data, "the copy holds the original's bytes")
        XCTAssertEqual(share.copyCount, 1)
        share.finish(.cancelled)
        XCTAssertNil(share.request)
        XCTAssertFalse(FileManager.default.fileExists(atPath: request.url.deletingLastPathComponent().path), "the copy's folder is gone")
        XCTAssertEqual(store.fileCount(), 0)
        XCTAssertEqual(share.copyCount, 0)
        XCTAssertEqual(share.lastOutcome, .cancelled)
        XCTAssertNil(share.notice, "a cancel adds no notice (REC-012-R15)")
        XCTAssertEqual(Self.png.data, Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3]))
    }

    /// A cancelled recording share deletes the copy and leaves the original file as it was.
    func testCancelledRecordingShareKeepsTheOriginalFile() throws {
        let store = makeStore()
        let original = try makeRecording()
        defer {
            try? FileManager.default.removeItem(at: store.directory)
            try? FileManager.default.removeItem(at: original.deletingLastPathComponent())
        }
        let bytes = try Data(contentsOf: original)
        let share = CaptureShareCoordinator(store: store, simulation: true)
        XCTAssertTrue(share.shareRecording(original))
        let copy = try XCTUnwrap(share.request?.url)
        XCTAssertNotEqual(copy.standardizedFileURL, original.standardizedFileURL, "never the original")
        XCTAssertEqual(copy.lastPathComponent, original.lastPathComponent)
        XCTAssertEqual(try Data(contentsOf: copy), bytes)
        share.finish(.cancelled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path))
        XCTAssertEqual(store.fileCount(), 0)
        XCTAssertEqual(try Data(contentsOf: original), bytes, "the original is retained unchanged (REC-012-R5)")
    }

    /// A completed share deletes the copy, keeps the original and says "Shared.".
    func testCompletedShareCleansTheCopy() throws {
        let store = makeStore()
        let original = try makeRecording()
        defer {
            try? FileManager.default.removeItem(at: store.directory)
            try? FileManager.default.removeItem(at: original.deletingLastPathComponent())
        }
        let share = CaptureShareCoordinator(store: store, simulation: true)
        XCTAssertTrue(share.shareRecording(original))
        XCTAssertEqual(share.request?.kind, .recording)
        share.finish(.completed)
        XCTAssertEqual(store.fileCount(), 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertEqual(share.notice, "Shared.")
        XCTAssertEqual(share.lastOutcome, .completed)
    }

    /// A failed share deletes the copy and says so; the original stays.
    func testFailedShareCleansTheCopyWithANotice() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let share = CaptureShareCoordinator(store: store, simulation: true)
        XCTAssertTrue(share.shareFrame(Self.png, date: Self.date))
        share.finish(.failed)
        XCTAssertEqual(store.fileCount(), 0)
        XCTAssertEqual(share.notice, "The file couldn't be shared.")
    }

    // MARK: - Failures and limits

    /// REC-012-R11: when the copy cannot be made, no sheet is requested and the notice says so.
    func testCopyFailureRequestsNoSheet() throws {
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent("rec012-file-\(UUID().uuidString)")
        try Data([1]).write(to: blocker)   // a file where the sharing folder should be
        defer { try? FileManager.default.removeItem(at: blocker) }
        let share = CaptureShareCoordinator(store: ShareFileStore(directory: blocker), simulation: true)
        XCTAssertFalse(share.shareFrame(Self.png, date: Self.date))
        XCTAssertNil(share.request)
        XCTAssertEqual(share.notice, "The file couldn't be shared.")
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("rec012-missing-\(UUID().uuidString).mp4")
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let other = CaptureShareCoordinator(store: store, simulation: true)
        XCTAssertFalse(other.shareRecording(missing), "a missing original makes no copy")
        XCTAssertEqual(store.fileCount(), 0, "the empty folder is removed too")
    }

    /// One sheet at a time: a second Share… while one is shown makes no copy.
    func testSecondRequestWhileOneIsShownIsRefused() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let share = CaptureShareCoordinator(store: store, simulation: true)
        XCTAssertTrue(share.shareFrame(Self.png, date: Self.date))
        let first = share.request
        XCTAssertFalse(share.shareFrame(Self.png, date: Self.date))
        XCTAssertEqual(share.request, first)
        XCTAssertEqual(store.fileCount(), 1)
        share.finish(.completed)
        XCTAssertTrue(share.shareFrame(Self.png, date: Self.date), "a new share after the sheet closed")
        XCTAssertNotEqual(share.request?.id, first?.id)
        share.finish(.cancelled)
        XCTAssertEqual(store.fileCount(), 0)
    }

    /// REC-012-R6, S3: copies left by an earlier run are deleted when the coordinator is created.
    func testLeftoversAreSweptAtLaunch() throws {
        let store = makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let folder = store.directory.appendingPathComponent("old", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data([1, 2]).write(to: folder.appendingPathComponent("Visualizer Frame old.png"))
        try Data([3]).write(to: store.directory.appendingPathComponent("stray.mp4"))
        XCTAssertEqual(store.fileCount(), 2)
        let share = CaptureShareCoordinator(store: store, simulation: false)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.directory.path), [])
        XCTAssertEqual(share.copyCount, 0)
    }

    /// REC-012-R7, S4: Save to Photos and Assign to Contact are excluded; the app declares no full Photos
    /// library or Contacts usage string. REC-011-R11 (ADR-0059): the sheet still excludes Save to Photos; the
    /// add-only key exists for the app's own Save to Photos button.
    func testExcludedActivitiesAndNoPhotosPermission() {
        XCTAssertEqual(ShareFileStore.excludedActivityTypes, [.saveToCameraRoll, .assignToContact])
        let info = Bundle.main.infoDictionary ?? [:]
        for key in ["NSPhotoLibraryUsageDescription", "NSContactsUsageDescription"] {
            XCTAssertNil(info[key], key)
        }
        XCTAssertNotNil(info["NSPhotoLibraryAddUsageDescription"])
        XCTAssertEqual(ShareFileStore.defaultDirectory.lastPathComponent, "Sharing")
    }

    func testOutcomeMapping() {
        XCTAssertEqual(ShareOutcome.from(completed: true, error: nil), .completed)
        XCTAssertEqual(ShareOutcome.from(completed: false, error: nil), .cancelled)
        XCTAssertEqual(ShareOutcome.from(completed: false, error: CocoaError(.fileWriteUnknown)), .failed)
        XCTAssertEqual(ShareOutcome.from(completed: true, error: CocoaError(.fileWriteUnknown)), .failed)
        XCTAssertEqual(ShareOutcome.completed.notice, "Shared.")
        XCTAssertNil(ShareOutcome.cancelled.notice)
    }

    // MARK: - The offered still (REC-012-R16)

    /// An offered still stays offered and savable through pause, blackout and a visual change.
    func testOfferedStillSurvivesContextChanges() {
        let source = OneShotSource()
        let context = ShareContextBox(FrameCaptureCoordinator.Context(source: source, outputLive: true, paused: false))
        let capture = FrameCaptureCoordinator(debugDirectory: nil, formats: [.png]) { context.value }
        capture.save(.png)
        let pixels = CapturedPixels(width: 2, height: 1, layout: .sRGBBGRA8TopDown([0, 0, 255, 0, 255, 0, 0, 0]))!
        source.pending?(pixels)
        waitUntil("offered") { capture.offered != nil }
        context.value.paused = true
        context.value.outputLive = false
        context.value.source = nil
        XCTAssertEqual(capture.offered?.summary, "png 2x1 opaque")
        capture.requestExport()
        XCTAssertTrue(capture.showExporter, "Save… still works while paused and blacked out")
        capture.exportDismissed()
        XCTAssertNotNil(capture.offered)
    }
}
