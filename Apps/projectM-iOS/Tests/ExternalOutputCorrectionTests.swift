// ExternalOutputCorrectionTests.swift — OUT-004-T05 (OUT-004-S2) and T06: a grid-of-circles visual
// placed through a real external `VisualSlotView` and rendered to a bitmap keeps its circles round
// (axis ratio within 2 % with the pixel aspect ratio taken into account) under Fit and Fill, with
// black bars where Fit leaves them; the OUT-010 cover spans the bars; the device slot stays identity;
// a recording hold defers a change; the setting persists. No display, screen or wall clock needed.
// Simulator results are never device evidence (OUT-004-T10 is).
import PresentationLifecycle
import UIKit
import XCTest
@testable import projectM_iOS

/// A visual that draws a 3 × 3 grid of white filled circles on black, sized from its own bounds
/// (as every visual lays out its drawable from its bounds).
private final class CircleGridView: UIView {
    private let shapes = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        shapes.fillColor = UIColor.white.cgColor
        layer.addSublayer(shapes)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("unused") }

    /// The circle radius in bounds units.
    var radius: CGFloat { min(bounds.width, bounds.height) * 0.14 }

    override func layoutSubviews() {
        super.layoutSubviews()
        shapes.frame = bounds
        let path = CGMutablePath()
        let step: CGFloat = radius * 2.4
        for row in -1...1 {
            for column in -1...1 {
                let center = CGPoint(x: bounds.midX + CGFloat(column) * step, y: bounds.midY + CGFloat(row) * step)
                path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            }
        }
        shapes.path = path
    }
}

/// An RGBA8 bitmap of a layer tree at scale 1.
private struct Bitmap {
    let width: Int
    let height: Int
    private var bytes: [UInt8]

    @MainActor init(_ view: UIView) {
        width = Int(view.bounds.width)
        height = Int(view.bounds.height)
        bytes = [UInt8](repeating: 0, count: width * height * 4)
        let w = width, h = height
        bytes.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) -> Void in
            let context = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.translateBy(x: 0, y: CGFloat(h))
            context.scaleBy(x: 1, y: -1)   // UIKit's top-left origin
            view.layer.render(in: context)
        }
    }

    func isWhite(_ x: Int, _ y: Int) -> Bool { bytes[(y * width + x) * 4] > 127 }
    func isBlack(_ x: Int, _ y: Int) -> Bool {
        let i = (y * width + x) * 4
        return bytes[i] < 8 && bytes[i + 1] < 8 && bytes[i + 2] < 8
    }

    /// The white run through (x, y) along one axis, in pixels.
    func run(_ x: Int, _ y: Int, horizontal: Bool) -> Int {
        var low = horizontal ? x : y, high = low
        let limit = horizontal ? width : height
        func white(_ v: Int) -> Bool { horizontal ? isWhite(v, y) : isWhite(x, v) }
        while low > 0, white(low - 1) { low -= 1 }
        while high < limit - 1, white(high + 1) { high += 1 }
        return high - low + 1
    }
}

@MainActor
final class ExternalOutputCorrectionTests: XCTestCase {
    private let hd = ExternalDisplayGeometry(width: 1920, height: 1080, scale: 1)
    private let portrait = CGSize(width: 390, height: 845)   // 9:19.5

    /// A visualizing coordinator whose device slot is portrait, with the visual on a 1920 × 1080
    /// external slot.
    private func external(_ correction: ExternalOutputCorrection)
        -> (ExternalDisplayCoordinator, VisualSlotView, VisualSlotView, CircleGridView) {
        let coordinator = ExternalDisplayCoordinator()
        let device = VisualSlotView(role: .device)
        device.frame = CGRect(origin: .zero, size: portrait)
        let slot = VisualSlotView(role: .external)
        slot.frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let visual = CircleGridView()
        coordinator.registerDeviceSlot(device)
        device.layoutIfNeeded()
        coordinator.show(visual)
        coordinator.visualizerActive(true)
        coordinator.correction = correction
        coordinator.externalConnected(id: "a", slot: slot, geometry: hd, foreground: true)
        slot.layoutIfNeeded()
        visual.layoutIfNeeded()
        return (coordinator, device, slot, visual)
    }

    /// The physical axis ratio of the central circle (1 = round on the glass).
    private func centralCircleRatio(_ slot: VisualSlotView, par: Double) -> Double {
        let bitmap = Bitmap(slot)
        let x = bitmap.width / 2, y = bitmap.height / 2
        XCTAssertTrue(bitmap.isWhite(x, y), "the central circle is at the centre")
        let across = Double(bitmap.run(x, y, horizontal: true))
        let down = Double(bitmap.run(x, y, horizontal: false))
        return across * par / down
    }

    // MARK: - T05: circles through the slot (OUT-004-S2)

    func testCirclesStayRoundThroughTheExternalSlotUnderFitAndFill() {
        let cases: [(ExternalOutputFit, ExternalOutputShape, ExternalPixelAspect, Double)] = [
            (.fit, .device, .square, 1.0), (.fit, .device, .wide, 1.2), (.fill, .device, .narrow, 0.9),
            (.fit, .display, .wide, 1.2), (.fill, .display, .square, 1.0),
        ]
        for (fit, shape, aspect, par) in cases {
            let correction = ExternalOutputCorrection(fit: fit, shape: shape, pixelAspect: aspect)
            let (_, _, slot, _) = external(correction)
            XCTAssertEqual(centralCircleRatio(slot, par: par), 1, accuracy: 0.02, "\(fit) \(shape) PAR \(par)")
        }
    }

    func testStretchDistortsADevicePictureAsDocumented() {
        let (_, _, slot, visual) = external(ExternalOutputCorrection(fit: .stretch, shape: .device, pixelAspect: .wide))
        XCTAssertEqual(visual.transform, .identity)
        XCTAssertEqual(visual.frame, slot.bounds, "stretch fills the pixels exactly (today's placement)")
    }

    func testFitPillarboxesTheDeviceShapeWithBlackBarsAndTheCoverSpansThem() {
        let (coordinator, _, slot, visual) = external(ExternalOutputCorrection(fit: .fit, shape: .device, pixelAspect: .square))
        let frameWidth = 1080 * portrait.width / portrait.height
        XCTAssertEqual(visual.frame.width, frameWidth, accuracy: 0.5)
        XCTAssertEqual(visual.frame.height, 1080, accuracy: 0.5)
        XCTAssertEqual(visual.frame.midX, 960, accuracy: 0.5)
        XCTAssertEqual(coordinator.externalPlacementSummary, "fit=fit shape=device par=1.00 frame=498x1080 bars=pillarbox")
        let bitmap = Bitmap(slot)
        XCTAssertTrue(bitmap.isBlack(10, 540) && bitmap.isBlack(1909, 540), "true black bars at both sides")
        coordinator.setBlackout(true)
        // `CALayer.render(in:)` ignores zPosition, so the cover is checked as OUT-010's tests check it:
        // fully opaque, not animating and spanning the whole slot (bars included).
        XCTAssertTrue(coordinator.isOutputBlack, "OUT-010: the cover fills the whole slot")
        XCTAssertTrue(slot.isOutputBlack)
    }

    func testFillCoversTheScreenAndDisplayShapeAtSquarePixelsIsTodaysPlacement() {
        let (coordinator, _, slot, visual) = external(ExternalOutputCorrection(fit: .fill, shape: .device, pixelAspect: .square))
        XCTAssertGreaterThanOrEqual(visual.frame.width, 1919.5)
        XCTAssertGreaterThanOrEqual(visual.frame.height, 1079.5)
        XCTAssertTrue(slot.clipsToBounds, "the overflow is cropped")
        coordinator.correction = .default
        XCTAssertEqual(visual.transform, .identity, "applied inside the call")
        XCTAssertEqual(visual.frame, slot.bounds)
        XCTAssertEqual(coordinator.externalPlacementSummary, "fit=fit shape=display par=1.00 frame=1920x1080 bars=none")
    }

    func testTheDeviceSlotIsNeverCorrected() {
        let (coordinator, device, slot, visual) = external(ExternalOutputCorrection(fit: .fit, shape: .device, pixelAspect: .wide))
        XCTAssertTrue(visual.superview === slot)
        XCTAssertNotEqual(visual.transform, .identity)
        coordinator.externalDisconnected(id: "a")
        XCTAssertTrue(visual.superview === device)
        XCTAssertEqual(visual.transform, .identity, "OUT-004-R3")
        XCTAssertEqual(visual.frame, device.bounds)
        XCTAssertNil(coordinator.externalPlacementSummary)
    }

    func testADeviceRotationRelaysTheExternalPicture() {
        let (coordinator, device, slot, visual) = external(ExternalOutputCorrection(fit: .fit, shape: .device, pixelAspect: .square))
        device.frame = CGRect(x: 0, y: 0, width: 845, height: 390)
        device.layoutIfNeeded()
        XCTAssertTrue(visual.superview === slot, "the test keeps the slot alive (the coordinator holds it weakly)")
        XCTAssertEqual(coordinator.deviceAspect ?? 0, 845.0 / 390, accuracy: 1e-9)
        XCTAssertEqual(visual.frame.width, 1920, accuracy: 0.5, "landscape device on 16:9: width-limited")
    }

    func testARecordingHoldDefersAChangeUntilItEnds() {
        let (coordinator, _, slot, visual) = external(.default)
        coordinator.holdsPlacement = true
        coordinator.correction = ExternalOutputCorrection(fit: .fit, shape: .device, pixelAspect: .square)
        slot.layoutIfNeeded()
        XCTAssertEqual(visual.frame, slot.bounds, "the recording's picture size never changes (OUT-004-R7)")
        coordinator.holdsPlacement = false
        XCTAssertEqual(visual.frame.height, 1080, accuracy: 0.5)
        XCTAssertLessThan(visual.frame.width, 600, "applied when the hold ends")
    }

    // MARK: - T06: persistence (OUT-004-R8)

    func testTheSettingPersistsAndPushesToTheCoordinator() throws {
        let suite = "OUT-004-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = ExternalDisplayCoordinator()
        let setting = ExternalOutputSetting(defaults: defaults, external: coordinator)
        XCTAssertEqual(setting.correction, .default, "defaults: Fit, Display, Automatic")
        XCTAssertTrue(defaults.dictionaryRepresentation().keys.filter { (k: String) -> Bool in k.hasPrefix("settings.externalDisplay") }.isEmpty,
                      "nothing stored until changed")
        setting.fit = .fill
        setting.shape = .device
        setting.pixelAspect = .wide
        XCTAssertEqual(coordinator.correction, ExternalOutputCorrection(fit: .fill, shape: .device, pixelAspect: .wide))
        XCTAssertEqual(defaults.string(forKey: ExternalOutputSetting.fitKey), "fill")
        XCTAssertEqual(defaults.string(forKey: ExternalOutputSetting.shapeKey), "device")
        XCTAssertEqual(defaults.string(forKey: ExternalOutputSetting.pixelAspectKey), "1.2")
        let reloaded = ExternalOutputSetting(defaults: defaults, external: ExternalDisplayCoordinator())
        XCTAssertEqual(reloaded.correction, coordinator.correction, "restored after relaunch")
        defaults.set("bogus", forKey: ExternalOutputSetting.fitKey)
        XCTAssertEqual(ExternalOutputSetting(defaults: defaults, external: ExternalDisplayCoordinator()).fit, .fit, "unknown reads the default")
        XCTAssertEqual([ExternalOutputSetting.fitKey, ExternalOutputSetting.shapeKey, ExternalOutputSetting.pixelAspectKey],
                       ["settings.externalDisplay.fit", "settings.externalDisplay.shape", "settings.externalDisplay.pixelAspect"])
    }
}
