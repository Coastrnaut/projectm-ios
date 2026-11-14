// ExternalRehearsalTests.swift — OUT-012-T05, T07, T08 (OUT-012-S1, S2, S3): the rehearsal preview
// against the real external output. For several display profiles and corrections, a real external
// `VisualSlotView` placed by the coordinator (a fake display of that profile: its size, and its PAR as
// the stand-in screen value) and the rehearsal's preview hold the same circle-grid view. Grid points
// (circle centres and edges) mapped through both agree within 0.5 pt after scaling the real slot into
// the device frame by the preview transform, and the rendered circles show the same physical axis
// ratio within 2 %. A settled real display ends the rehearsal; the visual never leaves the device slot
// for it. No display, screen or wall clock. Simulator results are never device evidence (T11 is).
import PresentationLifecycle
import UIKit
import XCTest
@testable import projectM_iOS

/// A 3 × 3 grid of white filled circles on black, sized from its own bounds (as OUT-004's test grid).
private final class RehearsalCircleGrid: UIView {
    private let shapes = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        shapes.fillColor = UIColor.white.cgColor
        layer.addSublayer(shapes)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("unused") }

    var radius: CGFloat { min(bounds.width, bounds.height) * 0.14 }

    /// Circle centres and their left, right, top and bottom edge points, in bounds coordinates.
    var gridPoints: [CGPoint] {
        var points: [CGPoint] = []
        let step: CGFloat = radius * 2.4
        for row in -1...1 {
            for column in -1...1 {
                let c = CGPoint(x: bounds.midX + CGFloat(column) * step, y: bounds.midY + CGFloat(row) * step)
                points += [c, CGPoint(x: c.x - radius, y: c.y), CGPoint(x: c.x + radius, y: c.y),
                           CGPoint(x: c.x, y: c.y - radius), CGPoint(x: c.x, y: c.y + radius)]
            }
        }
        return points
    }

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

/// An RGBA8 bitmap of a layer tree at `scale` pixels per point.
private struct RehearsalBitmap {
    let width: Int
    let height: Int
    private var bytes: [UInt8]

    @MainActor init(_ view: UIView, scale: CGFloat) {
        width = Int(view.bounds.width * scale)
        height = Int(view.bounds.height * scale)
        bytes = [UInt8](repeating: 0, count: width * height * 4)
        let w = width, h = height
        bytes.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) -> Void in
            let context = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.translateBy(x: 0, y: CGFloat(h))
            context.scaleBy(x: scale, y: -scale)   // UIKit's top-left origin
            view.layer.render(in: context)
        }
    }

    func isWhite(_ x: Int, _ y: Int) -> Bool { bytes[(y * width + x) * 4] > 160 }

    func run(_ x: Int, _ y: Int, horizontal: Bool) -> Int {
        var low = horizontal ? x : y, high = low
        let limit = horizontal ? width : height
        func white(_ v: Int) -> Bool { horizontal ? isWhite(v, y) : isWhite(x, v) }
        while low > 0, white(low - 1) { low -= 1 }
        while high < limit - 1, white(high + 1) { high += 1 }
        return high - low + 1
    }

    /// Across ÷ down of the white run through (x, y).
    func ratio(_ x: Int, _ y: Int) -> Double {
        Double(run(x, y, horizontal: true)) / Double(run(x, y, horizontal: false))
    }
}

@MainActor
final class ExternalRehearsalTests: XCTestCase {
    private let portrait = CGSize(width: 390, height: 845)
    /// The device frame the preview fills (an iPad-sized area, so circles span ~100 px at 2×).
    private let deviceFrame = CGRect(x: 0, y: 0, width: 1032, height: 1376)

    private struct Case {
        let profile: RehearsalProfile
        let correction: ExternalOutputCorrection
    }

    private let cases: [Case] = [
        Case(profile: RehearsalSize.hd1080.profile(pixelAspect: 1.0),
             correction: ExternalOutputCorrection(fit: .fit, shape: .device, pixelAspect: .automatic)),
        Case(profile: RehearsalSize.standard4x3.profile(pixelAspect: 1.2),
             correction: ExternalOutputCorrection(fit: .fill, shape: .device, pixelAspect: .automatic)),
        Case(profile: RehearsalSize.ultrawide.profile(pixelAspect: 1.0),
             correction: ExternalOutputCorrection(fit: .fit, shape: .display, pixelAspect: .narrow)),
        Case(profile: RehearsalProfile.custom(width: 720, height: 480, pixelAspect: 0.9),
             correction: ExternalOutputCorrection(fit: .fit, shape: .device, pixelAspect: .automatic)),
    ]

    /// The real path: a visualizing coordinator with a portrait device slot and the grid on an external
    /// slot of the profile's size whose screen reports the profile's PAR.
    private func realOutput(_ c: Case) -> (ExternalDisplayCoordinator, VisualSlotView, VisualSlotView, RehearsalCircleGrid) {
        let coordinator = ExternalDisplayCoordinator()
        let device = VisualSlotView(role: .device)
        device.frame = CGRect(origin: .zero, size: portrait)
        let slot = VisualSlotView(role: .external)
        slot.standInPixelAspect = c.profile.pixelAspect
        slot.frame = CGRect(x: 0, y: 0, width: c.profile.width, height: c.profile.height)
        let visual = RehearsalCircleGrid()
        coordinator.registerDeviceSlot(device)
        device.layoutIfNeeded()
        coordinator.show(visual)
        coordinator.visualizerActive(true)
        coordinator.correction = c.correction
        let geometry = ExternalDisplayGeometry(width: c.profile.width, height: c.profile.height, scale: 1)
        coordinator.externalConnected(id: "real", slot: slot, geometry: geometry, foreground: true)
        slot.layoutIfNeeded()
        visual.layoutIfNeeded()
        return (coordinator, device, slot, visual)
    }

    private func preview(_ c: Case, deviceAspect: Double?) -> (RehearsalPreviewView, RehearsalCircleGrid) {
        let grid = RehearsalCircleGrid()
        let view = RehearsalPreviewView(content: grid)
        view.frame = deviceFrame
        view.apply(ExternalOutputRehearsal(profile: c.profile, correction: c.correction, deviceAspect: deviceAspect))
        view.layoutIfNeeded()
        return (view, grid)
    }

    // MARK: - T05: the acceptance (OUT-012-S1, S2)

    func testGridPointsMapTheSameThroughThePreviewAndTheRealSlot() throws {
        for c in cases {
            let (coordinator, _, slot, visual) = realOutput(c)
            XCTAssertTrue(visual.superview === slot, "the real output holds the grid")
            let (view, grid) = preview(c, deviceAspect: coordinator.deviceAspect)
            let rehearsal = try XCTUnwrap(view.rehearsal)
            let t = try XCTUnwrap(view.previewTransform)
            XCTAssertEqual(view.slot.placement, slot.placement, "\(c.profile.name): the same OUT-004 placement")
            XCTAssertEqual(grid.bounds.size, visual.bounds.size)
            for point in visual.gridPoints {
                let real: CGPoint = visual.convert(point, to: slot)
                let u = Double(point.x / visual.bounds.width), v = Double(point.y / visual.bounds.height)
                let model = rehearsal.slotPoint(u: u, v: v)
                XCTAssertEqual(Double(real.x), model.x, accuracy: 0.5, "pure mapping = real slot (x)")
                XCTAssertEqual(Double(real.y), model.y, accuracy: 0.5, "pure mapping = real slot (y)")
                let expected = t.map(x: Double(real.x), y: Double(real.y))
                let shown: CGPoint = grid.convert(point, to: view)
                XCTAssertEqual(Double(shown.x), expected.x, accuracy: 0.5, "\(c.profile.name) \(c.correction.fit) x at \(point)")
                XCTAssertEqual(Double(shown.y), expected.y, accuracy: 0.5, "\(c.profile.name) \(c.correction.fit) y at \(point)")
            }
        }
    }

    func testRenderedCirclesHaveTheSamePhysicalAxisRatioInThePreviewAndTheRealSlot() throws {
        for c in cases {
            let (coordinator, _, slot, _) = realOutput(c)
            let (view, _) = preview(c, deviceAspect: coordinator.deviceAspect)
            let t = try XCTUnwrap(view.previewTransform)
            let par: Double = c.correction.pixelAspect.resolved(screen: c.profile.pixelAspect)

            let real = RehearsalBitmap(slot, scale: 1)
            XCTAssertTrue(real.isWhite(real.width / 2, real.height / 2), "the central circle is at the slot centre")
            let realPhysical: Double = real.ratio(real.width / 2, real.height / 2) * par

            let scale: CGFloat = 2
            let shown = RehearsalBitmap(view, scale: scale)
            let cx = Int(CGFloat(t.originX + t.frameWidth / 2) * scale), cy = Int(CGFloat(t.originY + t.frameHeight / 2) * scale)
            XCTAssertTrue(shown.isWhite(cx, cy), "the central circle is at the preview frame's centre")
            let previewPhysical: Double = shown.ratio(cx, cy)   // the preview frame is already physical

            XCTAssertEqual(previewPhysical / realPhysical, 1, accuracy: 0.02, "\(c.profile.name) \(c.correction.fit) PAR \(par)")
            if c.correction.fit != .stretch {
                XCTAssertEqual(previewPhysical, 1, accuracy: 0.03, "round on the glass, round in the preview")
            }
        }
    }

    func testTheSurroundIsNotBlackSoBarsShow() {
        let (view, _) = preview(cases[0], deviceAspect: Double(portrait.width / portrait.height))
        let bitmap = RehearsalBitmap(view, scale: 1)
        let t = view.previewTransform!
        let barX = Int(t.originX + 5), surroundY = Int(t.originY) - 5
        XCTAssertFalse(bitmap.isWhite(barX, Int(t.originY + t.frameHeight / 2)), "the pillarbox bar is black")
        if surroundY > 0 {
            XCTAssertFalse(bitmap.isWhite(barX, surroundY))
        }
        XCTAssertEqual(view.accessibilityLabel, "Previewing 16 by 9 display, fit, pillarbox")
    }

    // MARK: - T07: the test grid card (OUT-012-R5)

    func testTheCardGridTogglesAndSizesFromItsBounds() {
        let card = RehearsalCardView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        card.layoutIfNeeded()
        let on = RehearsalBitmap(card, scale: 1)
        XCTAssertTrue(on.isWhite(200, 150), "the crosshair crosses at the centre")
        card.showsGrid = false
        let off = RehearsalBitmap(card, scale: 1)
        XCTAssertFalse(off.isWhite(200, 150), "no grid: only the card")
        let box = RehearsalCardView.gridPath(in: CGRect(x: 0, y: 0, width: 400, height: 300)).boundingBox
        XCTAssertEqual(box.width, 400, accuracy: 0.5, "the crosshair spans the picture")
    }

    // MARK: - T08: exit and takeover (OUT-012-S3, R6, R8)

    func testASettledRealDisplayEndsTheRehearsalAndTheVisualStaysOnTheDevice() {
        let coordinator = ExternalDisplayCoordinator()
        let device = VisualSlotView(role: .device)
        device.frame = CGRect(origin: .zero, size: portrait)
        let visual = UIView()
        coordinator.registerDeviceSlot(device)
        coordinator.show(visual)
        coordinator.visualizerActive(true)

        XCTAssertTrue(coordinator.beginRehearsal())
        XCTAssertTrue(coordinator.isRehearsing)
        XCTAssertTrue(visual.superview === device, "rehearsal never moves the visual (OUT-012-R8)")

        let slot = VisualSlotView(role: .external)
        slot.frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        coordinator.externalConnected(id: "a", slot: slot, geometry: ExternalDisplayGeometry(width: 1920, height: 1080, scale: 1),
                                      foreground: true)
        XCTAssertFalse(coordinator.isRehearsing, "the real output takes over")
        XCTAssertTrue(coordinator.hasExternalDisplay)
        XCTAssertTrue(visual.superview === slot)
        XCTAssertFalse(coordinator.beginRehearsal(), "not offered while a real display is connected")

        coordinator.externalDisconnected(id: "a")
        XCTAssertFalse(coordinator.hasExternalDisplay)
        XCTAssertTrue(coordinator.beginRehearsal())
        coordinator.endRehearsal()
        XCTAssertFalse(coordinator.isRehearsing, "Done")
    }

    func testABounceThatNeverSettlesDoesNotEndTheRehearsal() {
        var pending: [@MainActor () -> Void] = []
        let coordinator = ExternalDisplayCoordinator(connectSettle: 0.3) { (_: Double, body: @escaping @MainActor () -> Void) -> Void in
            pending.append { body() }
        }
        XCTAssertTrue(coordinator.beginRehearsal())
        let slot = VisualSlotView(role: .external)
        coordinator.externalConnected(id: "b", slot: slot, geometry: ExternalDisplayGeometry(width: 1920, height: 1080, scale: 1),
                                      foreground: true)
        coordinator.externalDisconnected(id: "b")
        for fire in pending { fire() }
        XCTAssertTrue(coordinator.isRehearsing, "a connection that never settled changes nothing")
        XCTAssertFalse(coordinator.hasExternalDisplay)
    }
}
