// CMP-013-T03: the plain-Swift render cache model (CMP-013-R1 to R4, R6, R12; data-model.md). CPU only:
// runs on every host and in the Linux shape.
import Compositor
import XCTest

final class RenderCacheModelTests: XCTestCase {
    private let picture = LayerPictureDescriptor(width: 64, height: 32)!

    private func key(_ d: LayerRenderDependencies?, picture p: LayerPictureDescriptor? = nil, scale: Double = 2,
                     reduce: Bool = false, epoch: UInt64 = 0) -> LayerRenderCacheKey? {
        LayerRenderCacheKey(dependencies: d, picture: p ?? picture, contentScale: scale, reduceFlashing: reduce, epoch: epoch)
    }

    func testOnlyALayerWithoutPerFrameDependenciesIsCacheable() {
        XCTAssertTrue(LayerRenderDependencies.still(content: 3).isCacheable)
        XCTAssertFalse(LayerRenderDependencies(time: true).isCacheable, "time")
        XCTAssertFalse(LayerRenderDependencies(audio: true).isCacheable, "audio")
        XCTAssertFalse(LayerRenderDependencies(modulation: true).isCacheable, "modulation")
        XCTAssertFalse(LayerRenderDependencies(externalInput: true).isCacheable, "external input")
        XCTAssertFalse(LayerRenderDependencies.dynamic.isCacheable)
    }

    func testUndeclaredAndDynamicLayersHaveNoKey() {
        XCTAssertNil(key(nil), "unknown means render")
        XCTAssertNil(key(.dynamic))
        XCTAssertNil(key(LayerRenderDependencies(time: true, contentGeneration: 1)))
        XCTAssertNotNil(key(.still(content: 1)))
    }

    func testTheKeyChangesWithEveryInput() throws {
        let base = try XCTUnwrap(key(.still(content: 1, parameters: 1)))
        XCTAssertEqual(key(.still(content: 1, parameters: 1)), base, "same inputs, same key")
        let other = try XCTUnwrap(LayerPictureDescriptor(width: 65, height: 32))
        let variants: [(String, LayerRenderCacheKey?)] = [
            ("content", key(.still(content: 2, parameters: 1))),
            ("parameters", key(.still(content: 1, parameters: 2))),
            ("picture size", key(.still(content: 1, parameters: 1), picture: other)),
            ("content scale", key(.still(content: 1, parameters: 1), scale: 3)),
            ("Reduce flashing", key(.still(content: 1, parameters: 1), reduce: true)),
            ("epoch", key(.still(content: 1, parameters: 1), epoch: 1)),
        ]
        for (name, variant) in variants {
            XCTAssertNotNil(variant, name)
            XCTAssertNotEqual(variant, base, "\(name) invalidates")
        }
    }

    func testTheEntryReusesOnlyAMatchingKeyWithAGoodPicture() throws {
        let k = try XCTUnwrap(key(.still(content: 1)))
        var entry = LayerRenderCacheEntry()
        XCTAssertFalse(entry.canReuse(k, hasGoodPicture: true), "nothing stored yet")
        entry.rendered(k)
        XCTAssertTrue(entry.canReuse(k, hasGoodPicture: true))
        XCTAssertFalse(entry.canReuse(k, hasGoodPicture: false), "no good picture (prepared again)")
        XCTAssertFalse(entry.canReuse(nil, hasGoodPicture: true), "undeclared this frame")
        XCTAssertFalse(entry.canReuse(key(.still(content: 2)), hasGoodPicture: true), "changed key")
        entry.drop()
        XCTAssertNil(entry.key)
        XCTAssertFalse(entry.canReuse(k, hasGoodPicture: true), "dropped")
        entry.rendered(nil)
        XCTAssertNil(entry.key, "a render without a key stores nothing")
    }

    func testTheDrawInputRule() {
        let drawn = LayerDrawInput(picture: 0, opacity: 0.5, reused: true)
        XCTAssertFalse(drawn.isUnchanged(from: nil), "no previous frame")
        XCTAssertTrue(drawn.isUnchanged(from: LayerDrawInput(picture: 0, opacity: 0.5, reused: false)),
                      "the same picture reused with the same opacity")
        XCTAssertFalse(LayerDrawInput(picture: 0, opacity: 0.5, reused: false).isUnchanged(from: drawn), "rendered again")
        XCTAssertFalse(LayerDrawInput(picture: 1, opacity: 0.5, reused: true).isUnchanged(from: drawn), "another picture")
        XCTAssertFalse(LayerDrawInput(picture: 0, opacity: 0.6, reused: true).isUnchanged(from: drawn), "opacity moved")
        let hidden = LayerDrawInput(picture: -1, opacity: 0, reused: false)
        XCTAssertTrue(hidden.isUnchanged(from: LayerDrawInput(picture: -1, opacity: 1, reused: false)), "not drawn in both")
        XCTAssertFalse(hidden.isUnchanged(from: drawn), "disappeared")
        XCTAssertFalse(drawn.isUnchanged(from: hidden), "appeared")
    }
}
