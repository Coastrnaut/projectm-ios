// SceneTemplateTests.swift — SCN-011-T04 (contract T1, T2, T4; SCN-011-S1 to S4): the app's bundled templates,
// read from the repository copy (`Apps/projectM-iOS/Resources/SceneTemplates`, found from this file's path so
// the test also runs on Linux CI), decode with no warnings and carry a licence for every asset; copies are
// independent of the template and of each other.
import Foundation
import SceneFormat
import ShowControl
import ShowStorage
import XCTest

final class SceneTemplateTests: XCTestCase {
    /// `<repo>/Apps/projectM-iOS/Resources/SceneTemplates`.
    static var bundledFolder: URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }   // …/Tests/ShowControlTests/<file> → repo root
        return url.appendingPathComponent("Apps/projectM-iOS/Resources/SceneTemplates", isDirectory: true)
    }

    private func temporaryFolder(_ name: String) -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    private func id(_ n: Int) -> String { String(format: "A11CE000-0000-4000-8000-%012d", n) }

    // MARK: Bundled templates (S3, S4)

    func testEveryBundledTemplateIsOfferedAndDecodesWithoutWarnings() throws {
        let catalog = SceneTemplateCatalog.load(directory: Self.bundledFolder)
        XCTAssertEqual(catalog.skipped, [], "no bundled template is left out")
        XCTAssertEqual(catalog.templates.map(\.id), ["pulse-rings", "spectrum-bars", "horizon-bars", "title-card", "show-starter"])
        for template in catalog.templates {
            XCTAssertFalse(template.summary.isEmpty)
            XCTAssertTrue(template.tags.contains("template"))
            for scene in template.scenes {
                let result = try SceneDocument.decode([UInt8](try Data(contentsOf: scene.file)))
                XCTAssertEqual(result.warnings, [], "\(scene.file.lastPathComponent) decodes without warnings")
                XCTAssertTrue(scene.document.layers.allSatisfy { (layer: SceneLayer) -> Bool in
                    SceneTemplateCatalog.allowedLayerKinds.contains(layer.kind)
                }, "native layers only")
            }
        }
        let starter = try XCTUnwrap(catalog.template("show-starter"))
        XCTAssertEqual(starter.scenes.map(\.label), ["Opening", "Welcome"])
        XCTAssertNil(starter.scenes[0].transition)
        XCTAssertEqual(starter.scenes[1].transition?.type, .crossfade)
        XCTAssertEqual(starter.scenes[1].transition?.durationSeconds, 1.5)
    }

    func testTheLicenceManifestListsEveryAssetWithTheProjectsOwnLicence() throws {
        let data = try Data(contentsOf: Self.bundledFolder.appendingPathComponent(SceneTemplateManifest.fileName))
        let manifest = try JSONDecoder().decode(SceneTemplateManifest.self, from: data)
        var assetCount = 0
        for record in manifest.templates {
            for scene in record.scenes {
                let document = try SceneDocument.decode([UInt8](try Data(contentsOf: Self.bundledFolder.appendingPathComponent(scene.file)))).document
                XCTAssertEqual(Set(scene.assets.map(\.key)), Set(document.assets.keys), "\(scene.file): every asset listed")
                for asset in scene.assets {
                    XCTAssertEqual(asset.licence, "MIT", "\(scene.file) \(asset.key)")
                    XCTAssertFalse(asset.source.isEmpty)
                    assetCount += 1
                }
                XCTAssertTrue(SceneTemplateCatalog.licencesCover(document, records: scene.assets))
            }
        }
        XCTAssertEqual(assetCount, 2, "the two title texts are the only assets")
        // The licence named is the repository's.
        let licence = try String(contentsOf: Self.bundledFolder.appendingPathComponent("../../../../LICENSE").standardizedFileURL, encoding: .utf8)
        XCTAssertTrue(licence.hasPrefix("MIT License"))
    }

    func testAnUnlistedAssetOrAForeignLayerKindIsNotOffered() {
        let photo = SceneDocument(id: id(1), name: "Photo", layers: [SceneLayer(instance: 1, content: .photo(asset: "p"))],
                                  assets: ["p": SceneAsset(.photo(storeID: id(2)))])
        XCTAssertFalse(SceneTemplateCatalog.licencesCover(photo, records: []))
        let text = SceneDocument(id: id(3), name: "Text", layers: [SceneLayer(instance: 1, content: .text(asset: "t"))],
                                 assets: ["t": SceneAsset(.text(spec: .object(["message": .string("Hi")])))])
        XCTAssertFalse(SceneTemplateCatalog.licencesCover(text, records: []), "unlisted asset")
        let unknown = SceneTemplateAssetRecord(key: "t", kind: "text", source: "Written here.", licence: "CC-BY-NC-4.0")
        XCTAssertFalse(SceneTemplateCatalog.licencesCover(text, records: [unknown]), "licence not allowed")
        let mit = SceneTemplateAssetRecord(key: "t", kind: "text", source: "Written here.", licence: "MIT")
        XCTAssertTrue(SceneTemplateCatalog.licencesCover(text, records: [mit]))
    }

    func testABadManifestOffersNothingAndAMissingSceneFileSkipsOnlyItsTemplate() throws {
        let folder = temporaryFolder("SceneTemplateTests")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{".utf8).write(to: folder.appendingPathComponent(SceneTemplateManifest.fileName))
        XCTAssertEqual(SceneTemplateCatalog.load(directory: folder).templates, [])

        for name in try FileManager.default.contentsOfDirectory(atPath: Self.bundledFolder.path) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
            try FileManager.default.copyItem(at: Self.bundledFolder.appendingPathComponent(name), to: folder.appendingPathComponent(name))
        }
        try FileManager.default.removeItem(at: folder.appendingPathComponent("horizon-bars.scene.json"))
        let catalog = SceneTemplateCatalog.load(directory: folder)
        XCTAssertEqual(catalog.skipped, ["horizon-bars"])
        XCTAssertEqual(catalog.templates.count, 4)
    }

    // MARK: Independent copies (S1, S2; roadmap acceptance)

    func testTwoCopiesAreIndependentOfEachOtherAndOfTheTemplate() throws {
        let catalog = SceneTemplateCatalog.load(directory: Self.bundledFolder)
        let scene = try XCTUnwrap(catalog.template("pulse-rings")?.scenes.first)
        let templateBytes = try Data(contentsOf: scene.file)
        let store = ShowStore(directory: temporaryFolder("SceneTemplateCopies"))

        // 1. Instantiate twice: two distinct IDs and two files.
        let first = try store.storeTemplateCopy(scene.document, newID: id(11), name: "Pulse Rings")
        let second = try store.storeTemplateCopy(scene.document, newID: id(12), name: "Pulse Rings")
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(first.id, scene.document.id)
        XCTAssertEqual(store.storedSceneIDs(), [id(11), id(12)])
        let secondBytes = try Data(contentsOf: store.sceneFile(second.id))

        // 2. Edit copy 1 (a parameter) and save: copy 2 and the template are byte-identical.
        var edited = try store.scene(first.id).document
        edited.parameters["effect.bloom.intensity"] = .continuous(0.1)
        try store.saveScene(edited)
        XCTAssertEqual(try store.scene(first.id).document.parameters["effect.bloom.intensity"], .continuous(0.1))
        XCTAssertEqual(try Data(contentsOf: store.sceneFile(second.id)), secondBytes)
        XCTAssertEqual(try Data(contentsOf: scene.file), templateBytes)

        // 3. Delete copy 1: copy 2 still loads.
        try FileManager.default.removeItem(at: store.sceneFile(first.id))
        XCTAssertEqual(try store.scene(second.id).document, second)
        XCTAssertEqual(try Data(contentsOf: scene.file), templateBytes)
    }

    func testACopyOntoAStoredIDIsRefusedAndWritesNothing() throws {
        let scene = try XCTUnwrap(SceneTemplateCatalog.load(directory: Self.bundledFolder).template("spectrum-bars")?.scenes.first)
        let store = ShowStore(directory: temporaryFolder("SceneTemplateTaken"))
        try store.storeTemplateCopy(scene.document, newID: id(21), name: "Spectrum Bars")
        let before = try Data(contentsOf: store.sceneFile(id(21)))
        XCTAssertThrowsError(try store.storeTemplateCopy(scene.document, newID: id(21), name: "Other")) { (error: Error) in
            XCTAssertEqual(error as? ShowSceneEditError, .sceneIDTaken(id(21)))
        }
        XCTAssertEqual(try Data(contentsOf: store.sceneFile(id(21))), before)
        XCTAssertThrowsError(try store.storeTemplateCopy(scene.document, newID: "not-an-id", name: "X"))
        XCTAssertEqual(store.storedSceneIDs(), [id(21)])
    }
}
