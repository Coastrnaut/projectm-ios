// MED-010-T17 (MED-010-R10): the scene's `logo` asset — round trip, lenient placement, validation (store ID,
// missing picture, never unused), the repair report entry, and older apps' view of it. CPU only, runs on Linux.
import Compositor
import Foundation
import ImageLayer
@testable import SceneFormat
import XCTest

final class SceneLogoTests: XCTestCase {
    private let logoID = "0000B000-0000-4000-8000-000000000001"

    private func withLogo(_ placement: LogoPlacement = LogoPlacement(corner: .topLeft, size: 0.1, margin: 0.02, opacity: 0.6)) throws -> SceneDocument {
        var document = try SceneFixtures.allKinds()
        document.assets[SceneLogo.assetKey] = .logo(storeID: logoID, placement: placement)
        return document
    }

    func testTheLogoAssetRoundTripsWithItsPlacement() throws {
        let placement = LogoPlacement(corner: .custom, anchorX: 0.25, anchorY: 0, size: 0.3, margin: 0.1, opacity: 0.5)
        let document = try withLogo(placement)
        let decoded = try SceneDocument.decode(document.encoded())
        XCTAssertEqual(decoded.document.logo, SceneLogo(storeID: logoID, placement: placement))
        XCTAssertEqual(decoded.document.encoded(), document.encoded(), "re-saved byte-identically")
        XCTAssertFalse(decoded.warnings.contains { (w: SceneIssue) -> Bool in w.path.contains("logo") }, "no warning")
        XCTAssertNil(try SceneFixtures.allKinds().logo, "scenes without a logo have none")
        XCTAssertTrue(String(decoding: document.encoded(), as: UTF8.self).contains(#""type":"logo""#))
    }

    func testPlacementIsReadLeniently() throws {
        let missing = SceneAsset(.logo(storeID: logoID))
        XCTAssertEqual(missing.logoPlacement, .default)
        let partial = SceneAsset(.logo(storeID: logoID), extra: ["placement": .object([
            "corner": .string("topRight"), "size": .string("huge"), "opacity": .double(7)])])
        XCTAssertEqual(partial.logoPlacement, LogoPlacement(corner: .topRight, opacity: 1))
        let wrongType = SceneAsset(.logo(storeID: logoID), extra: ["placement": .string("corner")])
        XCTAssertEqual(wrongType.logoPlacement, .default)
        XCTAssertNil(SceneAsset.photo(storeID: logoID).logoPlacement, "only logo assets have a placement")
    }

    func testValidationMissingPictureAndRepairReport() throws {
        let registry = try SceneFixtures.registry()
        let document = try withLogo()
        let present = FakeAvailability(photos: [SceneFixtures.photoID, logoID])
        let ok = document.validate(registry: registry, assets: present)
        XCTAssertFalse(ok.contains { (i: SceneIssue) -> Bool in i.path.contains("logo") }, "used, present: no issue (never unusedAsset)")
        let missing = document.validate(registry: registry, assets: FakeAvailability())
        XCTAssertTrue(missing.contains { (i: SceneIssue) -> Bool in i.code == .missingAsset && i.message.contains("the logo is not shown") })
        var bad = document
        bad.assets[SceneLogo.assetKey] = SceneAsset(.logo(storeID: "../logo.png"))
        XCTAssertTrue(bad.validate(registry: registry).contains { (i: SceneIssue) -> Bool in i.code == .invalidStoreID && i.isError })
        let report = SceneRepairReport(document: document, registry: registry, assets: FakeAvailability())
        XCTAssertTrue(report.entries.contains { (e: SceneRepairReport.Entry) -> Bool in e.code == "missingAsset" && e.item.contains("Logo") },
                      "analyze F1: the missing logo is in the repair report: \(report.entries)")
    }

    func testOlderAppsKeepAnUnknownLogoAssetVerbatim() throws {
        // What an app without MED-010 sees: the same JSON with a type it does not know is kept as unknown.
        let document = try withLogo()
        let text = String(decoding: document.encoded(), as: UTF8.self).replacingOccurrences(of: #""type":"logo""#, with: #""type":"futureLogo""#)
        let decoded = try SceneDocument.decode([UInt8](text.utf8))
        guard case .unknown("futureLogo")? = decoded.document.assets[SceneLogo.assetKey]?.kind else { return XCTFail("kept as unknown") }
        XCTAssertEqual(String(decoding: decoded.document.encoded(), as: UTF8.self), text, "carried verbatim")
    }
}
