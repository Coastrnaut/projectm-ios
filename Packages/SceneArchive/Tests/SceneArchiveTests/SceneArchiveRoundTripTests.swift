// SceneArchiveRoundTripTests.swift — FILE-001-T09: layout, manifest, determinism, round trip and
// remapping (FILE-001-R1 to R4, R11, R14, R15; S1 at the package level).
import Foundation
import LocalPortability
@testable import SceneArchive
import SceneFormat
import XCTest

final class SceneArchiveRoundTripTests: XCTestCase {
    private func entries(_ data: Data) throws -> [StoredZipEntry] {
        try StoredZipReader.read(data, limits: StoredZipLimits(maxEntries: 10, maxEntryBytes: 1 << 20, maxArchiveBytes: 1 << 22))
    }

    func testTheArchiveHoldsExactlySceneAssetsAndManifestWithRelativeNames() throws {
        let data = try ArchiveFixtures.archive()
        let entries = try entries(data)
        XCTAssertEqual(entries.map(\.path), ["scene.json", "assets/clip.mov", "assets/photo1.png", "manifest.json"])
        XCTAssertEqual(entries[0].data, Data(try ArchiveFixtures.scene().encoded()), "scene.json is the canonical encoding")
        XCTAssertEqual(entries[1].data, ArchiveFixtures.movieBytes, "media bytes are packed unchanged")
        XCTAssertEqual(entries[2].data, ArchiveFixtures.pngBytes)
        let manifest = try JSONDecoder().decode(SceneArchiveManifest.self, from: entries[3].data)
        XCTAssertEqual(manifest.format, "projectm-ios.scene-archive")
        XCTAssertEqual(manifest.formatVersion, 1)
        XCTAssertEqual(manifest.scene, "scene.json")
        XCTAssertEqual(manifest.assets, [ArchiveFixtures.videoRecord, ArchiveFixtures.photoRecord])
        XCTAssertEqual(manifest.files.map(\.path), ["scene.json", "assets/clip.mov", "assets/photo1.png"])
        XCTAssertEqual(manifest.files.map(\.byteCount), entries.prefix(3).map(\.data.count))
        XCTAssertEqual(manifest.files[2].sha256, PortableSHA256.hex(ArchiveFixtures.pngBytes))
        let manifestText = String(decoding: entries[3].data, as: UTF8.self)
        XCTAssertTrue(manifestText.hasPrefix("{\"assets\":[{\"key\":\"clip\",\"path\":\"assets/clip.mov\",\"type\":\"video\"}"), manifestText)
        for entry in entries {
            XCTAssertFalse(entry.path.hasPrefix("/"))
            XCTAssertFalse(entry.path.contains(".."))
        }
    }

    func testTwoExportsWithTheSameDateAreByteIdentical() throws {
        XCTAssertEqual(try ArchiveFixtures.archive(), try ArchiveFixtures.archive())
    }

    func testReadingGivesTheSameSceneAndMedia() throws {
        let contents = try SceneArchiveReader.read(try ArchiveFixtures.archive(), registry: try ArchiveFixtures.registry())
        XCTAssertEqual(contents.document, try ArchiveFixtures.scene())
        XCTAssertEqual(contents.media, ArchiveFixtures.media())
        XCTAssertEqual(contents.document.assets["future"], SceneAsset(.unknown(type: "hologram"), extra: ["beam": .string("blue")]),
                       "an unknown asset type survives with its fields and carries no file")
        XCTAssertEqual(contents.document.extra["futureTopLevel"], .bool(true))
    }

    func testASceneWithoutMediaHoldsOnlyTheSceneAndManifest() throws {
        let data = try SceneArchiveWriter.data(document: ArchiveFixtures.plainScene(), media: [], registry: try ArchiveFixtures.registry(),
                                               modified: ArchiveFixtures.date)
        XCTAssertEqual(try entries(data).map(\.path), ["scene.json", "manifest.json"])
        let contents = try SceneArchiveReader.read(data, registry: try ArchiveFixtures.registry())
        XCTAssertEqual(contents.document, ArchiveFixtures.plainScene())
        XCTAssertEqual(contents.media, [])
    }

    func testAnUnusedPhotoAssetIsPackedLikeAUsedOne() throws {
        let scene = try ArchiveFixtures.scene(unusedPhoto: true)
        let data = try SceneArchiveWriter.data(document: scene, media: ArchiveFixtures.media(), registry: try ArchiveFixtures.registry(),
                                               modified: ArchiveFixtures.date)
        let contents = try SceneArchiveReader.read(data, registry: try ArchiveFixtures.registry())
        XCTAssertEqual(contents.media.map(\.key), ["clip", "photo1"])
        XCTAssertTrue(contents.warnings.contains { (i: SceneIssue) -> Bool in i.code == .unusedAsset })
    }

    func testRemappingChangesOnlyTheNamedStoreIDs() throws {
        let scene = try ArchiveFixtures.scene()
        let newPhoto = "11111111-2222-3333-4444-555555555555", newVideo = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        let remapped = scene.remappingStoreIDs(["photo1": newPhoto, "clip": newVideo, "caption": newPhoto, "absent": newPhoto])
        XCTAssertEqual(remapped.assets["photo1"], .photo(storeID: newPhoto))
        XCTAssertEqual(remapped.assets["clip"], SceneAsset(.video(storeID: newVideo), extra: ["futureNote": .string("kept")]))
        XCTAssertEqual(remapped.assets["caption"], scene.assets["caption"], "text is not a store asset")
        XCTAssertEqual(Set(remapped.assets.keys), Set(scene.assets.keys))
        var expected = scene
        expected.assets["photo1"] = .photo(storeID: newPhoto)
        expected.assets["clip"] = SceneAsset(.video(storeID: newVideo), extra: ["futureNote": .string("kept")])
        XCTAssertEqual(remapped, expected, "layers, parameters, other assets and unknown content are unchanged")
        XCTAssertEqual(remapped.remappingStoreIDs(["photo1": ArchiveFixtures.photoID, "clip": ArchiveFixtures.videoID]), scene)
    }

    // MARK: - Export refusals (FILE-001-R4)

    private func assertExportRefused(_ document: SceneDocument, _ media: [SceneArchiveMedia], _ expected: SceneArchiveError,
                                     file: StaticString = #filePath, line: UInt = #line) throws {
        let registry = try ArchiveFixtures.registry()
        XCTAssertThrowsError(try SceneArchiveWriter.data(document: document, media: media, registry: registry, modified: ArchiveFixtures.date),
                             file: file, line: line) { (error: Error) in
            XCTAssertEqual(error as? SceneArchiveError, expected, file: file, line: line)
        }
    }

    func testExportRefusesMissingExtraOrWrongMedia() throws {
        let scene = try ArchiveFixtures.scene()
        let media = ArchiveFixtures.media()
        try assertExportRefused(scene, [media[0]], .missingMedia(key: "photo1"))
        try assertExportRefused(scene, media + [SceneArchiveMedia(key: "other", type: .photo, fileExtension: "png", data: ArchiveFixtures.pngBytes)],
                                .mismatch(key: "other"))
        try assertExportRefused(scene, [media[0], SceneArchiveMedia(key: "photo1", type: .photo, fileExtension: "png", data: ArchiveFixtures.movieBytes)],
                                .wrongContent("assets/photo1.png"))
        try assertExportRefused(scene, [media[0], SceneArchiveMedia(key: "photo1", type: .photo, fileExtension: "gif", data: ArchiveFixtures.pngBytes)],
                                .wrongContent("assets/photo1.gif"))
        var two = scene
        two.assets["photo2"] = .photo(storeID: ArchiveFixtures.photoID)
        try assertExportRefused(two, media, .tooManyMedia(.photo))
        var broken = scene
        broken.name = ""
        XCTAssertThrowsError(try SceneArchiveWriter.data(document: broken, media: media, registry: try ArchiveFixtures.registry(),
                                                         modified: ArchiveFixtures.date)) { (error: Error) in
            guard case .sceneInvalid? = error as? SceneArchiveError else { return XCTFail("\(error)") }
        }
    }
}
