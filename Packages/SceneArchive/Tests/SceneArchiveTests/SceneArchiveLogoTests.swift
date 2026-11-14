// MED-010-T18 (MED-010-R11): the archive carries the scene's logo as `assets/<key>.png` with type `logo`;
// a second logo, a JPEG logo and a logo record without its asset are refused; the store IDs remap.
import Foundation
import ImageLayer
import LocalPortability
@testable import SceneArchive
import SceneFormat
import XCTest

final class SceneArchiveLogoTests: XCTestCase {
    private let logoID = "0000B000-0000-4000-8000-000000000001"
    private let placement = LogoPlacement(corner: .topLeft, size: 0.2, margin: 0.03, opacity: 0.7)

    private func sceneWithLogo() throws -> SceneDocument {
        var scene = try ArchiveFixtures.scene()
        scene.assets[SceneLogo.assetKey] = .logo(storeID: logoID, placement: placement)
        return scene
    }

    private func media() -> [SceneArchiveMedia] {
        ArchiveFixtures.media() + [SceneArchiveMedia(key: "logo", type: .logo, fileExtension: "png", data: ArchiveFixtures.pngBytes)]
    }

    func testTheLogoIsPackedAndReadBack() throws {
        let registry = try ArchiveFixtures.registry()
        let data = try SceneArchiveWriter.data(document: try sceneWithLogo(), media: media(), registry: registry, modified: ArchiveFixtures.date)
        let entries = try StoredZipReader.read(data, limits: StoredZipLimits(maxEntries: 10, maxEntryBytes: 1 << 20, maxArchiveBytes: 1 << 22))
        XCTAssertEqual(entries.map(\.path), ["scene.json", "assets/clip.mov", "assets/logo.png", "assets/photo1.png", "manifest.json"])
        let manifest = try JSONDecoder().decode(SceneArchiveManifest.self, from: entries[4].data)
        XCTAssertTrue(manifest.assets.contains(SceneArchiveAssetRecord(key: "logo", type: "logo", path: "assets/logo.png")))
        let contents = try SceneArchiveReader.read(data, registry: registry)
        XCTAssertEqual(contents.document.logo, SceneLogo(storeID: logoID, placement: placement))
        XCTAssertEqual(contents.media.first { (m: SceneArchiveMedia) -> Bool in m.type == .logo }?.data, ArchiveFixtures.pngBytes)
        let newID = "0000C000-0000-4000-8000-000000000009"
        XCTAssertEqual(contents.document.remappingStoreIDs(["logo": newID]).logo, SceneLogo(storeID: newID, placement: placement),
                       "remapped, placement kept")
    }

    func testLogoRefusals() throws {
        let registry = try ArchiveFixtures.registry()
        let jpeg = ArchiveFixtures.media() + [SceneArchiveMedia(key: "logo", type: .logo, fileExtension: "jpg", data: ArchiveFixtures.pngBytes)]
        XCTAssertThrowsError(try SceneArchiveWriter.data(document: try sceneWithLogo(), media: jpeg, registry: registry, modified: ArchiveFixtures.date),
                             "a logo is PNG only")
        var two = try sceneWithLogo()
        two.assets["logo2"] = .logo(storeID: logoID, placement: placement)
        let twoMedia = media() + [SceneArchiveMedia(key: "logo2", type: .logo, fileExtension: "png", data: ArchiveFixtures.pngBytes)]
        XCTAssertThrowsError(try SceneArchiveWriter.data(document: two, media: twoMedia, registry: registry, modified: ArchiveFixtures.date)) {
            (error: any Error) in XCTAssertEqual(error as? SceneArchiveError, .tooManyMedia(.logo))
        }
        XCTAssertThrowsError(try SceneArchiveWriter.data(document: try sceneWithLogo(), media: ArchiveFixtures.media(), registry: registry,
                                                         modified: ArchiveFixtures.date)) {
            (error: any Error) in XCTAssertEqual(error as? SceneArchiveError, .missingMedia(key: "logo"))
        }
        XCTAssertEqual(SceneArchiveLimits.maximumFiles, 24)   // SCN-014: + 20 slides
        XCTAssertEqual(SceneArchiveFormat.allowedExtensions(for: .logo), ["png"])
    }
}
