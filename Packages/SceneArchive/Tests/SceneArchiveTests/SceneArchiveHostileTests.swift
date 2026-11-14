// SceneArchiveHostileTests.swift — FILE-001-T13: every hostile or damaged archive is refused with
// its exact reason (FILE-001-R6 to R9, R14; S2 at the package level). Nothing is written by the
// reader, so "no store change" is the app test's part (SceneArchiveServiceTests).
import Foundation
import GeneratorGraphImport
import LocalPortability
@testable import SceneArchive
import SceneFormat
import XCTest

final class SceneArchiveHostileTests: XCTestCase {
    private let small = SceneArchiveLimits(maxArchiveBytes: 1 << 22, maxManifestBytes: 4_096, maxPhotoBytes: 200, maxVideoBytes: 2_000)

    private func assertRefused(_ data: Data, _ expected: SceneArchiveError, limits: SceneArchiveLimits = .standard,
                               file: StaticString = #filePath, line: UInt = #line) throws {
        let registry = try ArchiveFixtures.registry()
        XCTAssertThrowsError(try SceneArchiveReader.read(data, registry: registry, limits: limits), file: file, line: line) { (error: Error) in
            XCTAssertEqual(error as? SceneArchiveError, expected, file: file, line: line)
            XCTAssertFalse((error as? SceneArchiveError)?.message.isEmpty ?? true, file: file, line: line)
        }
    }

    private var records: [SceneArchiveAssetRecord] { [ArchiveFixtures.videoRecord, ArchiveFixtures.photoRecord] }

    private func standard(plus extra: [(String, Data)] = [], unlisted: Set<String> = []) throws -> Data {
        try ArchiveFixtures.handBuilt(files: try ArchiveFixtures.standardFiles() + extra, records: records, unlisted: unlisted)
    }

    /// The plain scene (no media) plus `extra` files: room for two more entries under the limit.
    private func plain(plus extra: [(String, Data)], unlisted: Set<String> = []) throws -> Data {
        try ArchiveFixtures.handBuilt(files: [("scene.json", ArchiveFixtures.sceneBytes(ArchiveFixtures.plainScene()))] + extra,
                                      records: [], unlisted: unlisted)
    }

    private func replacing(_ path: String, with data: Data) throws -> [(String, Data)] {
        try ArchiveFixtures.standardFiles().map { (entry: (String, Data)) -> (String, Data) in entry.0 == path ? (path, data) : entry }
    }

    func testTheHandBuiltControlIsAccepted() throws {
        XCTAssertEqual(try SceneArchiveReader.read(try standard(), registry: try ArchiveFixtures.registry()).media.count, 2)
    }

    // MARK: ZIP layer (PRE-014 reader)

    func testPathTraversalAbsolutePathDuplicateAndSymlinkEntriesAreRefused() throws {
        let traversal = ArchiveFixtures.patch(try plain(plus: [("ab/cd", Data("x".utf8))], unlisted: ["ab/cd"]), "ab/cd", "../cd")
        try assertRefused(traversal, .archive(.zip(.unsafePath("../cd"))))
        let absolute = ArchiveFixtures.patch(try plain(plus: [("xetcp", Data("x".utf8))], unlisted: ["xetcp"]), "xetcp", "/etcp")
        try assertRefused(absolute, .archive(.zip(.unsafePath("/etcp"))))
        let duplicate = ArchiveFixtures.patch(try plain(plus: [("dupa", Data("x".utf8)), ("dupb", Data("y".utf8))], unlisted: ["dupa", "dupb"]),
                                              "dupb", "DUPA")
        try assertRefused(duplicate, .archive(.zip(.duplicatePath("DUPA"))))
        var link = try standard()
        let central = ZipHeaders.centralHeaders(link)[1]
        ZipHeaders.set32(&link, central + 38, 0o120777 << 16)
        try assertRefused(link, .archive(.zip(.unsupported("symbolic links or special files"))))
    }

    func testTooManyEntriesAndOversizedEntriesAreRefused() throws {
        // MED-010: up to 4 files (scene, photo, video, logo) plus the manifest.
        try assertRefused(try standard(plus: [("e1", Data()), ("e2", Data()), ("e3", Data())], unlisted: ["e1", "e2", "e3"]),
                          .archive(.zip(.tooManyEntries(5))))
        let big = Data(repeating: 0x41, count: 1_048_577)
        let oversized = try ArchiveFixtures.handBuilt(files: [("scene.json", ArchiveFixtures.sceneBytes(ArchiveFixtures.plainScene())), ("big.bin", big)],
                                                      records: [], unlisted: ["big.bin"])
        try assertRefused(oversized, .archive(.zip(.entryTooLarge("big.bin"))), limits: small)
        try assertRefused(try standard(), .archiveTooLarge(limit: 100),
                          limits: SceneArchiveLimits(maxArchiveBytes: 100, maxManifestBytes: 4_096, maxPhotoBytes: 200, maxVideoBytes: 2_000))
        try assertRefused(try standard(), .assetTooLarge("assets/clip.mov"),
                          limits: SceneArchiveLimits(maxArchiveBytes: 1 << 22, maxManifestBytes: 4_096, maxPhotoBytes: 1_000, maxVideoBytes: 10))
    }

    // MARK: Manifest and file list

    func testUnlistedMissingAndExtraFilesAreRefused() throws {
        try assertRefused(try plain(plus: [("notes.txt", Data("hi".utf8))], unlisted: ["notes.txt"]), .archive(.unlistedFile("notes.txt")))
        try assertRefused(try plain(plus: [("notes.txt", Data("hi".utf8))]), .unexpectedFile("notes.txt"))
        let withoutPhotoFile = try ArchiveFixtures.standardFiles().filter { (e: (String, Data)) -> Bool in e.0 != "assets/photo1.png" }
        try assertRefused(try ArchiveFixtures.handBuilt(files: withoutPhotoFile, records: records), .missingAssetFile("assets/photo1.png"))
        try assertRefused(try ArchiveFixtures.handBuilt(files: withoutPhotoFile, records: records, listedButAbsent: ["assets/photo1.png"]),
                          .archive(.missingFile("assets/photo1.png")))
        let withoutScene = try ArchiveFixtures.standardFiles().filter { (e: (String, Data)) -> Bool in e.0 != "scene.json" }
        try assertRefused(try ArchiveFixtures.handBuilt(files: withoutScene, records: records), .missingScene)
    }

    func testNewerVersionWrongFormatAndBadSceneNameAreRefused() throws {
        let files = try ArchiveFixtures.standardFiles()
        try assertRefused(try ArchiveFixtures.handBuilt(files: files, records: records, version: 2), .archive(.newerVersion(2)))
        try assertRefused(try ArchiveFixtures.handBuilt(files: files, records: records, format: "projectm-ios.user-presets"), .archive(.wrongFormat))
        try assertRefused(try ArchiveFixtures.handBuilt(files: files, records: records, scene: "other.json"),
                          .malformedManifest("scene is not scene.json"))
    }

    func testBadAssetRecordsAreRefused() throws {
        let files = try ArchiveFixtures.standardFiles()
        let wrongPath = [ArchiveFixtures.videoRecord, SceneArchiveAssetRecord(key: "photo1", type: "photo", path: "assets/other.png")]
        try assertRefused(try ArchiveFixtures.handBuilt(files: files, records: wrongPath),
                          .malformedManifest("asset \"photo1\" has the path assets/other.png"))
        let unknownType = [ArchiveFixtures.videoRecord, SceneArchiveAssetRecord(key: "photo1", type: "hologram", path: "assets/photo1.png")]
        try assertRefused(try ArchiveFixtures.handBuilt(files: files, records: unknownType), .malformedManifest("unknown asset type \"hologram\""))
        try assertRefused(try ArchiveFixtures.handBuilt(files: files, records: records + [ArchiveFixtures.photoRecord]),
                          .malformedManifest("asset \"photo1\" listed twice"))
        let twoPhotos = [ArchiveFixtures.photoRecord, SceneArchiveAssetRecord(key: "photo2", type: "photo", path: "assets/photo2.png")]
        let photoFiles = files.filter { (e: (String, Data)) -> Bool in e.0 != "assets/clip.mov" } + [("assets/photo2.png", ArchiveFixtures.pngBytes)]
        try assertRefused(try ArchiveFixtures.handBuilt(files: photoFiles, records: twoPhotos),
                          .tooManyMedia(.photo))
    }

    // MARK: Scene against records

    func testManifestAndSceneMismatchesAreRefused() throws {
        // A record whose asset the scene does not have.
        var noPhoto = try ArchiveFixtures.scene()
        noPhoto.layers.removeAll { (l: SceneLayer) -> Bool in l.kind == "photo" }
        noPhoto.assets["photo1"] = nil
        try assertRefused(try ArchiveFixtures.handBuilt(files: try replacing("scene.json", with: ArchiveFixtures.sceneBytes(noPhoto)), records: records),
                          .mismatch(key: "photo1"))
        // An asset without a record (and without a file).
        let withoutPhoto = try ArchiveFixtures.standardFiles().filter { (e: (String, Data)) -> Bool in e.0 != "assets/photo1.png" }
        try assertRefused(try ArchiveFixtures.handBuilt(files: withoutPhoto, records: [ArchiveFixtures.videoRecord]), .mismatch(key: "photo1"))
        // The record's type differs from the scene's.
        let asVideo = [ArchiveFixtures.videoRecord, SceneArchiveAssetRecord(key: "photo1", type: "video", path: "assets/photo1.mov")]
        let files = withoutPhoto + [("assets/photo1.mov", ArchiveFixtures.movieBytes)]
        try assertRefused(try ArchiveFixtures.handBuilt(files: files, records: asVideo), .tooManyMedia(.video))
        let onlyPhotoAsVideo = [SceneArchiveAssetRecord(key: "photo1", type: "video", path: "assets/photo1.mov")]
        let photoAsVideoFiles: [(String, Data)] = [("scene.json", ArchiveFixtures.sceneBytes(try sceneWithoutVideo())), ("assets/photo1.mov", ArchiveFixtures.movieBytes)]
        try assertRefused(try ArchiveFixtures.handBuilt(files: photoAsVideoFiles, records: onlyPhotoAsVideo), .mismatch(key: "photo1"))
    }

    private func sceneWithoutVideo() throws -> SceneDocument {
        var scene = try ArchiveFixtures.scene()
        scene.layers.removeAll { (l: SceneLayer) -> Bool in l.kind == "video" }
        scene.assets["clip"] = nil
        return scene
    }

    func testRefusedAndInvalidScenesAreRefused() throws {
        try assertRefused(try ArchiveFixtures.handBuilt(files: try replacing("scene.json", with: Data("{}".utf8)), records: records),
                          .sceneRefused(.notAScene))
        var dangling = try ArchiveFixtures.scene()
        dangling.layers.append(SceneLayer(instance: 9, content: .material(id: "material.nonexistent")))
        let data = try ArchiveFixtures.handBuilt(files: try replacing("scene.json", with: ArchiveFixtures.sceneBytes(dangling)), records: records)
        XCTAssertThrowsError(try SceneArchiveReader.read(data, registry: try ArchiveFixtures.registry())) { (error: Error) in
            guard case let .sceneInvalid(issues)? = error as? SceneArchiveError else { return XCTFail("\(error)") }
            XCTAssertFalse(issues.isEmpty)
            XCTAssertTrue(issues.allSatisfy(\.isError))
        }
    }

    // MARK: Asset content (SHD-011 signatures, MED-014 sniffers)

    func testProgramsScriptsNestedArchivesAndWrongTypesAreRefused() throws {
        let machO = Data([0xCF, 0xFA, 0xED, 0xFE] + [UInt8](repeating: 0, count: 60))
        try assertRefused(try ArchiveFixtures.handBuilt(files: try replacing("assets/clip.mov", with: machO), records: records),
                          .executableContent(path: "assets/clip.mov", kind: .machO))
        try assertRefused(try ArchiveFixtures.handBuilt(files: try replacing("assets/photo1.png", with: Data("#!/bin/sh\necho hi\n".utf8)), records: records),
                          .executableContent(path: "assets/photo1.png", kind: .script))
        let nested = try ArchiveFixtures.archive()
        try assertRefused(try ArchiveFixtures.handBuilt(files: try replacing("assets/clip.mov", with: nested), records: records),
                          .nestedArchive("assets/clip.mov"))
        try assertRefused(try ArchiveFixtures.handBuilt(files: try replacing("assets/photo1.png", with: ArchiveFixtures.movieBytes), records: records),
                          .wrongContent("assets/photo1.png"))
        let jpegNamedPNG = Data([0xFF, 0xD8, 0xFF, 0xD9])
        try assertRefused(try ArchiveFixtures.handBuilt(files: try replacing("assets/photo1.png", with: jpegNamedPNG), records: records),
                          .wrongContent("assets/photo1.png"))
        try assertRefused(try ArchiveFixtures.handBuilt(files: try replacing("assets/clip.mov", with: ArchiveFixtures.pngBytes), records: records),
                          .wrongContent("assets/clip.mov"))
    }

    func testDamagedBytesAreRefusedWithoutTrapping() throws {
        try assertRefused(Data(), .archive(.zip(.notAZip)))
        let good = try ArchiveFixtures.archive()
        try assertRefused(good.prefix(good.count / 2), .archive(.zip(.truncated)))
        var flipped = good
        let start = ZipHeaders.dataStart(flipped, entry: 2)
        flipped[flipped.startIndex + start] ^= 0xFF
        try assertRefused(flipped, .archive(.zip(.checksumMismatch("assets/photo1.png"))))
    }
}

/// Little-endian header access (as LocalPortability's own tests do).
enum ZipHeaders {
    static func u16(_ d: Data, _ at: Int) -> Int { Int(d[d.startIndex + at]) | Int(d[d.startIndex + at + 1]) << 8 }
    static func u32(_ d: Data, _ at: Int) -> Int { u16(d, at) | u16(d, at + 2) << 16 }

    static func set32(_ d: inout Data, _ at: Int, _ value: Int) {
        for i in 0..<4 { d[d.startIndex + at + i] = UInt8((value >> (8 * i)) & 0xFF) }
    }

    static func centralHeaders(_ d: Data) -> [Int] {
        let end = d.count - 22
        var at = u32(d, end + 16)
        var result: [Int] = []
        for _ in 0..<u16(d, end + 10) {
            result.append(at)
            at += 46 + u16(d, at + 28) + u16(d, at + 30) + u16(d, at + 32)
        }
        return result
    }

    static func dataStart(_ d: Data, entry: Int) -> Int {
        let local = u32(d, centralHeaders(d)[entry] + 42)
        return local + 30 + u16(d, local + 26) + u16(d, local + 28)
    }
}
