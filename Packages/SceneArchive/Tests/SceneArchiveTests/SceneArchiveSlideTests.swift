// SceneArchiveSlideTests.swift — SCN-014-T03: slideshow pictures in a scene archive and the path audit
// (SCN-014-R1 to R4; contract specs/187-scn-014-dependency-pack/contracts/scene-pack.md P1-P3).
import Foundation
import LocalPortability
import MediaSniffing
@testable import SceneArchive
@testable import SceneFormat
import XCTest

final class SceneArchiveSlideTests: XCTestCase {
    private let slide1 = "11111111-1111-4111-8111-111111111111"
    private let slide2 = "22222222-2222-4222-8222-222222222222"
    private let slideA = Data(MediaFixtureBytes.png(width: 5, height: 4))
    private let slideB = Data(MediaFixtureBytes.png(width: 6, height: 2))

    /// The FILE-001 fixture scene whose photo asset has a two-picture slideshow (and an unknown slideshow field).
    private func scene(slides: [String]? = nil) throws -> SceneDocument {
        var document = try ArchiveFixtures.scene()
        var asset = try XCTUnwrap(document.assets["photo1"])
        var object = SceneSlideshow(enabled: true, storeIDs: slides ?? [slide1, slide2], mode: "time", seconds: 5, beats: 4).json.objectValue ?? [:]
        object["futureField"] = .string("kept")
        asset.extra[SceneSlideshow.key] = .object(object)
        document.assets["photo1"] = asset
        return document
    }

    private func slides() -> [SceneArchiveSlide] {
        [SceneArchiveSlide(key: "photo1", index: 2, fileExtension: "png", data: slideB),
         SceneArchiveSlide(key: "photo1", index: 1, fileExtension: "png", data: slideA)]
    }

    private func write(_ document: SceneDocument, slides: [SceneArchiveSlide]) throws -> Data {
        try SceneArchiveWriter.data(document: document, media: ArchiveFixtures.media(), slides: slides,
                                    registry: try ArchiveFixtures.registry(), modified: ArchiveFixtures.date)
    }

    private func manifest(_ archive: Data) throws -> [String: Any] {
        let contents = try PortableArchive.read(archive, schema: SceneArchiveFormat.manifestSchema, limits: SceneArchiveLimits.standard.portable)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: contents.manifest) as? [String: Any])
    }

    // MARK: Round trip (P1, P2)

    func testSlidesTravelInOrderAndRemapKeepsOtherFields() throws {
        let document = try scene()
        let archive = try write(document, slides: slides())
        let records = try XCTUnwrap(try manifest(archive)["slides"] as? [[String: Any]])
        XCTAssertEqual(records.map { (r: [String: Any]) -> String in r["path"] as? String ?? "" },
                       ["assets/photo1-slide-01.png", "assets/photo1-slide-02.png"])
        let read = try SceneArchiveReader.read(archive, registry: try ArchiveFixtures.registry())
        XCTAssertEqual(read.document, document)
        XCTAssertEqual(read.slides.map(\.index), [1, 2])
        XCTAssertEqual(read.slides.map(\.data), [slideA, slideB])
        XCTAssertEqual(read.document.slideStoreIDs.first?.storeIDs, [slide1, slide2])

        let newIDs = ["AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA", "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB"]
        let remapped = read.document.remappingSlideIDs(["photo1": newIDs, "caption": newIDs])
        XCTAssertEqual(remapped.slideStoreIDs.first?.storeIDs, newIDs)
        XCTAssertEqual(remapped.assets["photo1"]?.extra[SceneSlideshow.key]?.objectValue?["futureField"], .string("kept"))
        XCTAssertEqual(remapped.assets["photo1"]?.kind, document.assets["photo1"]?.kind, "the photo's own ID is not touched")
        XCTAssertEqual(remapped.assets["caption"], document.assets["caption"], "only photo assets with a slideshow change")
    }

    func testAnArchiveWithoutSlidesHasNoSlidesField() throws {
        let archive = try ArchiveFixtures.archive()
        XCTAssertNil(try manifest(archive)["slides"])
        XCTAssertEqual(try SceneArchiveReader.read(archive, registry: try ArchiveFixtures.registry()).slides, [])
    }

    func testTheWriterRefusesMissingExtraAndWrongSlides() throws {
        let document = try scene()
        XCTAssertThrowsError(try write(document, slides: Array(slides().prefix(1)))) { (error: any Error) in
            XCTAssertEqual(error as? SceneArchiveError, .missingMedia(key: "photo1"))
        }
        let extra = slides() + [SceneArchiveSlide(key: "photo1", index: 3, fileExtension: "png", data: slideA)]
        XCTAssertThrowsError(try write(document, slides: extra)) { (error: any Error) in
            XCTAssertEqual(error as? SceneArchiveError, .slideMismatch(key: "photo1"))
        }
        let repeated = [SceneArchiveSlide(key: "photo1", index: 1, fileExtension: "png", data: slideA),
                        SceneArchiveSlide(key: "photo1", index: 1, fileExtension: "jpg", data: slideA)]
        XCTAssertThrowsError(try write(document, slides: repeated)) { (error: any Error) in
            XCTAssertEqual(error as? SceneArchiveError, .slideMismatch(key: "photo1"))
        }
        let notAPicture = [SceneArchiveSlide(key: "photo1", index: 1, fileExtension: "png", data: Data("hello".utf8)), slides()[0]]
        XCTAssertThrowsError(try write(document, slides: notAPicture)) { (error: any Error) in
            XCTAssertEqual(error as? SceneArchiveError, .wrongContent("assets/photo1-slide-01.png"))
        }
    }

    // MARK: Path audit (P3, R2)

    func testTheAuditFlagsLocationsButNotText() {
        for text in ["/var/mobile/Containers/Data/Application/1/Library/Photos/a.png", "/private/var/x", "/Users/me/a.png",
                     "file:///tmp/a.png", "FILE:/x", "~/Documents/a", "Library/x/Containers/Data/Application/y",
                     "/Library/Application Support/Photos/a.png"] {
            XCTAssertTrue(SceneArchivePathAudit.isAbsoluteLocation(text), text)
        }
        for text in ["1/2", "/// drop", "/", "AC/DC", "assets/photo1.png", "Night Drive", "/variety show"] {
            XCTAssertFalse(SceneArchivePathAudit.isAbsoluteLocation(text), text)
        }
        let json = Data(#"{"a":["x",{"/Users/me":"y","z":"file:///q"}]}"#.utf8)
        XCTAssertEqual(SceneArchivePathAudit.findings(inJSON: json), ["/Users/me", "file:///q"])
    }

    func testTheWriterRefusesASceneThatNamesALocation() throws {
        var document = try ArchiveFixtures.scene()
        var clip = try XCTUnwrap(document.assets["clip"])
        clip.extra["futureNote"] = .string("/var/mobile/Containers/Data/Application/X/Library/Application Support/Videos/a.mov")
        document.assets["clip"] = clip
        XCTAssertThrowsError(try write(document, slides: [])) { (error: any Error) in
            guard case .absolutePath? = error as? SceneArchiveError else { return XCTFail("\(error)") }
        }
        // The written fixture archive itself has no location anywhere (manifest, scene, entry names).
        let archive = try write(try scene(), slides: slides())
        let contents = try PortableArchive.read(archive, schema: SceneArchiveFormat.manifestSchema, limits: SceneArchiveLimits.standard.portable)
        XCTAssertEqual(SceneArchivePathAudit.findings(inJSON: contents.manifest), [])
        XCTAssertEqual(SceneArchivePathAudit.findings(inJSON: try XCTUnwrap(contents.files["scene.json"])), [])
        XCTAssertTrue(contents.records.allSatisfy { (r: PortableFileRecord) -> Bool in ArchivePath.isSafe(r.path) })
    }

    // MARK: Crafted packs (P2, R4)

    /// The standard files plus slide files, with `records` as the manifest's `slides`.
    private func crafted(slideFiles: [(String, Data)], records: [[String: Any]], scene document: SceneDocument? = nil) throws -> Data {
        var out = Data()
        let zip = StoredZipWriter(modified: ArchiveFixtures.date) { (chunk: Data) in out.append(chunk) }
        var files: [(String, Data)] = try ArchiveFixtures.standardFiles()
        files[0] = ("scene.json", ArchiveFixtures.sceneBytes(try document ?? scene()))
        files += slideFiles
        var listed: [[String: Any]] = []
        for (path, data) in files {
            try zip.add(path: path, data: data)
            listed.append(["path": path, "sha256": PortableSHA256.hex(data), "byteCount": data.count])
        }
        let assets: [[String: Any]] = [ArchiveFixtures.videoRecord, ArchiveFixtures.photoRecord].map { (r: SceneArchiveAssetRecord) -> [String: Any] in
            ["key": r.key, "type": r.type, "path": r.path]
        }
        let manifest: [String: Any] = ["format": SceneArchiveFormat.formatName, "formatVersion": 1, "files": listed, "scene": "scene.json",
                                       "assets": assets, "slides": records]
        try zip.add(path: "manifest.json", data: try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys]))
        try zip.finish()
        return out
    }

    private func refused(_ data: Data, file: StaticString = #filePath, line: UInt = #line) throws -> SceneArchiveError? {
        do {
            _ = try SceneArchiveReader.read(data, registry: try ArchiveFixtures.registry())
            XCTFail("accepted", file: file, line: line)
            return nil
        } catch {
            return error as? SceneArchiveError
        }
    }

    func testCraftedSlideRecordsAreRefused() throws {
        let one: (String, Data) = ("assets/photo1-slide-01.png", slideA)
        let two: (String, Data) = ("assets/photo1-slide-02.png", slideB)
        let good: [[String: Any]] = [["key": "photo1", "index": 1, "path": one.0], ["key": "photo1", "index": 2, "path": two.0]]
        XCTAssertEqual(try SceneArchiveReader.read(try crafted(slideFiles: [one, two], records: good), registry: try ArchiveFixtures.registry()).slides.count, 2,
                       "the hand-built control is accepted")

        let wrongPath: [[String: Any]] = [["key": "photo1", "index": 1, "path": "assets/other.png"], good[1]]
        guard case .malformedManifest? = try refused(try crafted(slideFiles: [("assets/other.png", slideA), two], records: wrongPath)) else {
            return XCTFail("wrong path")
        }
        let repeated: [[String: Any]] = [good[0], good[0]]
        guard case .malformedManifest? = try refused(try crafted(slideFiles: [one], records: repeated)) else { return XCTFail("repeated") }
        XCTAssertEqual(try refused(try crafted(slideFiles: [one], records: [good[0]])), .slideMismatch(key: "photo1"), "count mismatch")
        XCTAssertEqual(try refused(try crafted(slideFiles: [one, two], records: good, scene: try ArchiveFixtures.scene())),
                       .slideMismatch(key: "photo1"), "slides for a scene without a slideshow")
        // A listed slide whose file is absent from the archive.
        XCTAssertEqual(try refused(try crafted(slideFiles: [one], records: good)), .missingAssetFile(two.0))
        // A slide that is not a picture.
        XCTAssertEqual(try refused(try crafted(slideFiles: [one, (two.0, Data("text".utf8))], records: good)), .wrongContent(two.0))
    }

    func testTraversalAndAbsoluteSlideEntriesAreRefusedByTheZipLayer() throws {
        let one: (String, Data) = ("assets/photo1-slide-01.png", slideA)
        let records: [[String: Any]] = [["key": "photo1", "index": 1, "path": one.0]]
        let base = try crafted(slideFiles: [one, ("ab/x.png", slideB)], records: records, scene: try scene(slides: [slide1]))
        let traversal = ArchiveFixtures.patch(base, "ab/x.png", "../x.png")
        XCTAssertEqual(try refused(traversal), .archive(.zip(.unsafePath("../x.png"))))
        let absolute = ArchiveFixtures.patch(base, "ab/x.png", "/a/x.png")
        XCTAssertEqual(try refused(absolute), .archive(.zip(.unsafePath("/a/x.png"))))
    }
}
