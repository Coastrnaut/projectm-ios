// ExternalOutputPlacementTests.swift — OUT-004-T02, the row's acceptance (OUT-004-S1): "Test grid
// circles stay circular under chosen correction." For 16:9, 4:3 and 21:9 screens, a 9:19.5 portrait
// source and the display's own shape, and PAR 1.0, 0.9 and 1.2, a unit circle in the source maps to
// a circle on the glass (physical x and y radii equal within 0.5 %); Fit shows the whole source, Fill
// covers the screen, Stretch is an ellipse whenever the shapes differ.
import PresentationLifecycle
import XCTest

final class ExternalOutputPlacementTests: XCTestCase {
    /// Slot sizes in points whose pixel grid has the named shape.
    private let screens: [(name: String, width: Double, height: Double)] = [
        ("16:9", 1920, 1080), ("4:3", 1024, 768), ("21:9", 2560, 1080),
    ]
    private let ratios: [Double] = [1.0, 0.9, 1.2]
    private let portrait: Double = 9.0 / 19.5

    /// A unit circle in the source (radius 1 in source-height units) on the glass: its x radius in
    /// pixels is (frame width / source width) and its y radius (frame height / source height); the
    /// physical x radius multiplies by the PAR.
    private func physicalRadii(_ p: ExternalOutputPlacement, par: Double, sourceAspect: Double) -> (x: Double, y: Double) {
        let sourceHeight: Double = 1
        let sourceWidth: Double = sourceAspect * sourceHeight
        let xPixels: Double = p.frameWidth / sourceWidth
        let yPixels: Double = p.frameHeight / sourceHeight
        return (xPixels * par, yPixels)
    }

    func testFitAndFillKeepCirclesCircularForEveryScreenSourceAndRatio() {
        for screen in screens {
            for par in ratios {
                let display: Double = screen.width * par / screen.height
                for source in [portrait, display] {
                    for fit in [ExternalOutputFit.fit, .fill] {
                        let p = ExternalOutputPlacement(slotWidth: screen.width, slotHeight: screen.height,
                                                        pixelAspectRatio: par, sourceAspect: source, fit: fit)
                        let r = physicalRadii(p, par: par, sourceAspect: source)
                        let label = "\(screen.name) PAR \(par) source \(source) \(fit)"
                        XCTAssertEqual(r.x / r.y, 1, accuracy: 0.005, "circle stays circular: \(label)")
                        XCTAssertEqual(p.centerX, screen.width / 2, accuracy: 1e-9, label)
                        XCTAssertEqual(p.centerY, screen.height / 2, accuracy: 1e-9, label)
                        if fit == .fit {
                            XCTAssertLessThanOrEqual(p.frameWidth, screen.width + 1e-6, "whole source visible: \(label)")
                            XCTAssertLessThanOrEqual(p.frameHeight, screen.height + 1e-6, "whole source visible: \(label)")
                            XCTAssertTrue(abs(p.frameWidth - screen.width) < 1e-6 || abs(p.frameHeight - screen.height) < 1e-6,
                                          "touches one edge: \(label)")
                        } else {
                            XCTAssertGreaterThanOrEqual(p.frameWidth, screen.width - 1e-6, "screen covered: \(label)")
                            XCTAssertGreaterThanOrEqual(p.frameHeight, screen.height - 1e-6, "screen covered: \(label)")
                        }
                    }
                }
            }
        }
    }

    func testFitPillarboxesAPortraitSourceAndTheDisplayShapeHasNoBars() {
        let p = ExternalOutputPlacement(slotWidth: 1920, slotHeight: 1080, pixelAspectRatio: 1, sourceAspect: portrait, fit: .fit)
        XCTAssertEqual(p.bars, .pillarbox)
        XCTAssertEqual(p.frameHeight, 1080, accuracy: 1e-9)
        XCTAssertEqual(p.frameWidth, 1080 * portrait, accuracy: 1e-9)
        let wide = ExternalOutputPlacement(slotWidth: 1024, slotHeight: 768, pixelAspectRatio: 1, sourceAspect: 21.0 / 9, fit: .fit)
        XCTAssertEqual(wide.bars, .letterbox)
        for par in ratios {
            let own = ExternalOutputPlacement(slotWidth: 1920, slotHeight: 1080, pixelAspectRatio: par, sourceAspect: nil, fit: .fit)
            XCTAssertEqual(own.bars, .none, "display shape: no bars at PAR \(par)")
            XCTAssertEqual(own.frameWidth, 1920, accuracy: 1e-6)
            XCTAssertEqual(own.scaleX, 1 / par, accuracy: 1e-12)
        }
        let fill = ExternalOutputPlacement(slotWidth: 1920, slotHeight: 1080, pixelAspectRatio: 1, sourceAspect: portrait, fit: .fill)
        XCTAssertEqual(fill.bars, .none)
    }

    func testDisplayShapeAtSquarePixelsIsTodaysPlacement() {
        let p = ExternalOutputPlacement(slotWidth: 1920, slotHeight: 1080, correction: .default, screenPixelAspect: 1, deviceAspect: portrait)
        XCTAssertTrue(p.isIdentity)
    }

    func testStretchIgnoresShapeAndRatioSoCirclesBecomeEllipses() {
        for screen in screens {
            for par in ratios {
                let p = ExternalOutputPlacement(slotWidth: screen.width, slotHeight: screen.height,
                                                pixelAspectRatio: par, sourceAspect: portrait, fit: .stretch)
                XCTAssertTrue(p.isIdentity, "stretch fills the pixels exactly")
                let r = physicalRadii(p, par: par, sourceAspect: portrait)
                XCTAssertGreaterThan(abs(r.x / r.y - 1), 0.05, "a portrait source stretched is an ellipse (\(screen.name), \(par))")
            }
        }
    }

    func testCorrectionResolvesTheShapeAndTheRatio() {
        let device = ExternalOutputCorrection(fit: .fit, shape: .device, pixelAspect: .automatic)
        let a = ExternalOutputPlacement(slotWidth: 1920, slotHeight: 1080, correction: device, screenPixelAspect: 1.2, deviceAspect: portrait)
        XCTAssertEqual(a.scaleX, 1 / 1.2, accuracy: 1e-12, "automatic reads the screen")
        XCTAssertEqual(a.frameWidth * 1.2 / a.frameHeight, portrait, accuracy: 1e-9)
        let manual = ExternalOutputCorrection(fit: .fit, shape: .device, pixelAspect: .narrow)
        let b = ExternalOutputPlacement(slotWidth: 1920, slotHeight: 1080, correction: manual, screenPixelAspect: 1.2, deviceAspect: portrait)
        XCTAssertEqual(b.scaleX, 1 / 0.9, accuracy: 1e-12, "the override wins")
        let noDevice = ExternalOutputPlacement(slotWidth: 1920, slotHeight: 1080, correction: device, screenPixelAspect: 1, deviceAspect: nil)
        XCTAssertTrue(noDevice.isIdentity, "no device shape yet: the display's shape")
    }

    func testInvalidInputFillsAndBadRatiosReadSquare() {
        XCTAssertTrue(ExternalOutputPlacement(slotWidth: 0, slotHeight: 1080, pixelAspectRatio: 1, sourceAspect: portrait, fit: .fit).isIdentity)
        XCTAssertEqual(ExternalOutputPlacement(slotWidth: .nan, slotHeight: 1080, pixelAspectRatio: 1, sourceAspect: portrait, fit: .fill).scaleX, 1)
        XCTAssertTrue(ExternalOutputPlacement(slotWidth: 1920, slotHeight: 1080, pixelAspectRatio: .nan, sourceAspect: portrait, fit: .fit).isIdentity)
        for bad in [Double.nan, .infinity, 0, -1, 0.3, 3] as [Double] {
            XCTAssertEqual(ExternalPixelAspect.automatic.resolved(screen: bad), 1)
        }
        XCTAssertEqual(ExternalPixelAspect.automatic.resolved(screen: nil), 1)
        XCTAssertEqual(ExternalPixelAspect.automatic.resolved(screen: 0.9), 0.9)
        XCTAssertEqual(ExternalPixelAspect.allCases.map(\.rawValue), ["auto", "1.0", "0.9", "1.2"])
        XCTAssertEqual(ExternalOutputFit.allCases.map(\.rawValue), ["fit", "fill", "stretch"])
        XCTAssertEqual(ExternalOutputShape.allCases.map(\.rawValue), ["display", "device"])
    }
}
