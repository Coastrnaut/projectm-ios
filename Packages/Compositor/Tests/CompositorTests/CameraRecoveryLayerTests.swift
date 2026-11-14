// CAM-013-T08: every stop reason clears the composite on the next frame and the camera's return
// brings the picture back (CAM-013-R1, S1, S2), through the real Metal compositor with the stand-in
// camera. Own file, away from CMP-006's Compositor edits. Skipped without a Metal device.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import CameraLayer
import Compositor
import Metal
import XCTest

final class CameraRecoveryLayerTests: XCTestCase {
    private let red = StubCameraFrameProvider.Color(red: 255, green: 0, blue: 0)

    func testEveryReasonClearsTheNextFrameAndTheReturnRestoresIt() throws {
        let rig = try GPURig()
        let output = try rig.output()
        var time: UInt64 = 1
        for reason in CameraStopReason.allCases {
            let stub = StubCameraFrameProvider(device: rig.device, scenario: .granted, pattern: .solid(red))
            let layer = CameraLayerSource(provider: stub)
            let compositor = try Compositor(device: rig.device, layers: [layer])
            layer.start()
            try rig.frame(compositor, into: output, time: time)
            time += 16_666_667
            assertAll(try rig.read(output), equal: Pixel(1, 0, 0, 1), "\(reason): camera pixels before")

            if reason.isInterruption { stub.interrupt(reason) } else { stub.fail(reason) }
            XCTAssertEqual(stub.state, reason.feedState, "\(reason)")
            XCTAssertEqual(stub.stopReason, reason, "\(reason)")
            XCTAssertNil(stub.latestFrame(), "\(reason): the picture is dropped")
            try rig.frame(compositor, into: output, time: time)
            time += 16_666_667
            XCTAssertEqual(compositor.outcome(ofLayer: 0), .fallbackTransparent(.notReady), "\(reason): the next frame falls back")
            assertAll(try rig.read(output), equal: .zero, "\(reason): zero camera pixels (S1)")
            let shownWhileStopped: Int = layer.framesShown

            if reason.resumesWhenEnded {
                stub.endInterruption()
            } else {
                layer.stop()   // a Retry: stop, then start
                layer.start()
            }
            XCTAssertEqual(stub.state, .running, "\(reason)")
            XCTAssertNil(stub.stopReason, "\(reason): no reason while running")
            try rig.frame(compositor, into: output, time: time)
            time += 16_666_667
            XCTAssertEqual(compositor.outcome(ofLayer: 0), .rendered, "\(reason)")
            assertAll(try rig.read(output), equal: Pixel(1, 0, 0, 1), "\(reason): camera pixels on the first frame back (S2)")
            XCTAssertEqual(layer.framesShown, shownWhileStopped + 1)
        }
    }

    func testWithdrawnAccessIsSeenAtTheNextStart() throws {
        let rig = try GPURig()
        let stub = StubCameraFrameProvider(device: rig.device, scenario: .granted, pattern: .solid(red))
        let layer = CameraLayerSource(provider: stub)
        let compositor = try Compositor(device: rig.device, layers: [layer])
        layer.start()
        stub.interrupt(.anotherApp)
        stub.withdrawAccess()
        XCTAssertEqual(stub.state, .interrupted, "nothing changes until the next start")
        layer.stop()
        layer.start()
        XCTAssertEqual(stub.state, .denied)
        XCTAssertNil(stub.stopReason)
        XCTAssertFalse(stub.state.offersRetry)
        let output = try rig.output()
        try rig.frame(compositor, into: output, time: 1)
        assertAll(try rig.read(output), equal: .zero, "denied: nothing of the camera")
    }

    func testCameraSwitchClearsTheReason() throws {
        let rig = try GPURig()
        let stub = StubCameraFrameProvider(device: rig.device, scenario: .granted)
        stub.start()
        stub.fail(.runtimeError)
        XCTAssertEqual(stub.stopReason, .runtimeError)
        stub.select(.front)
        XCTAssertEqual(stub.state, .running, "a switch starts the new camera at once")
        XCTAssertNil(stub.stopReason)
        stub.interrupt(.runtimeError)
        XCTAssertEqual(stub.state, .running, "an error kind is not an interruption")
        stub.fail(.anotherApp)
        XCTAssertEqual(stub.state, .running, "an interruption kind is not an error")
    }
}
#endif
