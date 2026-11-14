// PhotoStoreTests.swift — MED-001-T14, T16, T18: the stored photo (MED-001-R3, R6 to R8, R11, R14;
// S2, S4, S5). Each test uses its own temporary folder and UserDefaults suite; fixtures are made with
// ImageIO here. "Relaunch" is a new store (and coordinator) on the same folder and defaults.
import CoreGraphics
import Foundation
import ImageIO
import ImageLayer
import UniformTypeIdentifiers
import LocalPortability
import XCTest
@testable import projectM_iOS

@MainActor
final class PhotoStoreTests: XCTestCase {
    private struct Sandbox {
        let root: URL
        let photos: URL
        let defaults: UserDefaults
        let suite: String

        func store() -> PhotoStore { PhotoStore(directory: photos, defaults: defaults) }

        func cleanUp() {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suite)
        }
    }

    private func makeSandbox() throws -> Sandbox {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PhotoStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suite = "PhotoStoreTests.\(UUID().uuidString)"
        return Sandbox(root: root, photos: root.appendingPathComponent("Photos"), defaults: try XCTUnwrap(UserDefaults(suiteName: suite)),
                       suite: suite)
    }

    /// A `width` × `height` solid picture written as `type` outside the store's folder (a "picked" file).
    private func pickedFile(in sandbox: Sandbox, width: Int = 64, height: Int = 48, type: UTType = .png,
                            name: String = "picked") throws -> URL {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) { bytes[i * 4] = 230; bytes[i * 4 + 1] = 120; bytes[i * 4 + 2] = 30; bytes[i * 4 + 3] = 255 }
        let image = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                          space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                                          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                                          provider: try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData)), decode: nil,
                                          shouldInterpolate: false, intent: .defaultIntent))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data as CFMutableData, type.identifier as CFString, 1, nil))
        let gps: [CFString: Any] = [kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 51.5, kCGImagePropertyGPSLatitudeRef: "N"]]
        CGImageDestinationAddImage(destination, image, gps as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let url = sandbox.root.appendingPathComponent("\(name).\(type.preferredFilenameExtension ?? "img")")
        try (data as Data).write(to: url)
        return url
    }

    /// Stored files (FILE-008: the reference registry is not a copy).
    private func files(in folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { (name: String) -> Bool in name != ContentAddressedMediaFolder.registryName }.sorted()
    }

    // MARK: - Import and relaunch (T14; R3, R6, R8, R14; S2)

    func testImportCopiesIntoTheFolderAndARelaunchResolvesTheSameFile() throws {
        let sandbox = try makeSandbox()
        defer { sandbox.cleanUp() }
        let source = try pickedFile(in: sandbox, type: .jpeg)
        let sourceBytes = try Data(contentsOf: source)
        let stored = try sandbox.store().importImage(at: source)
        XCTAssertEqual(stored.url.deletingLastPathComponent().standardizedFileURL, sandbox.photos.standardizedFileURL, "inside the folder")
        XCTAssertEqual(stored.url.lastPathComponent, try MediaContentHash.digest(ofFileAt: stored.url).sha256 + ".jpg",
                       "FILE-008: the copy is named by its content")
        XCTAssertEqual(sandbox.defaults.string(forKey: AppSettings.photoIDKey), stored.id.uuidString, "the identifier is a setting")
        XCTAssertEqual(try Data(contentsOf: source), sourceBytes, "the picked file is untouched")
        let props = CGImageSourceCopyPropertiesAtIndex(try XCTUnwrap(CGImageSourceCreateWithURL(stored.url as CFURL, nil)), 0, nil)
            as? [CFString: Any] ?? [:]
        XCTAssertNil(props[kCGImagePropertyGPSDictionary], "the copy has no location")

        XCTAssertEqual(sandbox.store().current(), stored, "a relaunch resolves the same file")
        let relaunched = PhotoCoordinator(store: sandbox.store(), announce: { _ in })
        XCTAssertEqual(relaunched.photo, stored)
        XCTAssertEqual(AppCoordinator.photoContent(relaunched.photo), .file(stored.url), "and the layer shows it")
    }

    func testASecondImportReplacesTheFirst() throws {
        let sandbox = try makeSandbox()
        defer { sandbox.cleanUp() }
        let store = sandbox.store()
        let first = try store.importImage(at: try pickedFile(in: sandbox, name: "a"))
        let second = try store.importImage(at: try pickedFile(in: sandbox, width: 32, height: 32, name: "b"))
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.url.path), "the previous copy is deleted")
        XCTAssertEqual(files(in: sandbox.photos), [second.url.lastPathComponent], "one photo at a time")
        XCTAssertEqual(store.current(), second)
    }

    func testInvalidOrMissingIdentifiersReadAsNoPhotoAndAreCleared() throws {
        let sandbox = try makeSandbox()
        defer { sandbox.cleanUp() }
        let store = sandbox.store()
        // A file outside the folder that a crafted identifier might try to reach.
        let outside = sandbox.root.appendingPathComponent("secret.png")
        try Data("x".utf8).write(to: outside)
        for raw in ["../secret", "../secret.png", "not-a-uuid", UUID().uuidString.lowercased(), UUID().uuidString] {
            sandbox.defaults.set(raw, forKey: AppSettings.photoIDKey)
            XCTAssertNil(store.current(), "\(raw) is no photo")
            XCTAssertNil(sandbox.defaults.string(forKey: AppSettings.photoIDKey), "and is cleared")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path), "nothing outside the folder is touched")
        let stored = try store.importImage(at: try pickedFile(in: sandbox))
        try FileManager.default.removeItem(at: stored.url)
        XCTAssertNil(store.current(), "a missing copy reads as no photo")
    }

    // MARK: - Remove (T16; R7; S4)

    func testRemoveDeletesTheCopyAndTheIdentifier() async throws {
        let sandbox = try makeSandbox()
        defer { sandbox.cleanUp() }
        let coordinator = PhotoCoordinator(store: sandbox.store(), announce: { _ in })
        var shown: [StoredPhoto?] = []
        coordinator.onPhotoChange = { shown.append($0) }
        await coordinator.importImage(at: try pickedFile(in: sandbox), deleteAfterwards: false)
        let stored = try XCTUnwrap(coordinator.photo)
        XCTAssertEqual(shown, [stored], "the layer is told")
        coordinator.remove()
        XCTAssertNil(coordinator.photo)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stored.url.path), "the copy is deleted")
        XCTAssertNil(sandbox.defaults.string(forKey: AppSettings.photoIDKey))
        XCTAssertEqual(files(in: sandbox.photos), [])
        XCTAssertEqual(shown.last, .some(nil), "the layer shows nothing")
        XCTAssertNil(sandbox.store().current(), "a relaunch shows no photo")
        XCTAssertEqual(coordinator.summary, "No photo")
    }

    // MARK: - Refusals (T18; R6, R11; S5)

    func testARefusedImportShowsTheNoticeAndKeepsTheStoredPhoto() async throws {
        let sandbox = try makeSandbox()
        defer { sandbox.cleanUp() }
        var announced: [String] = []
        let coordinator = PhotoCoordinator(store: sandbox.store(), announce: { announced.append($0) })
        await coordinator.importImage(at: try pickedFile(in: sandbox), deleteAfterwards: false)
        let kept = try XCTUnwrap(coordinator.photo)

        let jpeg = try Data(contentsOf: try pickedFile(in: sandbox, type: .jpeg, name: "whole"))
        let corrupt = sandbox.root.appendingPathComponent("corrupt.jpg")
        try jpeg.prefix(jpeg.count / 2).write(to: corrupt)
        await coordinator.importImage(at: corrupt, deleteAfterwards: false)
        XCTAssertEqual(coordinator.notice, ImageImportError.damaged.message, "the notice names the reason")
        XCTAssertEqual(announced.last, ImageImportError.damaged.message, "and VoiceOver hears it")
        XCTAssertEqual(coordinator.photo, kept, "the stored photo is unchanged")
        XCTAssertEqual(sandbox.store().current(), kept)

        let text = sandbox.root.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: text)
        await coordinator.importImage(at: text, deleteAfterwards: false)
        XCTAssertEqual(coordinator.notice, ImageImportError.notAnImage.message)
        await coordinator.importImage(at: sandbox.root.appendingPathComponent("gone.png"), deleteAfterwards: false)
        XCTAssertEqual(coordinator.notice, ImageImportError.unreadable.message)
        XCTAssertEqual(files(in: sandbox.photos), [kept.url.lastPathComponent], "no partial copies are left")
        coordinator.clearNotice()
        XCTAssertNil(coordinator.notice, "Dismiss clears it")
    }

    func testCancellingThePickerChangesNothing() async throws {
        let sandbox = try makeSandbox()
        defer { sandbox.cleanUp() }
        let coordinator = PhotoCoordinator(store: sandbox.store(), announce: { _ in })
        await coordinator.filePicked(.failure(CocoaError(.userCancelled)))
        XCTAssertNil(coordinator.notice)
        XCTAssertNil(coordinator.photo)
    }

    func testPhotoIsAPersistedChoice() throws {
        let sandbox = try makeSandbox()
        defer { sandbox.cleanUp() }
        XCTAssertEqual(VisualChoice.photo.title, "Photo")
        XCTAssertFalse(VisualChoice.photo.isNative)
        XCTAssertFalse(VisualChoice.photo.usesCamera)
        XCTAssertTrue(VisualChoice.photo.replacesProjectM)
        let settings = AppSettings(defaults: sandbox.defaults, systemReduceMotion: false)
        settings.visual = .photo
        XCTAssertEqual(AppSettings(defaults: sandbox.defaults, systemReduceMotion: false).visual, .photo, "restored after a relaunch (R8)")
        XCTAssertTrue(AppSettings.allKeys.contains(AppSettings.photoIDKey), "the UI-test reset clears it")
        XCTAssertEqual(PhotoVisualHost.accessibilityValue(.ready(width: 64, height: 48)), "Photo 64 × 48")
        XCTAssertEqual(PhotoVisualHost.accessibilityValue(.empty), "No photo")
    }
}
