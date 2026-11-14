// CAM-005-T09: the touch → focus point mapping (table-driven across rotations, crop modes, mirror, zoom
// and anchors, corners and Fit's bars), the focus control routine and focus on a running stand-in
// camera (CAM-005-R1 to R5, R8, R9, R11, R12; S1 to S4). Mapping and routine tests are plain Swift
// (every platform, the Linux shape included); the stand-in provider tests need a Metal device.
import CameraLayer
import XCTest
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Metal
#endif

final class CameraFocusTests: XCTestCase {
    // MARK: Mapping (contract C1; S1, S2)

    /// An independent reference, written from the on-screen picture rather than from
    /// `CameraPictureGeometry`: the upright picture is scaled (Fill: cover, Fit: inside, times the zoom)
    /// and placed so its anchor (0.5, anchor.y) lies on the same fraction of the rect; the touch's
    /// fraction of that drawn picture is mirrored, then turned back by the rotation into the texture.
    /// The touch is relative to the rect's origin.
    private static func expected(touchX: Double, touchY: Double, rectWidth: Double, rectHeight: Double,
                                 picture: CameraDrawnPicture, crop: CameraCrop, mirrored: Bool) -> (x: Double, y: Double)? {
        let swaps: Bool = picture.rotation == .clockwise90 || picture.rotation == .clockwise270
        let uprightW: Double = Double(swaps ? picture.height : picture.width)
        let uprightH: Double = Double(swaps ? picture.width : picture.height)
        let sx: Double = rectWidth / uprightW
        let sy: Double = rectHeight / uprightH
        let scale: Double = (crop.mode == .fill ? max(sx, sy) : min(sx, sy)) * Double(crop.zoom)
        let drawnW: Double = uprightW * scale
        let drawnH: Double = uprightH * scale
        let anchorY: Double = Double(crop.anchor.y)
        let left: Double = 0.5 * rectWidth - 0.5 * drawnW
        let top: Double = anchorY * rectHeight - anchorY * drawnH
        var a: Double = (touchX - left) / drawnW
        let b: Double = (touchY - top) / drawnH
        let tolerance: Double = 1e-6
        guard a >= -tolerance, a <= 1 + tolerance, b >= -tolerance, b <= 1 + tolerance else { return nil }
        if mirrored { a = 1 - a }
        let clampedA: Double = min(max(a, 0), 1)
        let clampedB: Double = min(max(b, 0), 1)
        switch picture.rotation {
        case .none: return (clampedA, clampedB)
        case .clockwise90: return (clampedB, 1 - clampedA)
        case .clockwise180: return (1 - clampedA, 1 - clampedB)
        case .clockwise270: return (1 - clampedB, clampedA)
        }
    }

    private struct Row {
        let name: String
        let touch: (x: Double, y: Double)
        let rect: (x: Double, y: Double, width: Double, height: Double)
        let picture: CameraDrawnPicture
        let crop: CameraCrop
        let mirrored: Bool
        let expected: (x: Double, y: Double)?
    }

    private static let sensor = CameraDrawnPicture(width: 1280, height: 720, rotation: .clockwise90)
    private static let phone: (x: Double, y: Double, width: Double, height: Double) = (0, 0, 390, 844)

    /// Hand-computed rows (portrait iPhone 390 × 844 pt, back camera 1280 × 720 turned 90°).
    private static let handRows: [Row] = [
        Row(name: "centre maps to the sensor centre", touch: (195, 422), rect: phone, picture: sensor,
            crop: .fill, mirrored: false, expected: (0.5, 0.5)),
        // Fill: drawn 474.75 × 844, left −42.375 → a = 42.375 / 474.75 = 0.089258, b = 0 → (b, 1 − a).
        Row(name: "top-left corner, Fill", touch: (0, 0), rect: phone, picture: sensor,
            crop: .fill, mirrored: false, expected: (0, 0.910742)),
        Row(name: "top-left corner, Fill, mirrored", touch: (0, 0), rect: phone, picture: sensor,
            crop: .fill, mirrored: true, expected: (0, 0.089258)),
        Row(name: "bottom-right corner, Fill", touch: (390, 844), rect: phone, picture: sensor,
            crop: .fill, mirrored: false, expected: (1, 0.089258)),
        // Fit: drawn 390 × 693.333, top 75.333: the band above is a bar.
        Row(name: "Fit top bar is ignored", touch: (195, 30), rect: phone, picture: sensor,
            crop: CameraCrop(mode: .fit, anchor: .center, zoom: 1), mirrored: false, expected: nil),
        Row(name: "Fit picture's top-left corner", touch: (0, 75.34), rect: phone, picture: sensor,
            crop: CameraCrop(mode: .fit, anchor: .center, zoom: 1), mirrored: false, expected: (0.00001, 1)),
        // Fit anchored to the top: the bar is below the picture (top 0, bottom 693.333).
        Row(name: "Fit top anchor, bottom bar is ignored", touch: (195, 800), rect: phone, picture: sensor,
            crop: CameraCrop(mode: .fit, anchor: .top, zoom: 1), mirrored: false, expected: nil),
        // Zoom 2 on Fill: drawn 949.5 × 1688; centre kept; touch at (0, 422): a = (474.75 − 195) / 949.5.
        Row(name: "Fill 2× zoom, left edge", touch: (0, 422), rect: phone, picture: sensor,
            crop: CameraCrop(mode: .fill, anchor: .center, zoom: 2), mirrored: false, expected: (0.5, 0.705371)),
        // Landscape: the picture is already upright; an offset rect (iPad split editor's output pane).
        Row(name: "landscape, offset rect, centre", touch: (500, 300), rect: (100, 75, 800, 450),
            picture: CameraDrawnPicture(width: 1280, height: 720, rotation: .none), crop: .fill, mirrored: false,
            expected: (0.5, 0.5)),
        Row(name: "outside the rect is ignored", touch: (50, 300), rect: (100, 75, 800, 450),
            picture: CameraDrawnPicture(width: 1280, height: 720, rotation: .none), crop: .fill, mirrored: false,
            expected: nil),
        Row(name: "upside-down landscape, top-left", touch: (100, 75), rect: (100, 75, 800, 450),
            picture: CameraDrawnPicture(width: 1280, height: 720, rotation: .clockwise180), crop: .fill, mirrored: false,
            expected: (1, 1)),
    ]

    private func map(_ touch: (x: Double, y: Double), rect: (x: Double, y: Double, width: Double, height: Double),
                     picture: CameraDrawnPicture, crop: CameraCrop, mirrored: Bool) -> CameraFocusPoint? {
        CameraFocusMapping.devicePoint(touchX: touch.x, touchY: touch.y, rectX: rect.x, rectY: rect.y,
                                       rectWidth: rect.width, rectHeight: rect.height, picture: picture,
                                       crop: crop, mirrored: mirrored)
    }

    func testHandComputedRows() {   // S1, S2
        for row in Self.handRows {
            let got: CameraFocusPoint? = map(row.touch, rect: row.rect, picture: row.picture, crop: row.crop, mirrored: row.mirrored)
            guard let want = row.expected else {
                XCTAssertNil(got, row.name)
                continue
            }
            guard let got else { XCTFail("\(row.name): nil"); continue }
            XCTAssertEqual(got.x, want.x, accuracy: 0.001, row.name)
            XCTAssertEqual(got.y, want.y, accuracy: 0.001, row.name)
        }
    }

    /// Every rotation × crop mode × mirror × zoom × anchor, at corners, edges and inner points, in a
    /// portrait and a landscape rect: the mapping equals the reference within 0.001, and nil exactly
    /// where the reference finds a bar (S1, S2). 4 × 2 × 2 × 3 anchors × 2 rects × 12 touches = 4,608 checks.
    func testEveryCombinationMatchesTheReference() {
        let rects: [(x: Double, y: Double, width: Double, height: Double)] = [(0, 0, 390, 844), (20, 10, 844, 390)]
        let fractions: [Double] = [0, 0.25, 0.5, 1]
        var checked = 0
        var bars = 0
        for rotation in CameraRotation.allCases {
            let picture = CameraDrawnPicture(width: 1280, height: 720, rotation: rotation)
            for mode in CameraCropMode.allCases {
                for anchor in CameraCropAnchor.allCases {
                    for zoom in CameraCrop.zoomChoices {
                        let crop = CameraCrop(mode: mode, anchor: anchor, zoom: zoom)
                        for mirrored in [false, true] {
                            for rect in rects {
                                for fx in fractions {
                                    for fy in [0.0, 0.5, 1.0] {
                                        let touch: (x: Double, y: Double) = (rect.x + fx * rect.width, rect.y + fy * rect.height)
                                        let got: CameraFocusPoint? = map(touch, rect: rect, picture: picture, crop: crop, mirrored: mirrored)
                                        let want = Self.expected(touchX: touch.x - rect.x, touchY: touch.y - rect.y, rectWidth: rect.width,
                                                                 rectHeight: rect.height, picture: picture, crop: crop, mirrored: mirrored)
                                        let label: String = "\(rotation) \(mode) \(anchor) \(zoom)× mirror \(mirrored) rect \(rect.width) touch \(fx),\(fy)"
                                        checked += 1
                                        guard let want else {
                                            bars += 1
                                            XCTAssertNil(got, label)
                                            continue
                                        }
                                        guard let got else { XCTFail("\(label): nil"); continue }
                                        XCTAssertEqual(got.x, want.x, accuracy: 0.001, label)
                                        XCTAssertEqual(got.y, want.y, accuracy: 0.001, label)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        XCTAssertEqual(checked, 4 * 2 * 3 * 4 * 2 * 2 * 4 * 3)
        XCTAssertGreaterThan(bars, 0, "Fit's bars were exercised")
    }

    func testEmptyInputsGiveNothing() {
        let picture = CameraDrawnPicture(width: 1280, height: 720, rotation: .none)
        XCTAssertNil(map((1, 1), rect: (0, 0, 0, 100), picture: picture, crop: .fill, mirrored: false))
        XCTAssertNil(map((1, 1), rect: (0, 0, 100, 100), picture: CameraDrawnPicture(width: 0, height: 720, rotation: .none),
                         crop: .fill, mirrored: false))
        XCTAssertNil(map((.nan, 1), rect: (0, 0, 100, 100), picture: picture, crop: .fill, mirrored: false))
        XCTAssertEqual(CameraFocusPoint(x: -3, y: .infinity), CameraFocusPoint(x: 0, y: 0.5), "clamped; non-finite → 0.5")
    }

    // MARK: Control routine (contract C2)

    func testFocusSetsThePointThenAutoFocusInOneConfiguration() {   // R4, R12
        let device = FakeCameraFocusDevice()
        let point = CameraFocusPoint(x: 0.2, y: 0.7)
        let state: CameraFocusState = CameraFocusControl.focus(at: point, on: device)
        XCTAssertEqual(state.point, point)
        XCTAssertEqual(state.mode, .autoFocus)
        XCTAssertEqual(device.configurations, 1)
        XCTAssertEqual(device.changesOutsideConfiguration, 0)
        CameraFocusControl.reset(device)
        XCTAssertEqual(device.currentFocusMode, .continuousAuto)
        XCTAssertEqual(device.currentFocusPoint, .centre)
        XCTAssertEqual(device.configurations, 2)
        CameraFocusControl.reset(device)
        XCTAssertEqual(device.configurations, 2, "already at rest: nothing configured")
    }

    func testContinuousFallbackWithoutSingleShotFocus() {   // R4
        let device = FakeCameraFocusDevice(modes: [.continuousAuto])
        let state: CameraFocusState = CameraFocusControl.focus(at: CameraFocusPoint(x: 0.9, y: 0.1), on: device)
        XCTAssertEqual(state.mode, .continuousAuto)
        XCTAssertEqual(state.point, CameraFocusPoint(x: 0.9, y: 0.1))
    }

    func testUnsupportedAndRefusedChangeNothing() {   // R5, S3
        let fixed = FakeCameraFocusDevice(canFocusOnPoint: false)
        XCTAssertFalse(CameraFocusControl.focus(at: CameraFocusPoint(x: 0.1, y: 0.1), on: fixed).canFocus)
        XCTAssertEqual(fixed.configurations, 0)
        let busy = FakeCameraFocusDevice()
        busy.refusesConfiguration = true
        let state: CameraFocusState = CameraFocusControl.focus(at: CameraFocusPoint(x: 0.1, y: 0.1), on: busy)
        XCTAssertEqual(state.point, .centre)
        XCTAssertEqual(state.mode, .continuousAuto)
    }

    // MARK: Stand-in provider (contract C3)

    #if canImport(Metal) && !COMPOSITOR_NO_METAL
    private func makeProvider(focusable: Set<FakeCameraKey>? = nil) throws -> StubCameraFrameProvider {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice(), "no Metal device")
        return StubCameraFrameProvider(device: device, scenario: .granted, lensInventory: FixedCameraLensInventory([.wide, .ultraWide]),
                                       focusPointCameras: focusable)
    }

    func testTapSetsTheExpectedPointAndModeOnTheRunningCamera() throws {   // US1, R1, R4, R9, R12
        let camera = try makeProvider()
        var reported: [CameraFocusState] = []
        camera.onFocusChange = { (state: CameraFocusState) -> Void in reported.append(state) }
        camera.setFocusPoint(CameraFocusPoint(x: 0.3, y: 0.6))
        XCTAssertEqual(camera.session.focusDevice(lens: .wide).configurations, 0, "idle: nothing configured")
        XCTAssertEqual(camera.focus, .notRunning(canFocus: true))
        camera.start()
        XCTAssertEqual(camera.state, .running)
        let picture = CameraDrawnPicture(width: 1280, height: 720, rotation: .clockwise90)
        let point = try XCTUnwrap(CameraFocusMapping.devicePoint(touchX: 0, touchY: 0, rectX: 0, rectY: 0, rectWidth: 390,
                                                                 rectHeight: 844, picture: picture, crop: .fill, mirrored: false))
        reported.removeAll()
        camera.setFocusPoint(point)
        let device: FakeCameraFocusDevice = camera.session.focusDevice(lens: .wide)
        XCTAssertEqual(device.currentFocusPoint, point, "the tap's point reached the camera")
        XCTAssertEqual(device.currentFocusMode, .autoFocus)
        XCTAssertEqual(camera.focus, CameraFocusState(canFocus: true, isRunning: true, mode: .autoFocus, point: point), "read back")
        XCTAssertEqual(reported.count, 1, "reported once")
        XCTAssertEqual(device.changesOutsideConfiguration, 0)
        XCTAssertEqual(camera.startCount, 1, "no restart")
        XCTAssertEqual(camera.stopCount, 0)
    }

    func testUnsupportedCameraIsNeverConfigured() throws {   // US2, R5, S3
        let camera = try makeProvider(focusable: [])
        camera.start()
        XCTAssertFalse(camera.focus.canFocus)
        camera.setFocusPoint(CameraFocusPoint(x: 0.3, y: 0.6))
        XCTAssertEqual(camera.session.focusDevice(lens: .wide).configurations, 0)
    }

    func testLensAndPositionSwitchesAndStopsResetTheFocus() throws {   // US4, R8, S4
        let camera = try makeProvider()
        camera.start()
        let point = CameraFocusPoint(x: 0.1, y: 0.2)
        camera.setFocusPoint(point)
        camera.selectLens(.ultraWide)
        XCTAssertEqual(camera.session.focusDevice(lens: .wide).currentFocusMode, .continuousAuto, "lens switch reset the wide lens")
        XCTAssertEqual(camera.session.focusDevice(lens: .wide).currentFocusPoint, .centre)
        XCTAssertEqual(camera.focus.point, .centre)
        camera.setFocusPoint(point)
        camera.select(.front)
        XCTAssertEqual(camera.session.focusDevice(lens: .ultraWide).currentFocusPoint, .centre, "position switch reset it")
        camera.setFocusPoint(point)
        camera.stop()
        XCTAssertEqual(camera.session.focusDevice(lens: .wide, position: .front).currentFocusPoint, .centre, "stop reset it")
        XCTAssertEqual(camera.focus, .notRunning(canFocus: true))
    }
    #endif
}
