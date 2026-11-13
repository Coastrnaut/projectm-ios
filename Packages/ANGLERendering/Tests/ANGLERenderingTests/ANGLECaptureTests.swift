// ANGLECaptureTests.swift — REC-001-T10: projectM's frame capture through ANGLE (research
// REC-001-D1). iOS Simulator through ANGLE's Metal backend; simulator results are never device evidence.
import XCTest
@testable import ANGLERendering

@MainActor
final class ANGLECaptureTests: XCTestCase {
    /// The capture is the frame rendered after the request, at the surface's pixel size, read before
    /// the swap (equal to a read-back of the same unpresented frame), and only one frame is captured.
    func testCaptureIsTheNextFrameAtTheSurfaceSize() throws {
        let renderer = try ANGLERenderer.make()
        renderer.view.frame = CGRect(x: 0, y: 0, width: 24, height: 16)
        renderer.view.layoutIfNeeded()
        let size = renderer.currentSurfaceSize
        XCTAssertGreaterThan(size.width, 0)
        var captured: [ANGLECapturedFrame?] = []
        renderer.captureNextFrame { (frame: ANGLECapturedFrame?) in captured.append(frame) }
        XCTAssertTrue(renderer.hasPendingFrameCapture)
        XCTAssertTrue(renderer.renderFrame(present: false))
        XCTAssertEqual(captured.count, 1)
        let frame = try XCTUnwrap(captured.first ?? nil)
        XCTAssertEqual(frame.width, size.width)
        XCTAssertEqual(frame.height, size.height)
        XCTAssertEqual(frame.rgbaBottomUp.count, size.width * size.height * 4)
        XCTAssertEqual(frame.rgbaBottomUp, renderer.readPixels(), "the unpresented frame's own pixels")
        XCTAssertFalse(renderer.hasPendingFrameCapture)
        XCTAssertTrue(renderer.renderFrame(present: false))
        XCTAssertEqual(captured.count, 1, "one request, one frame")
    }

    /// Presentation loss cancels a pending capture (REC-001-R14); a replaced request gets nil.
    func testSuspensionAndReplacementGiveNil() throws {
        let renderer = try ANGLERenderer.make()
        renderer.view.frame = CGRect(x: 0, y: 0, width: 8, height: 8)
        renderer.view.layoutIfNeeded()
        var results: [Bool] = []
        renderer.captureNextFrame { (frame: ANGLECapturedFrame?) in results.append(frame != nil) }
        renderer.captureNextFrame { (frame: ANGLECapturedFrame?) in results.append(frame != nil) }
        XCTAssertEqual(results, [false])
        renderer.suspendForPresentationLoss()
        XCTAssertEqual(results, [false, false])
        XCTAssertFalse(renderer.hasPendingFrameCapture)
    }
}
