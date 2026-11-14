// CameraFocusAppTests.swift — CAM-005-T13: the host maps a window point to the camera point and focuses
// the stand-in camera; bars and unsupported cameras change nothing; switches reset; the feedback ring
// and notes (CAM-005-R1 to R9). Simulator results are never device evidence. Host tests need a Metal
// device and skip without one.
import CameraLayer
import LibraryBackup
import Metal
import XCTest
@testable import projectM_iOS

@MainActor
final class CameraFocusAppTests: XCTestCase {
    func testNotesAndNoStoredKey() {   // R5, R9
        XCTAssertEqual(CameraFocusNote.text(canFocus: false), "This camera can't focus on a point.")
        XCTAssertEqual(CameraFocusNote.text(canFocus: true), "Double-tap the picture to focus there.")
        let keys: [String] = AppSettings.allKeys + Array(LibrarySettingsPolicy.includedKeys)
        XCTAssertFalse(keys.contains { (key: String) -> Bool in key.lowercased().contains("focus") })
    }

    func testRingShowsForOneSecondAndASecondTapRestartsIt() {   // R6
        var pending: [(Double, @MainActor () -> Void)] = []
        let feedback = CameraFocusFeedback(schedule: { (delay: Double, action: @escaping @MainActor () -> Void) -> Void in
            pending.append((delay, action))
        })
        feedback.showRing(at: CGPoint(x: 10, y: 20))
        feedback.showRing(at: CGPoint(x: 30, y: 40))
        XCTAssertEqual(pending.map { $0.0 }, [1.0, 1.0])
        pending[0].1()
        XCTAssertEqual(feedback.ring?.location, CGPoint(x: 30, y: 40), "the first tap's timer does not hide the second ring")
        pending[1].1()
        XCTAssertNil(feedback.ring)
    }

    private func makeHost(focusable: Set<FakeCameraKey>?) throws -> (CameraVisualHost, StubCameraFrameProvider) {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("No Metal device in this simulator") }
        let inventory = FixedCameraLensInventory([.wide, .ultraWide])
        var stub: StubCameraFrameProvider?
        let host = try CameraVisualHost.make(device: device, reader: nil, barCount: .b32, lenses: inventory) {
            (device: MTLDevice) -> any CameraFrameProvider in
            let made = StubCameraFrameProvider(device: device, scenario: .granted, lensInventory: inventory, focusPointCameras: focusable)
            stub = made
            return made
        }
        return (host, try XCTUnwrap(stub))
    }

    private let rect = CGRect(x: 0, y: 0, width: 390, height: 844)
    private let picture = CameraDrawnPicture(width: 1280, height: 720, rotation: .clockwise90)

    /// US1, R1, R2, R4, R9: a tap focuses the running camera at the mapped point with single-shot
    /// autofocus; Fit's bars and a stopped camera change nothing; the frame loop and camera keep running.
    func testHostFocusesAtTheMappedPoint() throws {
        let (host, camera) = try makeHost(focusable: nil)
        XCTAssertEqual(host.focus(at: CGPoint(x: 0, y: 0), pictureRect: rect, picture: picture), .notRunning)
        host.resume()
        defer { host.pause() }
        let expected = try XCTUnwrap(CameraFocusMapping.devicePoint(touchX: 0, touchY: 0, rectX: 0, rectY: 0, rectWidth: 390,
                                                                    rectHeight: 844, picture: picture, crop: .fill, mirrored: false))
        XCTAssertEqual(expected.x, 0, accuracy: 0.001)
        XCTAssertEqual(expected.y, 0.9107, accuracy: 0.001)
        XCTAssertEqual(host.focus(at: CGPoint(x: 0, y: 0), pictureRect: rect, picture: picture), .focused(expected))
        let device: FakeCameraFocusDevice = camera.session.focusDevice(lens: .wide)
        XCTAssertEqual(device.currentFocusPoint, expected)
        XCTAssertEqual(device.currentFocusMode, .autoFocus)
        XCTAssertEqual(host.cameraFocus.point, expected, "read back")
        host.mirrored = true
        let mirroredOutcome: CameraFocusTapOutcome = host.focus(at: CGPoint(x: 0, y: 0), pictureRect: rect, picture: picture)
        XCTAssertEqual(mirroredOutcome, .focused(CameraFocusPoint(x: 0, y: 1 - expected.y)), "the mirror is followed")
        host.mirrored = false
        host.crop = CameraCrop(mode: .fit, anchor: .center, zoom: 1)
        let configurations: Int = device.configurations
        XCTAssertEqual(host.focus(at: CGPoint(x: 195, y: 30), pictureRect: rect, picture: picture), .outsidePicture, "Fit's bar")
        XCTAssertEqual(host.focus(at: CGPoint(x: 195, y: 30), pictureRect: rect, picture: nil), .outsidePicture, "no picture yet")
        XCTAssertEqual(device.configurations, configurations, "nothing configured")
        XCTAssertTrue(host.isRunning)
        XCTAssertEqual(camera.startCount, 1, "no restart")
        host.cameraLens = .ultraWide
        XCTAssertEqual(device.currentFocusPoint, .centre, "the lens switch reset the previous camera")
        XCTAssertEqual(device.currentFocusMode, .continuousAuto)
    }

    /// US2, R5: an unsupported camera is never configured.
    func testUnsupportedCameraIsNeverConfigured() throws {
        let (host, camera) = try makeHost(focusable: [])
        host.resume()
        defer { host.pause() }
        XCTAssertEqual(host.focus(at: CGPoint(x: 195, y: 422), pictureRect: rect, picture: picture), .unsupported)
        XCTAssertEqual(camera.session.focusDevice(lens: .wide).configurations, 0)
    }
}
