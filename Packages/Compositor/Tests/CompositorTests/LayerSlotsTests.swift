// CMP-001-T04: per-layer picture bookkeeping (CMP-001-R6 to R8; data-model.md "LayerSlots
// transitions"). CPU only; every host.
import XCTest
@testable import Compositor

final class LayerSlotsTests: XCTestCase {
    func testPictureCountFollowsTheFallback() {
        XCTAssertEqual(LayerSlots(fallback: .transparent).pictureCount, 1)
        XCTAssertEqual(LayerSlots(fallback: .lastGoodFrame).pictureCount, 2)
    }

    func testSuccessFlipsTheRenderPictureWithTwoPictures() {
        var s = LayerSlots(fallback: .lastGoodFrame)
        s.prepared(ok: true)
        XCTAssertEqual(s.renderIndex, 0)
        XCTAssertEqual(s.frameSucceeded(), 0)   // shown picture
        XCTAssertEqual(s.lastGoodIndex, 0)
        XCTAssertEqual(s.renderIndex, 1)
        XCTAssertEqual(s.frameSucceeded(), 1)
        XCTAssertEqual(s.renderIndex, 0)
    }

    func testOnePictureNeverFlips() {
        var s = LayerSlots(fallback: .transparent)
        s.prepared(ok: true)
        XCTAssertEqual(s.frameSucceeded(), 0)
        XCTAssertEqual(s.renderIndex, 0)
    }

    func testTransparentFailureShowsNothing() {
        var s = LayerSlots(fallback: .transparent)
        s.prepared(ok: true)
        _ = s.frameSucceeded()
        XCTAssertNil(s.frameFailed())
        XCTAssertEqual(s.renderIndex, 0)
    }

    func testLastGoodFailureShowsTheLastGoodAndNeverRendersIntoIt() {
        var s = LayerSlots(fallback: .lastGoodFrame)
        s.prepared(ok: true)
        XCTAssertNil(s.frameFailed(), "no good frame yet: nothing")
        XCTAssertEqual(s.frameSucceeded(), 0)
        for _ in 0..<3 {
            XCTAssertEqual(s.frameFailed(), 0)
            XCTAssertNotEqual(s.renderIndex, s.lastGoodIndex)
        }
        XCTAssertEqual(s.frameSucceeded(), 1)
        XCTAssertEqual(s.frameFailed(), 1)
        XCTAssertEqual(s.renderIndex, 0)
    }

    func testPrepareFailureMakesTheLayerUnavailableUntilRetryOrResize() {
        var s = LayerSlots(fallback: .lastGoodFrame)
        s.prepared(ok: false)
        XCTAssertFalse(s.isAvailable)
        s.prepared(ok: true)
        XCTAssertTrue(s.isAvailable)
    }

    func testResizeForgetsTheLastGood() {
        var s = LayerSlots(fallback: .lastGoodFrame)
        s.prepared(ok: true)
        _ = s.frameSucceeded()
        s.prepared(ok: true)   // a new size
        XCTAssertNil(s.lastGoodIndex)
        XCTAssertEqual(s.renderIndex, 0)
        XCTAssertNil(s.frameFailed())
    }
}
