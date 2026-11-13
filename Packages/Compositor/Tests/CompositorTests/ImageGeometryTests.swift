// MED-001-T05: the photo layer's CPU parts — fill and fit geometry, the stored-size rule, the error
// messages and the one-photo layer kind (MED-001-R5, R9, R11). Plain Swift: runs on the host, the
// simulator and in the Linux shape.
import Compositor
import ImageLayer
import XCTest

final class ImageGeometryTests: XCTestCase {
    private func assertClose(_ a: Float, _ b: Float, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a, b, accuracy: 1e-5, message, file: file, line: line)
    }

    func testFillCropsTheLongSideEqually() {
        let wide = ImagePictureGeometry(pictureWidth: 30, pictureHeight: 10, outputWidth: 64, outputHeight: 64, mode: .fill)
        assertClose(wide.visibleWidth, 1.0 / 3, "a third of the width is shown")
        assertClose(wide.visibleHeight, 1, "the full height")
        assertClose(wide.offsetX, 1.0 / 3, "centered")
        assertClose(wide.textureCoordinate(x: 1, y: 1).x, 2.0 / 3, "right edge")
        let tall = ImagePictureGeometry(pictureWidth: 10, pictureHeight: 40, outputWidth: 100, outputHeight: 100)
        XCTAssertEqual(tall, ImagePictureGeometry(pictureWidth: 10, pictureHeight: 40, outputWidth: 100, outputHeight: 100, mode: .fill),
                       "fill is the default")
        assertClose(tall.visibleHeight, 0.25, "a quarter of the height")
        assertClose(tall.offsetY, 0.375, "centered vertically")
    }

    func testFitLetterboxesOutsideTheImage() {
        let g = ImagePictureGeometry(pictureWidth: 30, pictureHeight: 10, outputWidth: 64, outputHeight: 64, mode: .fit)
        assertClose(g.visibleWidth, 1, "the full width")
        assertClose(g.visibleHeight, 3, "three image heights fill the output")
        assertClose(g.offsetY, -1, "a bar above")
        XCTAssertLessThan(g.textureCoordinate(x: 0.5, y: 0.1).y, 0, "the top bar is outside the image")
        let middle = g.textureCoordinate(x: 0.5, y: 0.5)
        assertClose(middle.x, 0.5, "middle x")
        assertClose(middle.y, 0.5, "middle y")
    }

    func testSameAspectAndDegenerateSizesAreTheIdentity() {
        XCTAssertEqual(ImagePictureGeometry(pictureWidth: 32, pictureHeight: 16, outputWidth: 64, outputHeight: 32), .identity)
        XCTAssertEqual(ImagePictureGeometry(pictureWidth: 32, pictureHeight: 16, outputWidth: 64, outputHeight: 32, mode: .fit), .identity)
        XCTAssertEqual(ImagePictureGeometry(pictureWidth: 0, pictureHeight: 16, outputWidth: 64, outputHeight: 32), .identity)
        XCTAssertEqual(ImagePictureGeometry(pictureWidth: 8, pictureHeight: 8, outputWidth: 64, outputHeight: -1), .identity)
    }

    func testStoredSizeScalesDownOnlyAndKeepsTheAspect() {
        let limits = ImageImportLimits.standard
        XCTAssertEqual(limits.maxFileBytes, 40 * 1024 * 1024)
        XCTAssertEqual(limits.maxPixelCount, 100_000_000)
        XCTAssertEqual(limits.maxStoredLongestSide, 4096)
        XCTAssertTrue(limits.storedSize(width: 5000, height: 100) == (4096, 82), "a wide panorama is scaled to 4096")
        XCTAssertTrue(limits.storedSize(width: 3000, height: 8192) == (1500, 4096))
        XCTAssertTrue(limits.storedSize(width: 64, height: 48) == (64, 48), "never scaled up")
    }

    func testEveryErrorHasAPlainMessage() {
        let errors: [ImageImportError] = [.notAnImage, .tooLarge, .tooManyPixels, .damaged, .unreadable, .saveFailed]
        XCTAssertEqual(Set(errors.map(\.message)).count, errors.count, "distinct messages")
        XCTAssertTrue(errors.allSatisfy { !$0.message.isEmpty && $0.message.hasSuffix(".") })
    }

    func testOnePhotoPerStack() throws {
        var stack = LayerStack()
        let id = try stack.add(LayerDescriptor(kind: .photo))
        XCTAssertThrowsError(try stack.add(LayerDescriptor(kind: .photo)), "a second photo is refused")
        XCTAssertThrowsError(try stack.duplicate(id), "duplicating the photo is refused")
        XCTAssertEqual(stack.entries.count, 1)
    }
}
