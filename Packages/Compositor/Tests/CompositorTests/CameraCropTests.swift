// CAM-007-T04: the crop geometry on the CPU (CAM-007-R1 to R3, R9; S1, S3). Plain Swift: runs on the
// host, the simulator and in the Linux shape (-DCOMPOSITOR_NO_METAL -DVISUAL_NO_METAL
// -DANALYSIS_NO_ACCELERATE). Arithmetic in typed steps (type-checker budget on Linux and Xcode 26).
import CameraLayer
import XCTest

/// One case of the table.
private struct CropCase {
    let pictureWidth: Int
    let pictureHeight: Int
    let rotation: CameraRotation
    let mirrored: Bool
    let outputWidth: Int
    let outputHeight: Int
    let crop: CameraCrop

    var label: String {
        let size: String = "\(pictureWidth)x\(pictureHeight)"
        let out: String = "\(outputWidth)x\(outputHeight)"
        let choice: String = "\(crop.mode.rawValue)/\(crop.anchor.rawValue)/\(crop.zoom)"
        return size + " r" + String(rotation.rawValue) + (mirrored ? " mirrored" : "") + " → " + out + " " + choice
    }

    var geometry: CameraPictureGeometry {
        CameraPictureGeometry(pictureWidth: pictureWidth, pictureHeight: pictureHeight, rotation: rotation,
                              outputWidth: outputWidth, outputHeight: outputHeight, mirrored: mirrored, crop: crop)
    }

    var uprightWidth: Double { Double(rotation.swapsAxes ? pictureHeight : pictureWidth) }
    var uprightHeight: Double { Double(rotation.swapsAxes ? pictureWidth : pictureHeight) }

    /// Output pixels per upright picture pixel, horizontally and vertically.
    func scales(_ g: CameraPictureGeometry) -> (x: Double, y: Double) {
        let sx: Double = Double(outputWidth) / (uprightWidth * Double(g.visibleWidth))
        let sy: Double = Double(outputHeight) / (uprightHeight * Double(g.visibleHeight))
        return (sx, sy)
    }
}

final class CameraCropTests: XCTestCase {
    /// Camera pictures: a landscape sensor and a portrait one.
    private let pictures: [(Int, Int)] = [(1920, 1080), (1080, 1920)]
    /// Portrait phone, landscape phone, iPad 4:3 both ways, square.
    private let outputs: [(Int, Int)] = [(1179, 2556), (2556, 1179), (1640, 2360), (2360, 1640), (1000, 1000)]

    private var allCrops: [CameraCrop] {
        var crops: [CameraCrop] = []
        for mode in CameraCropMode.allCases {
            for anchor in CameraCropAnchor.allCases {
                for zoom in CameraCrop.zoomChoices {
                    crops.append(CameraCrop(mode: mode, anchor: anchor, zoom: zoom))
                }
            }
        }
        return crops
    }

    /// The camera texture coordinate of upright point (`x`, `y`) with this rotation and mirror (no crop).
    private func textureOfUpright(x: Float, y: Float, rotation: CameraRotation, mirrored: Bool) -> (x: Float, y: Float) {
        let whole = CameraPictureGeometry(visibleWidth: 1, visibleHeight: 1, offsetX: 0, offsetY: 0, rotation: rotation, mirrored: mirrored)
        return whole.textureCoordinate(x: x, y: y)
    }

    /// Checks every guarantee of contracts/camera-crop.md for one case; returns the failure count.
    private func check(_ c: CropCase) -> Int {
        let g: CameraPictureGeometry = c.geometry
        var failures: Int = 0
        func expect(_ ok: Bool, _ what: String) {
            if !ok {
                failures += 1
                XCTFail(c.label + ": " + what)
            }
        }
        let s = c.scales(g)
        let aspectError: Double = abs(s.x / s.y - 1)
        expect(aspectError < 0.001, "no stretch (aspect error \(aspectError))")
        let tolerance: Float = 1e-5
        let endX: Float = g.offsetX + g.visibleWidth
        let endY: Float = g.offsetY + g.visibleHeight
        if c.crop.mode == .fill {
            expect(g.offsetX >= -tolerance && g.offsetY >= -tolerance, "Fill starts inside the picture")
            expect(endX <= 1 + tolerance && endY <= 1 + tolerance, "Fill ends inside the picture (layer covered)")
            for (x, y) in [(Float(0.0005), Float(0.0005)), (0.9995, 0.0005), (0.0005, 0.9995), (0.9995, 0.9995)] {
                expect(g.contains(x: x, y: y), "Fill shows the picture at (\(x), \(y))")
            }
        } else if c.crop.zoom == 1 {
            expect(g.offsetX <= tolerance && g.offsetY <= tolerance, "Fit starts at or before the picture's edge")
            expect(endX >= 1 - tolerance && endY >= 1 - tolerance, "Fit shows the whole picture")
        }
        // The anchor point of the upright (mirrored) picture lands on its relative output point.
        let ay: Float = c.crop.anchor.y
        let shown = g.textureCoordinate(x: 0.5, y: ay)
        let expected = textureOfUpright(x: 0.5, y: ay, rotation: c.rotation, mirrored: c.mirrored)
        expect(abs(shown.x - expected.x) < 1e-4 && abs(shown.y - expected.y) < 1e-4, "anchor kept")
        // The zoom multiplies the plain Fill (or Fit) scale.
        let plainCrop = CameraCrop(mode: c.crop.mode, anchor: c.crop.anchor, zoom: 1)
        let plain = CropCase(pictureWidth: c.pictureWidth, pictureHeight: c.pictureHeight, rotation: c.rotation, mirrored: c.mirrored,
                             outputWidth: c.outputWidth, outputHeight: c.outputHeight, crop: plainCrop)
        let plainScale: Double = plain.scales(plain.geometry).x
        let ratio: Double = s.x / plainScale
        expect(abs(ratio - Double(c.crop.zoom)) < 0.001, "zoom ratio \(ratio)")
        return failures
    }

    /// CAM-007-S1: 2 pictures × 4 turns × mirror × 5 output shapes × 24 crops.
    func testGeometryTableHoldsEveryGuarantee() {
        var cases: Int = 0
        var failures: Int = 0
        for (pw, ph) in pictures {
            for rotation in CameraRotation.allCases {
                for mirrored in [false, true] {
                    for (ow, oh) in outputs {
                        for crop in allCrops {
                            let c = CropCase(pictureWidth: pw, pictureHeight: ph, rotation: rotation, mirrored: mirrored,
                                             outputWidth: ow, outputHeight: oh, crop: crop)
                            failures += check(c)
                            cases += 1
                        }
                    }
                }
            }
        }
        XCTAssertEqual(cases, 1920)
        XCTAssertEqual(failures, 0)
    }

    /// The acceptance on the CPU: a 1920×1080 sensor turned 90° on a portrait phone, then upright (0°)
    /// on the same phone in landscape (CAM-007-R3). Same anchor point, same zoom ratio, same mode.
    func testPortraitToLandscapePreservesTheChosenCrop() {
        for mirrored in [false, true] {
            for crop in allCrops {
                let portrait = CropCase(pictureWidth: 1920, pictureHeight: 1080, rotation: .clockwise90, mirrored: mirrored,
                                        outputWidth: 1179, outputHeight: 2556, crop: crop)
                let landscape = CropCase(pictureWidth: 1920, pictureHeight: 1080, rotation: .none, mirrored: mirrored,
                                         outputWidth: 2556, outputHeight: 1179, crop: crop)
                let label: String = "mirrored \(mirrored) \(crop.mode.rawValue)/\(crop.anchor.rawValue)/\(crop.zoom)"
                XCTAssertEqual(check(portrait), 0, label + " portrait")
                XCTAssertEqual(check(landscape), 0, label + " landscape")
                // Upright, the anchor point is at the same relative output point in both orientations.
                let gp = portrait.geometry, gl = landscape.geometry
                let ay: Float = crop.anchor.y
                let uprightP: Float = gp.offsetY + ay * gp.visibleHeight
                let uprightL: Float = gl.offsetY + ay * gl.visibleHeight
                XCTAssertEqual(uprightP, ay, accuracy: 1e-5, label)
                XCTAssertEqual(uprightL, ay, accuracy: 1e-5, label)
            }
        }
    }

    /// CAM-007-S3: the default is CAM-001's centered aspect fill.
    func testDefaultCropIsTheOldCenteredFill() {
        for (pw, ph) in pictures {
            for (ow, oh) in outputs {
                for rotation in CameraRotation.allCases {
                    let plain = CameraPictureGeometry(pictureWidth: pw, pictureHeight: ph, rotation: rotation, outputWidth: ow, outputHeight: oh)
                    let explicit = CameraPictureGeometry(pictureWidth: pw, pictureHeight: ph, rotation: rotation, outputWidth: ow,
                                                         outputHeight: oh, crop: .fill)
                    XCTAssertEqual(plain, explicit)
                    // CAM-001's formula, recomputed here.
                    let uw: Double = Double(rotation.swapsAxes ? ph : pw)
                    let uh: Double = Double(rotation.swapsAxes ? pw : ph)
                    let scale: Double = max(Double(ow) / uw, Double(oh) / uh)
                    let fx: Double = min(Double(ow) / (uw * scale), 1)
                    let fy: Double = min(Double(oh) / (uh * scale), 1)
                    XCTAssertEqual(plain.visibleWidth, Float(fx), accuracy: 1e-6)
                    XCTAssertEqual(plain.visibleHeight, Float(fy), accuracy: 1e-6)
                    XCTAssertEqual(plain.offsetX, Float((1 - fx) / 2), accuracy: 1e-6)
                    XCTAssertEqual(plain.offsetY, Float((1 - fy) / 2), accuracy: 1e-6)
                }
            }
        }
    }

    func testFitBarsAreOutsideThePicture() {
        // A 16:9 picture fitted into a square: bars above and below; with Top, all of it below.
        let center = CameraPictureGeometry(pictureWidth: 1920, pictureHeight: 1080, rotation: .none, outputWidth: 1000, outputHeight: 1000,
                                           crop: CameraCrop(mode: .fit, anchor: .center, zoom: 1))
        XCTAssertFalse(center.contains(x: 0.5, y: 0.05), "bar above")
        XCTAssertTrue(center.contains(x: 0.5, y: 0.5))
        XCTAssertFalse(center.contains(x: 0.5, y: 0.95), "bar below")
        let top = CameraPictureGeometry(pictureWidth: 1920, pictureHeight: 1080, rotation: .none, outputWidth: 1000, outputHeight: 1000,
                                        crop: CameraCrop(mode: .fit, anchor: .top, zoom: 1))
        XCTAssertTrue(top.contains(x: 0.5, y: 0.01), "picture against the top edge")
        XCTAssertTrue(top.contains(x: 0.5, y: 0.55))
        XCTAssertFalse(top.contains(x: 0.5, y: 0.6), "bar only below")
        XCTAssertEqual(top.offsetY, 0, accuracy: 1e-6)
    }

    func testDegenerateSizesWithACropGiveTheIdentity() {
        let crop = CameraCrop(mode: .fit, anchor: .bottom, zoom: 3)
        for (pw, ph, ow, oh) in [(0, 10, 64, 64), (10, -1, 64, 64), (10, 10, 0, 64), (10, 10, 64, 0)] {
            let g = CameraPictureGeometry(pictureWidth: pw, pictureHeight: ph, rotation: .clockwise270, outputWidth: ow, outputHeight: oh,
                                          mirrored: true, crop: crop)
            let expected = CameraPictureGeometry(visibleWidth: 1, visibleHeight: 1, offsetX: 0, offsetY: 0, rotation: .clockwise270, mirrored: true)
            XCTAssertEqual(g, expected, "\(pw)×\(ph) → \(ow)×\(oh)")
        }
    }

    func testCropValuesTitlesAndSnapping() {
        XCTAssertEqual(CameraCrop.fill, CameraCrop(mode: .fill, anchor: .center, zoom: 1))
        XCTAssertEqual(CameraCrop(mode: .fit, anchor: .top, zoom: 2.5).zoom, 1, "not a step → 1")
        XCTAssertEqual(CameraCrop(mode: .fit, anchor: .top, zoom: .nan).zoom, 1)
        XCTAssertEqual(CameraCrop(mode: .fit, anchor: .top, zoom: 1.5).zoom, 1.5)
        XCTAssertEqual(CameraCrop.zoomChoices.map(CameraCrop.zoomTitle), ["1×", "1.5×", "2×", "3×"])
        XCTAssertEqual(CameraCrop.zoomChoices.map(CameraCrop.zoomSpokenValue), ["1 times", "1.5 times", "2 times", "3 times"])
        XCTAssertEqual(CameraCropMode.allCases.map(\.title), ["Fill", "Fit"])
        XCTAssertEqual(CameraCropAnchor.allCases.map(\.title), ["Center", "Top", "Bottom"])
        XCTAssertEqual(CameraCropAnchor(rawValue: "top"), .top)
        XCTAssertNil(CameraCropMode(rawValue: "Fill"))
    }

    // MARK: QA-011 CAM-007-T15/T16: the drawn picture rectangle (spec 098 Clarifications 2026-11-23)

    /// D1's portrait case by hand: a 1920 × 1440 picture turned 90° (upright 1440 × 1920, 3:4) in a 1179 × 2556
    /// output. Fit: full width, 1920 × 0.81875 / 2556 = 0.61502 high, centred (bars above and below). Fill Top 2×:
    /// twice the height, against the top edge, centred horizontally. Fill Center 1×: full height, centred.
    func testPictureRectByHand() {
        let fit: CameraPictureRect = CameraPictureGeometry(pictureWidth: 1920, pictureHeight: 1440, rotation: .clockwise90,
                                                           outputWidth: 1179, outputHeight: 2556,
                                                           crop: CameraCrop(mode: .fit, anchor: .center, zoom: 1)).pictureRect
        XCTAssertEqual(fit.x, 0, accuracy: 1e-5)
        XCTAssertEqual(fit.width, 1, accuracy: 1e-5)
        XCTAssertEqual(fit.height, 0.61502, accuracy: 1e-4)
        XCTAssertEqual(fit.y, (1 - 0.61502) / 2, accuracy: 1e-4)
        let top: CameraPictureRect = CameraPictureGeometry(pictureWidth: 1920, pictureHeight: 1440, rotation: .clockwise90,
                                                           outputWidth: 1179, outputHeight: 2556,
                                                           crop: CameraCrop(mode: .fill, anchor: .top, zoom: 2)).pictureRect
        XCTAssertEqual(top.y, 0, accuracy: 1e-5, "Fill Top sits against the top edge")
        XCTAssertEqual(top.height, 2, accuracy: 1e-4)
        XCTAssertEqual(top.x + top.width / 2, 0.5, accuracy: 1e-5, "centred horizontally")
        let center: CameraPictureRect = CameraPictureGeometry(pictureWidth: 1920, pictureHeight: 1440, rotation: .clockwise90,
                                                              outputWidth: 1179, outputHeight: 2556, crop: .fill).pictureRect
        XCTAssertEqual(center.y, 0, accuracy: 1e-5)
        XCTAssertEqual(center.height, 1, accuracy: 1e-5)
        XCTAssertLessThan(center.x, 0, "Fill crops the sides")
        XCTAssertEqual(center.x + center.width / 2, 0.5, accuracy: 1e-5)
    }

    /// For representative pictures, turns, outputs and crops: the rectangle keeps the upright picture's aspect in
    /// output pixels, Fill covers the output, Fit lies inside it touching two opposite edges at 1×, the anchor sets
    /// the top edge, and a point is inside the rectangle exactly where `contains` (the shader's bar test) says so.
    func testPictureRectAgreesWithTheSamplingGeometry() {
        let pictures: [(Int, Int, CameraRotation)] = [(1920, 1440, .clockwise90), (1920, 1080, .none), (1440, 1920, .clockwise270)]
        let outputs: [(Int, Int)] = [(1179, 2556), (2556, 1179), (2064, 2752)]
        let crops: [CameraCrop] = [.fill, CameraCrop(mode: .fill, anchor: .top, zoom: 2), CameraCrop(mode: .fill, anchor: .bottom, zoom: 1.5),
                                   CameraCrop(mode: .fit, anchor: .center, zoom: 1), CameraCrop(mode: .fit, anchor: .top, zoom: 1)]
        for (pw, ph, rotation) in pictures {
            for (ow, oh) in outputs {
                for crop in crops {
                    checkPictureRect(pw, ph, rotation, ow, oh, crop)
                }
            }
        }
    }

    private func checkPictureRect(_ pw: Int, _ ph: Int, _ rotation: CameraRotation, _ ow: Int, _ oh: Int, _ crop: CameraCrop) {
        let g = CameraPictureGeometry(pictureWidth: pw, pictureHeight: ph, rotation: rotation,
                                      outputWidth: ow, outputHeight: oh, mirrored: crop.anchor == .top, crop: crop)
        let r: CameraPictureRect = g.pictureRect
        let label: String = "\(pw)x\(ph) r\(rotation.rawValue) → \(ow)x\(oh) \(crop.mode.rawValue)/\(crop.anchor.rawValue)/\(crop.zoom)"
        let uprightAspect: Double = rotation.swapsAxes ? Double(ph) / Double(pw) : Double(pw) / Double(ph)
        let drawnWidth: Double = Double(r.width) * Double(ow)
        let drawnHeight: Double = Double(r.height) * Double(oh)
        XCTAssertEqual(drawnWidth / drawnHeight, uprightAspect, accuracy: uprightAspect * 1e-4, label + ": aspect kept")
        let e: Float = 1e-4
        let right: Float = r.x + r.width
        let bottom: Float = r.y + r.height
        if crop.mode == .fill {
            XCTAssertTrue(r.x <= e && r.y <= e && right >= 1 - e && bottom >= 1 - e, label + ": covers the output")
        } else {
            XCTAssertTrue(r.x >= -e && r.y >= -e && right <= 1 + e && bottom <= 1 + e, label + ": inside the output")
            let touches: Bool = abs(r.width - 1) < e || abs(r.height - 1) < e
            XCTAssertTrue(touches, label + ": touches two opposite edges at 1×")
        }
        let expectedTop: Float = (1 - r.height) * crop.anchor.y
        XCTAssertEqual(r.y, expectedTop, accuracy: 1e-4, label + ": the anchor places the top edge")
        XCTAssertEqual(r.x + r.width / 2, 0.5, accuracy: 1e-4, label + ": centred horizontally")
        for column in 0...20 {
            for row in 0...20 {
                let x: Float = Float(column) / 20
                let y: Float = Float(row) / 20
                let insideX: Float = min(x - r.x, right - x)
                let insideY: Float = min(y - r.y, bottom - y)
                let margin: Float = min(insideX, insideY)
                guard abs(margin) > 1e-3 else { continue }   // on an edge: either answer
                XCTAssertEqual(g.contains(x: x, y: y), margin > 0, label + " at (\(x), \(y))")
            }
        }
    }
}
