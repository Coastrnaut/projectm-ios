// SceneMediaReferenceTests.swift — MED-013-T05 (contract L3): listing a scene's media references and
// replacing one identifier across the photo, slideshow, logo and video roles, keeping everything else.
import Compositor
import ImageLayer
import XCTest
@testable import SceneFormat

final class SceneMediaReferenceTests: XCTestCase {
    private let p = "11111111-1111-4111-8111-111111111111"
    private let q = "22222222-2222-4222-8222-222222222222"
    private let other = "33333333-3333-4333-8333-333333333333"
    private let video = "44444444-4444-4444-8444-444444444444"

    private func scene() -> SceneDocument {
        var photo = SceneAsset.photo(storeID: p)
        photo.photoSlideshow = SceneSlideshow(enabled: true, storeIDs: [other, p, p], mode: "time", seconds: 5, beats: 4)
        photo.extra["future"] = .string("kept")
        let logo = SceneAsset.logo(storeID: p, placement: .default)
        return SceneDocument(id: "5CE7E000-0000-4000-8000-000000000001", name: "A",
                             layers: [SceneLayer(instance: 1, content: .photo(asset: "photo")), SceneLayer(instance: 2, content: .video(asset: "video"))],
                             assets: ["photo": photo, "logo": logo, "video": .video(storeID: video)])
    }

    func testReferencesListEveryRoleInKeyOrder() {
        let refs = scene().mediaReferences
        XCTAssertEqual(refs.map(\.role), [.logo, .photo, .slide, .slide, .slide, .video])
        XCTAssertEqual(scene().mediaIDs(in: .photos), [p, other])
        XCTAssertEqual(scene().mediaIDs(in: .videos), [video])
    }

    func testReplacingAPhotoRewritesThePhotoTheSlidesAndTheLogoAndKeepsTheRest() throws {
        let original = scene()
        let (rewritten, count) = original.replacingMediaReference(store: .photos, from: p, to: q)
        XCTAssertEqual(count, 4, "photo, two slides, logo")
        XCTAssertFalse(rewritten.mediaReferences.contains { (r: SceneMediaReference) -> Bool in r.storeID == p })
        XCTAssertEqual(rewritten.assets["photo"]?.photoSlideshow?.storeIDs, [other, q, q])
        XCTAssertEqual(rewritten.assets["photo"]?.photoSlideshow?.seconds, 5)
        XCTAssertEqual(rewritten.assets["photo"]?.extra["future"], .string("kept"))
        XCTAssertEqual(rewritten.assets["logo"]?.logoPlacement, original.assets["logo"]?.logoPlacement)
        XCTAssertEqual(rewritten.assets["video"], original.assets["video"])
        XCTAssertEqual(rewritten.layers, original.layers)
        XCTAssertEqual(rewritten.id, original.id)
        // The rewrite survives encoding and decoding.
        let decoded = try SceneDocument.decode(rewritten.encoded()).document
        XCTAssertEqual(decoded.mediaIDs(in: .photos), [q, other])
    }

    func testAPhotoIdentifierIsNotReplacedInTheVideoStoreAndViceVersa() {
        let original = scene()
        XCTAssertEqual(original.replacingMediaReference(store: .videos, from: p, to: q).replaced, 0)
        let (rewritten, count) = original.replacingMediaReference(store: .videos, from: video, to: q)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(rewritten.mediaIDs(in: .videos), [q])
        XCTAssertEqual(rewritten.mediaIDs(in: .photos), original.mediaIDs(in: .photos))
        XCTAssertEqual(original.replacingMediaReference(store: .photos, from: "55555555-5555-4555-8555-555555555555", to: q).document, original)
    }
}
