// CAM-009-T04 (contract face-sources F4): the stand-in camera offers each picture it stores to the picture analyzer
// (the hook the app's face tracking uses), with the picture's rotation and camera, and the camera layer's stop resets
// the analyzer. Nothing is offered before start or after stop. Skipped without a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import CameraLayer
import CoreVideo
import Metal
import os
import XCTest

private final class CountingAnalyzer: CameraPictureAnalyzing, @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(initialState: (offers: 0, resets: 0, last: CameraPosition?.none))
    var offers: Int { state.withLock { $0.offers } }
    var resets: Int { state.withLock { $0.resets } }
    var lastPosition: CameraPosition? { state.withLock { $0.last } }

    func offer(_ pixels: CVPixelBuffer, rotation: CameraRotation, position: CameraPosition) {
        state.withLock { $0.offers += 1; $0.last = position }
    }

    func reset() { state.withLock { $0.resets += 1 } }
}

final class CameraPictureAnalyzerTests: XCTestCase {
    func testStandInOffersEachStoredPictureAndStopResets() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device") }
        let stub = StubCameraFrameProvider(device: device, scenario: .granted)
        let layer = CameraLayerSource(provider: stub)
        let analyzer = CountingAnalyzer()
        stub.pictureAnalyzer = analyzer
        stub.deliverNextPicture()
        XCTAssertEqual(analyzer.offers, 0, "nothing before the camera starts")
        layer.start()
        XCTAssertEqual(analyzer.offers, 1, "the first picture")
        stub.deliverNextPicture()
        XCTAssertEqual(analyzer.offers, 2)
        XCTAssertEqual(analyzer.lastPosition, .back)
        layer.stop()
        XCTAssertEqual(analyzer.resets, 1, "stopping the camera resets the analyzer")
        stub.deliverNextPicture()
        XCTAssertEqual(analyzer.offers, 2, "nothing after stop")
    }

    /// CAM-010-T04 (contract H4): a group behind the one slot offers each picture to every member and resets them all.
    func testGroupForwardsOffersAndResetsToEveryMember() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device") }
        let stub = StubCameraFrameProvider(device: device, scenario: .granted)
        let layer = CameraLayerSource(provider: stub)
        let face = CountingAnalyzer(), hand = CountingAnalyzer()
        stub.pictureAnalyzer = CameraPictureAnalyzerGroup([face, hand])
        layer.start()
        stub.deliverNextPicture()
        XCTAssertEqual([face.offers, hand.offers], [2, 2])
        layer.stop()
        XCTAssertEqual([face.resets, hand.resets], [1, 1])
    }
}
#endif
