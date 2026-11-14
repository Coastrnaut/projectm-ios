// CMP-006-T04, T07, T09: the aspect-fitting geometry on the CPU (CMP-006-R1 to R7, S1, S2). Plain
// Swift: runs on the host, the simulator and in the Linux shape (-DCOMPOSITOR_NO_METAL).
// * The table: portrait and landscape content × portrait and landscape output × the four modes —
//   fill covers, fit shows everything, stretch maps corners, pixelAccurate is 1:1, square pixels
//   except in stretch.
// * The anchor lands on the same output fraction when the output turns from portrait to landscape.
// * Composition with a CMP-005 transform keeps content pixels square; video fits its upright size
//   and equals the camera geometry's fill when no fit is set.
import CameraLayer
import Compositor
import VideoLayer
import XCTest

final class LayerFitGeometryTests: XCTestCase {
    private struct Size { let w: Int; let h: Int }
    private let portraitContent = Size(w: 300, h: 500)
    private let landscapeContent = Size(w: 1000, h: 600)
    private let portraitOutput = Size(w: 390, h: 844)
    private let landscapeOutput = Size(w: 1920, h: 1080)

    private func placement(_ c: Size, _ o: Size, _ fit: LayerFit) -> LayerFitPlacement {
        LayerFitPlacement(contentWidth: c.w, contentHeight: c.h, outputWidth: o.w, outputHeight: o.h, fit: fit)
    }

    func testModeNamesAreStable() {
        XCTAssertEqual(LayerFitMode.allCases.map(\.rawValue), ["fill", "fit", "stretch", "pixelAccurate"])
        XCTAssertEqual(LayerFit.default, LayerFit(mode: .fill, anchor: LayerPoint(x: 0.5, y: 0.5)))
    }

    func testEveryContentOutputAndModeCombinationMeetsItsRule() {
        let contents = [("portrait", portraitContent), ("landscape", landscapeContent)]
        let outputs = [("portrait", portraitOutput), ("landscape", landscapeOutput)]
        var cases = 0
        for (cn, c) in contents {
            for (on, o) in outputs {
                for mode in LayerFitMode.allCases {
                    let p = placement(c, o, LayerFit(mode: mode))
                    let label = "\(cn) content, \(on) output, \(mode)"
                    let rect = p.contentRect
                    switch mode {
                    case .fill:
                        XCTAssertLessThanOrEqual(p.visibleWidth, 1, label)
                        XCTAssertLessThanOrEqual(p.visibleHeight, 1, label)
                        XCTAssertTrue(p.visibleWidth == 1 || p.visibleHeight == 1, "\(label): one axis exact")
                        XCTAssertLessThanOrEqual(rect.x, 0, "\(label): covers left")
                        XCTAssertGreaterThanOrEqual(rect.x + rect.width, 1 - 1e-12, "\(label): covers right")
                        XCTAssertLessThanOrEqual(rect.y, 0, "\(label): covers top")
                        XCTAssertGreaterThanOrEqual(rect.y + rect.height, 1 - 1e-12, "\(label): covers bottom")
                    case .fit:
                        XCTAssertGreaterThanOrEqual(p.visibleWidth, 1, label)
                        XCTAssertGreaterThanOrEqual(p.visibleHeight, 1, label)
                        XCTAssertGreaterThanOrEqual(rect.x, 0, "\(label): fully visible")
                        XCTAssertLessThanOrEqual(rect.x + rect.width, 1 + 1e-12, label)
                        XCTAssertGreaterThanOrEqual(rect.y, 0, label)
                        XCTAssertLessThanOrEqual(rect.y + rect.height, 1 + 1e-12, label)
                    case .stretch:
                        XCTAssertEqual(p.textureCoordinate(x: 0, y: 0), LayerPoint(x: 0, y: 0), "\(label): corner")
                        XCTAssertEqual(p.textureCoordinate(x: 1, y: 1), LayerPoint(x: 1, y: 1), "\(label): corner")
                    case .pixelAccurate:
                        XCTAssertEqual(p.pixelScale.x, 1, accuracy: 1e-12, "\(label): 1:1 horizontally")
                        XCTAssertEqual(p.pixelScale.y, 1, accuracy: 1e-12, "\(label): 1:1 vertically")
                        let originX = rect.x * Double(o.w), originY = rect.y * Double(o.h)
                        XCTAssertEqual(originX, originX.rounded(), accuracy: 1e-9, "\(label): whole-pixel origin")
                        XCTAssertEqual(originY, originY.rounded(), accuracy: 1e-9, "\(label): whole-pixel origin")
                    }
                    if mode == .stretch {
                        XCTAssertNotEqual(p.pixelAspect, 1, accuracy: 1e-3, "\(label): stretch changes the shape here")
                    } else {
                        XCTAssertEqual(p.pixelAspect, 1, accuracy: 1e-12, "\(label): square content pixels")
                    }
                    cases += 1
                }
            }
        }
        XCTAssertEqual(cases, 16)
    }

    func testEqualAspectAndDegenerateSizes() {
        for mode in [LayerFitMode.fill, .fit, .stretch] {
            let p = LayerFitPlacement(contentWidth: 32, contentHeight: 16, outputWidth: 64, outputHeight: 32, fit: LayerFit(mode: mode))
            XCTAssertEqual(p.visibleWidth, 1); XCTAssertEqual(p.visibleHeight, 1)
            XCTAssertEqual(p.offsetX, 0); XCTAssertEqual(p.offsetY, 0)
        }
        for (cw, ch, ow, oh) in [(0, 10, 10, 10), (10, -1, 10, 10), (10, 10, 0, 10), (10, 10, 10, -5)] {
            let p = LayerFitPlacement(contentWidth: cw, contentHeight: ch, outputWidth: ow, outputHeight: oh,
                                      fit: LayerFit(mode: .pixelAccurate))
            XCTAssertEqual(p.contentToOutput, .identity, "identity for \(cw)×\(ch) in \(ow)×\(oh)")
        }
    }

    func testPixelAccurateCentresOnWholePixelsAndCrops() {
        // 300 × 500 in 800 × 600: centred at (250, 50) — exactly 300 × 500 output pixels.
        let p = LayerFitPlacement(contentWidth: 300, contentHeight: 500, outputWidth: 800, outputHeight: 600,
                                  fit: LayerFit(mode: .pixelAccurate))
        let r = p.contentRect
        XCTAssertEqual(r.x * 800, 250, accuracy: 1e-9); XCTAssertEqual(r.width * 800, 300, accuracy: 1e-9)
        XCTAssertEqual(r.y * 600, 50, accuracy: 1e-9); XCTAssertEqual(r.height * 600, 500, accuracy: 1e-9)
        // Odd difference: 3 × 3 in 8 × 8 → origin round(2.5) = 3; output pixel centre 3.5 → texel centre 0.5/3.
        let odd = LayerFitPlacement(contentWidth: 3, contentHeight: 3, outputWidth: 8, outputHeight: 8, fit: LayerFit(mode: .pixelAccurate))
        XCTAssertEqual(odd.textureCoordinate(x: 3.5 / 8, y: 3.5 / 8).x, 0.5 / 3, accuracy: 1e-12, "a texel centre")
        // Larger than the output: cropped around the anchor (centre), 1:1.
        let big = LayerFitPlacement(contentWidth: 1000, contentHeight: 2000, outputWidth: 400, outputHeight: 400,
                                    fit: LayerFit(mode: .pixelAccurate))
        XCTAssertEqual(big.visibleWidth, 0.4, accuracy: 1e-12); XCTAssertEqual(big.offsetX, 0.3, accuracy: 1e-12)
        XCTAssertEqual(big.visibleHeight, 0.2, accuracy: 1e-12); XCTAssertEqual(big.offsetY, 0.4, accuracy: 1e-12)
        // A factor of 2 doubles every content pixel.
        let doubled = LayerFitPlacement(contentWidth: 100, contentHeight: 100, outputWidth: 400, outputHeight: 400,
                                        fit: LayerFit(mode: .pixelAccurate), pixelsPerContentPixel: 2)
        XCTAssertEqual(doubled.pixelScale.x, 2, accuracy: 1e-12)
    }

    func testAnchorIsClampedAndNonFiniteReadsCentre() {
        XCTAssertEqual(LayerFit(mode: .fill, anchor: LayerPoint(x: -3, y: 7)).anchor, LayerPoint(x: 0, y: 1))
        XCTAssertEqual(LayerFit(mode: .fit, anchor: LayerPoint(x: .nan, y: .infinity)).anchor, LayerPoint(x: 0.5, y: 0.5))
    }

    /// CMP-006-S2: the anchor's content point lands on the same output fraction, portrait and landscape.
    func testTheAnchorIsKeptWhenTheOutputTurnsLandscape() {
        let anchors = [LayerPoint(x: 0.5, y: 0.5), LayerPoint(x: 0.5, y: 0), LayerPoint(x: 0, y: 0), LayerPoint(x: 1, y: 0.5)]
        for mode in [LayerFitMode.fill, .fit, .pixelAccurate] {
            for anchor in anchors {
                let fit = LayerFit(mode: mode, anchor: anchor)
                for o in [portraitOutput, landscapeOutput] {
                    let p = placement(portraitContent, o, fit)
                    let t = p.textureCoordinate(x: anchor.x, y: anchor.y)
                    let label = "\(mode) anchor (\(anchor.x), \(anchor.y)) in \(o.w)×\(o.h)"
                    if mode == .pixelAccurate {
                        // Whole-pixel rounding moves the content by at most half an output pixel.
                        XCTAssertEqual(t.x, anchor.x, accuracy: 0.5 / Double(portraitContent.w) + 1e-12, label)
                        XCTAssertEqual(t.y, anchor.y, accuracy: 0.5 / Double(portraitContent.h) + 1e-12, label)
                    } else {
                        XCTAssertEqual(t.x, anchor.x, accuracy: 1e-9, label)
                        XCTAssertEqual(t.y, anchor.y, accuracy: 1e-9, label)
                    }
                    XCTAssertEqual(p.pixelAspect, 1, accuracy: 1e-12, "\(label): square pixels")
                    if mode == .fill { XCTAssertTrue(p.visibleWidth <= 1 && p.visibleHeight <= 1, "\(label): still covers") }
                    if mode == .fit { XCTAssertTrue(p.visibleWidth >= 1 && p.visibleHeight >= 1, "\(label): still all visible") }
                }
            }
        }
        // The top-anchored fill keeps the picture's top edge at the output's top in both orientations.
        let top = LayerFit(mode: .fill, anchor: LayerPoint(x: 0.5, y: 0))
        XCTAssertEqual(placement(portraitContent, portraitOutput, top).offsetY, 0)
        XCTAssertEqual(placement(portraitContent, landscapeOutput, top).offsetY, 0)
        XCTAssertLessThan(placement(portraitContent, landscapeOutput, top).visibleHeight, 1, "landscape crops the bottom")
    }

    func testAContentPixelStaysSquareThroughARotatedTransform() throws {
        let transform = try LayerTransform(translation: LayerPoint(x: 0.1, y: -0.05), uniformScale: 0.7, rotation: 0.6)
        for o in [portraitOutput, landscapeOutput] {
            for mode in [LayerFitMode.fill, .fit, .pixelAccurate] {
                let p = placement(portraitContent, o, LayerFit(mode: mode))
                let m = p.placed(by: transform)
                // One content pixel step along u and along v, in output pixels.
                let ux: Double = m.m00 * Double(o.w) / Double(portraitContent.w)
                let uy: Double = m.m10 * Double(o.h) / Double(portraitContent.w)
                let vx: Double = m.m01 * Double(o.w) / Double(portraitContent.h)
                let vy: Double = m.m11 * Double(o.h) / Double(portraitContent.h)
                let lu: Double = (ux * ux + uy * uy).squareRoot()
                let lv: Double = (vx * vx + vy * vy).squareRoot()
                XCTAssertEqual(lu / lv, 1, accuracy: 1e-9, "\(mode) in \(o.w)×\(o.h): equal lengths")
                XCTAssertEqual((ux * vx + uy * vy) / (lu * lv), 0, accuracy: 1e-9, "\(mode): orthogonal")
            }
        }
        let identity = placement(portraitContent, landscapeOutput, .default)
        XCTAssertEqual(identity.placed(by: .identity), identity.contentToOutput, "identity transform adds nothing")
    }

    /// CMP-006-T07: video fits its upright size; with no fit it equals the camera geometry's fill.
    func testVideoFitsTheUprightSizeAndKeepsTodaysFill() {
        for rotation in CameraRotation.allCases {
            for (ow, oh) in [(390, 844), (1920, 1080)] {
                let old = CameraPictureGeometry(pictureWidth: 64, pictureHeight: 48, rotation: rotation, outputWidth: ow, outputHeight: oh)
                let new = VideoPictureGeometry(pictureWidth: 64, pictureHeight: 48, rotation: rotation, outputWidth: ow, outputHeight: oh)
                XCTAssertEqual(new.visibleWidth, old.visibleWidth, accuracy: 1e-6, "\(rotation) \(ow)×\(oh)")
                XCTAssertEqual(new.visibleHeight, old.visibleHeight, accuracy: 1e-6)
                XCTAssertEqual(new.offsetX, old.offsetX, accuracy: 1e-6)
                XCTAssertEqual(new.offsetY, old.offsetY, accuracy: 1e-6)
                for (x, y) in [(Float(0.1), Float(0.2)), (0.5, 0.5), (0.9, 0.7)] {
                    let a = new.textureCoordinate(x: x, y: y), b = old.textureCoordinate(x: x, y: y)
                    XCTAssertEqual(a.x, b.x, accuracy: 1e-6); XCTAssertEqual(a.y, b.y, accuracy: 1e-6)
                }
            }
        }
        // A sideways-recorded portrait clip (64 × 48 turned 90°: upright 48 × 64) in fit, landscape output.
        let fit = VideoPictureGeometry(pictureWidth: 64, pictureHeight: 48, rotation: .clockwise90, outputWidth: 1920,
                                       outputHeight: 1080, fit: LayerFit(mode: .fit))
        XCTAssertEqual(fit.visibleHeight, 1)
        XCTAssertLessThan(fit.uprightCoordinate(x: 0.05, y: 0.5).x, 0, "left bar")
        XCTAssertGreaterThan(fit.uprightCoordinate(x: 0.95, y: 0.5).x, 1, "right bar")
        let centre = fit.uprightCoordinate(x: 0.5, y: 0.5)
        XCTAssertEqual(centre.x, 0.5, accuracy: 1e-6); XCTAssertEqual(centre.y, 0.5, accuracy: 1e-6)
        let pixel = VideoPictureGeometry(pictureWidth: 64, pictureHeight: 48, rotation: .clockwise90, outputWidth: 480,
                                         outputHeight: 640, fit: LayerFit(mode: .pixelAccurate))
        XCTAssertEqual(pixel.visibleWidth, 10, accuracy: 1e-6, "48 upright pixels in 480: 1:1")
        XCTAssertEqual(pixel.visibleHeight, 10, accuracy: 1e-6, "64 upright pixels in 640: 1:1")
    }
}
