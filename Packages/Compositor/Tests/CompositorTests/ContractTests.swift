// CMP-001-T04: the fixed parts of the contract (CMP-001-R2, R7, R11; research CMP-001-D2, D7).
// CPU only; every host.
import XCTest
@testable import Compositor

final class ContractTests: XCTestCase {
    func testPictureDescriptorFixedValues() throws {
        let d = try XCTUnwrap(LayerPictureDescriptor(width: 64, height: 32))
        XCTAssertEqual(d.width, 64)
        XCTAssertEqual(d.height, 32)
        XCTAssertEqual(d.format, .rgba16Float)
        XCTAssertEqual(d.colorSpace, .linearSRGB)
        XCTAssertEqual(d.alpha, .premultiplied)
        XCTAssertEqual(d.origin, .topLeft)
        XCTAssertEqual(d, LayerPictureDescriptor(width: 64, height: 32))
        XCTAssertNotEqual(d, LayerPictureDescriptor(width: 32, height: 64))
        XCTAssertNil(LayerPictureDescriptor(width: 0, height: 32))
        XCTAssertNil(LayerPictureDescriptor(width: 64, height: -1))
    }

    func testOnlyIdentityCompositeSettingsAreSupported() {
        XCTAssertTrue(LayerCompositeSettings().isSupportedByCMP001)
        XCTAssertEqual(LayerCompositeSettings().opacity, 1)
        XCTAssertEqual(LayerCompositeSettings().blendMode, .normal)
        XCTAssertEqual(LayerCompositeSettings().transform, .identity)
        XCTAssertFalse(LayerCompositeSettings(opacity: 0.5).isSupportedByCMP001)
        XCTAssertFalse(LayerCompositeSettings(transform: LayerTransform(a: 2, b: 0, c: 0, d: 1, tx: 0, ty: 0)).isSupportedByCMP001)
        XCTAssertEqual(LayerCompositeSettings(opacity: 3).opacity, 1, "opacity is clamped to 0…1")
        XCTAssertEqual(LayerCompositeSettings(opacity: .nan).opacity, 1, "non-finite opacity reads 1")
    }

    func testOutcomes() {
        XCTAssertEqual(LayerOutcome.notRendered, .notRendered)
        XCTAssertNotEqual(LayerOutcome.fallbackTransparent(.frameSkipped), .fallbackLastGood(.frameSkipped))
        XCTAssertEqual(LayerOutcome.unavailable(.resourceUnavailable("x")), .unavailable(.resourceUnavailable("x")))
        XCTAssertTrue(LayerOutcome.rendered.isShown)
        XCTAssertFalse(LayerOutcome.fallbackTransparent(.notReady).isShown)
    }
}
