// ExternalOutputRehearsalTests.swift — OUT-012-T02: the rehearsal's placement is OUT-004's for the
// profile, grid points map into the preview frame, circles stay round in the preview for Fit and Fill
// (and are ellipses for Stretch on non-square pixels), the spoken description and probe, clamping.
import XCTest
@testable import PresentationLifecycle

final class ExternalOutputRehearsalTests: XCTestCase {
    private let portrait: Double = 390.0 / 845.0

    private func rehearsal(_ size: RehearsalSize, par: Double, _ fit: ExternalOutputFit, _ shape: ExternalOutputShape,
                           _ aspect: ExternalPixelAspect = .automatic) -> ExternalOutputRehearsal {
        ExternalOutputRehearsal(profile: size.profile(pixelAspect: par),
                                correction: ExternalOutputCorrection(fit: fit, shape: shape, pixelAspect: aspect),
                                deviceAspect: portrait)
    }

    func testThePlacementIsOUT004sForTheProfile() {
        let r = rehearsal(.ultrawide, par: 1.2, .fill, .device)
        let real = ExternalOutputPlacement(slotWidth: 2560, slotHeight: 1080,
                                           correction: r.correction, screenPixelAspect: 1.2, deviceAspect: portrait)
        XCTAssertEqual(r.placement, real)
        XCTAssertEqual(r.appliedPixelAspect, 1.2)
        let overridden = rehearsal(.ultrawide, par: 1.2, .fit, .device, .narrow)
        XCTAssertEqual(overridden.appliedPixelAspect, 0.9, "the setting's override wins, as on real hardware")
    }

    /// Physical x and y radii of a circle at the visual's centre, measured in the preview.
    private func previewRadii(_ r: ExternalOutputRehearsal) -> (Double, Double) {
        let t = r.preview(width: 390, height: 600)
        let radius: Double = 0.1
        let p = r.placement
        let du: Double = radius * min(p.boundsWidth, p.boundsHeight) / p.boundsWidth
        let dv: Double = radius * min(p.boundsWidth, p.boundsHeight) / p.boundsHeight
        let left = r.slotPoint(u: 0.5 - du, v: 0.5), right = r.slotPoint(u: 0.5 + du, v: 0.5)
        let top = r.slotPoint(u: 0.5, v: 0.5 - dv), bottom = r.slotPoint(u: 0.5, v: 0.5 + dv)
        let a = t.map(x: left.x, y: left.y), b = t.map(x: right.x, y: right.y)
        let c = t.map(x: top.x, y: top.y), d = t.map(x: bottom.x, y: bottom.y)
        return ((b.x - a.x) / 2, (d.y - c.y) / 2)
    }

    func testCirclesAreRoundInThePreviewForFitAndFillAndEllipsesForStretch() {
        let cases: [(RehearsalSize, Double, ExternalOutputFit, ExternalOutputShape)] = [
            (.hd1080, 1.0, .fit, .device), (.standard4x3, 1.2, .fill, .device),
            (.ultrawide, 0.9, .fit, .display), (.hd1080, 1.2, .fill, .display),
        ]
        for (size, par, fit, shape) in cases {
            let (rx, ry) = previewRadii(rehearsal(size, par: par, fit, shape))
            XCTAssertEqual(rx / ry, 1, accuracy: 0.005, "\(size) PAR \(par) \(fit) \(shape)")
        }
        let (sx, sy) = previewRadii(rehearsal(.hd1080, par: 1.2, .stretch, .device))
        XCTAssertEqual(sx / sy, 1.2, accuracy: 0.005, "Stretch does not correct: wide pixels widen circles on the glass and in the preview")
    }

    func testFitGridPointsStayInsideTheFrameAndTheFrameHasThePhysicalShape() {
        let r = rehearsal(.standard4x3, par: 1.2, .fit, .device)
        let t = r.preview(width: 390, height: 600)
        XCTAssertEqual(t.frameWidth / t.frameHeight, 1024 * 1.2 / 768, accuracy: 1e-9)
        XCTAssertEqual(t.originX * 2 + t.frameWidth, 390, accuracy: 1e-9, "centred")
        for u in [0.0, 0.5, 1.0] {
            for v in [0.0, 0.5, 1.0] {
                let s = r.slotPoint(u: u, v: v), q = t.map(x: s.x, y: s.y)
                XCTAssertGreaterThanOrEqual(q.x, t.originX - 1e-9)
                XCTAssertLessThanOrEqual(q.x, t.originX + t.frameWidth + 1e-9)
                XCTAssertGreaterThanOrEqual(q.y, t.originY - 1e-9)
                XCTAssertLessThanOrEqual(q.y, t.originY + t.frameHeight + 1e-9)
            }
        }
        let corner = r.slotPoint(u: 0, v: 0)
        XCTAssertEqual(corner.y, 0, accuracy: 1e-9, "a portrait picture fills the height")
    }

    func testDescriptionProbeAndClamping() {
        XCTAssertEqual(rehearsal(.hd1080, par: 1, .fit, .device).spokenDescription, "Previewing 16 by 9 display, fit, pillarbox")
        XCTAssertEqual(rehearsal(.hd1080, par: 1, .fit, .device).probe,
                       "profile=1920x1080 par=1.00 fit=fit shape=device frame=498x1080 bars=pillarbox")
        XCTAssertEqual(rehearsal(.hd1080, par: 1, .fill, .device).barsWord, "cropped")
        XCTAssertEqual(rehearsal(.hd1080, par: 1, .fit, .display).barsWord, "no bars")
        XCTAssertEqual(rehearsal(.hd1080, par: 1, .stretch, .device).barsWord, "stretched")
        let landscapeOn4x3 = ExternalOutputRehearsal(profile: RehearsalSize.standard4x3.profile(pixelAspect: 1),
                                                     correction: ExternalOutputCorrection(fit: .fit, shape: .device),
                                                     deviceAspect: 845.0 / 390.0)
        XCTAssertEqual(landscapeOn4x3.spokenDescription, "Previewing 4 by 3 display, fit, letterbox")
        XCTAssertEqual(rehearsal(.ultrawide, par: 1.2, .fit, .display).spokenDescription,
                       "Previewing 21 by 9 display, fit, no bars, pixel aspect 1.2")
        let custom = RehearsalProfile.custom(width: 10, height: 99_999, pixelAspect: .nan)
        XCTAssertEqual(custom.width, 160)
        XCTAssertEqual(custom.height, 7680)
        XCTAssertEqual(custom.pixelAspect, 1)
        XCTAssertEqual(custom.spokenName, "160 by 7680")
        XCTAssertEqual(ExternalOutputRehearsal.twoDecimals(0.9), "0.90")
        let empty = rehearsal(.hd1080, par: 1, .fit, .device).preview(width: 0, height: 100)
        XCTAssertEqual(empty.scaleX, 0)
    }
}
