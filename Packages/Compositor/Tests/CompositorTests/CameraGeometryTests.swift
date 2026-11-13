// CAM-001-T05: the camera layer's CPU parts — aspect fill, rotation and the feed states' notices
// (CAM-001-R2, R5, R6, R8, R14). Plain Swift: runs on the host, the simulator and in the Linux shape.
import CameraLayer
import XCTest

final class CameraGeometryTests: XCTestCase {
    private func assertClose(_ a: Float, _ b: Float, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a, b, accuracy: 1e-5, message, file: file, line: line)
    }

    func testWidePictureInSquareOutputCropsTheSidesEqually() {
        let g = CameraPictureGeometry(pictureWidth: 30, pictureHeight: 10, rotation: .none, outputWidth: 64, outputHeight: 64)
        assertClose(g.visibleWidth, 1.0 / 3, "a third of the width is shown")
        assertClose(g.visibleHeight, 1, "the full height")
        assertClose(g.offsetX, 1.0 / 3, "centered")
        assertClose(g.offsetY, 0, "no vertical crop")
        let left = g.textureCoordinate(x: 0, y: 0), right = g.textureCoordinate(x: 1, y: 1)
        assertClose(left.x, 1.0 / 3, "left edge")
        assertClose(right.x, 2.0 / 3, "right edge")
    }

    func testTallPictureInWideOutputCropsTopAndBottom() {
        let g = CameraPictureGeometry(pictureWidth: 720, pictureHeight: 1280, rotation: .none, outputWidth: 1920, outputHeight: 1080)
        assertClose(g.visibleWidth, 1, "full width")
        assertClose(g.visibleHeight, Float((1080.0 / 1920.0) * (720.0 / 1280.0)), "height fraction")
        assertClose(g.offsetY, (1 - g.visibleHeight) / 2, "centered")
    }

    func testMatchingAspectShowsEverything() {
        let g = CameraPictureGeometry(pictureWidth: 1280, pictureHeight: 720, rotation: .none, outputWidth: 640, outputHeight: 360)
        XCTAssertEqual(g, .identity)
    }

    func testQuarterTurnSwapsTheAxesAndMapsCorners() {
        // A landscape sensor picture shown in a portrait output: upright it is portrait, so it fills
        // exactly (1280 × 720 turned is 720 × 1280 = 9:16).
        let g = CameraPictureGeometry(pictureWidth: 1280, pictureHeight: 720, rotation: .clockwise90, outputWidth: 900, outputHeight: 1600)
        assertClose(g.visibleWidth, 1, "w"); assertClose(g.visibleHeight, 1, "h")
        // Turning clockwise puts the texture's top-left at the output's top-right.
        let topRight = g.textureCoordinate(x: 1, y: 0)
        assertClose(topRight.x, 0, "x"); assertClose(topRight.y, 0, "y")
        let r180 = CameraPictureGeometry.identity.with(.clockwise180).textureCoordinate(x: 0, y: 0)
        assertClose(r180.x, 1, "180 x"); assertClose(r180.y, 1, "180 y")
        let r270 = CameraPictureGeometry.identity.with(.clockwise270).textureCoordinate(x: 0, y: 0)
        assertClose(r270.x, 1, "270 x"); assertClose(r270.y, 0, "270 y")
    }

    func testDegenerateSizesGiveTheIdentity() {
        for (pw, ph, ow, oh) in [(0, 10, 64, 64), (10, -1, 64, 64), (10, 10, 0, 64), (10, 10, 64, 0)] {
            let g = CameraPictureGeometry(pictureWidth: pw, pictureHeight: ph, rotation: .clockwise90, outputWidth: ow, outputHeight: oh)
            XCTAssertEqual(g, CameraPictureGeometry.identity.with(.clockwise90), "\(pw)×\(ph) → \(ow)×\(oh)")
        }
    }

    func testRotationFromDegrees() {
        XCTAssertEqual(CameraRotation(degrees: 0), .none)
        XCTAssertEqual(CameraRotation(degrees: 90), .clockwise90)
        XCTAssertEqual(CameraRotation(degrees: 180), .clockwise180)
        XCTAssertEqual(CameraRotation(degrees: 270), .clockwise270)
        XCTAssertEqual(CameraRotation(degrees: -90), .clockwise270)
        XCTAssertEqual(CameraRotation(degrees: 450), .clockwise90)
        XCTAssertEqual(CameraRotation(degrees: .nan), .none)
    }

    // MARK: - Feed states (CAM-001-R5, R6, R8, R14)

    func testOnlyRunningShowsPictures() {
        let all: [CameraFeedState] = [.idle, .requestingAccess, .starting, .running, .denied, .restricted, .unavailable, .interrupted, .failed]
        XCTAssertEqual(all.filter(\.showsPicture), [.running])
        XCTAssertEqual(all.filter(\.offersSettings), [.denied, .restricted])
        XCTAssertEqual(all.filter { $0.notice != nil }, [.denied, .restricted, .unavailable, .interrupted, .failed])
    }

    func testNoticesAndAccessibilityValues() {
        XCTAssertEqual(CameraFeedState.denied.notice, "Camera access is off. To show the camera, allow it in Settings.")
        XCTAssertEqual(CameraFeedState.unavailable.notice, "No rear camera is available. Showing the spectrum only.")
        XCTAssertEqual(CameraFeedState.interrupted.notice, CameraFeedState.failed.notice)
        XCTAssertEqual(CameraFeedState.running.accessibilityValue, "Live")
        XCTAssertEqual(CameraFeedState.denied.accessibilityValue, "Camera access off")
        XCTAssertEqual(CameraFeedState.unavailable.accessibilityValue, "No rear camera")
        XCTAssertEqual(CameraFeedState.interrupted.accessibilityValue, "Paused by the system")
        XCTAssertEqual(CameraScenario(rawValue: "denied"), .denied)
        XCTAssertNil(CameraScenario(rawValue: "front"))
    }
}

private extension CameraPictureGeometry {
    func with(_ rotation: CameraRotation) -> CameraPictureGeometry {
        var g = self
        g.rotation = rotation
        return g
    }
}
