// RehearsalPreviewView.swift — OUT-012 (spec specs/184-out-012-display-rehearsal; research OUT-012-D1,
// D2, D4): the device-side preview of an external display that is not connected.
//
// It hosts a real `VisualSlotView(role: .external)` the size of the profile's slot, with the profile's
// pixel aspect ratio as its stand-in PAR and the user's OUT-004 correction and device shape, so the
// slot lays its content out by the very code the real external output uses (bounds, centre, 1/PAR
// scale; black bars; clipped crop). The whole slot is then scaled by the rehearsal's preview transform
// (s·PAR, s) into this view, so the frame has the display's physical shape. A grey surround and an
// outline make the black bars visible. The content is a test card, never the live visual (OUT-012-R8).
import PresentationLifecycle
import UIKit

final class RehearsalPreviewView: UIView {
    /// The slot standing in for the external display (tests read its placement).
    let slot = VisualSlotView(role: .external)
    /// What the slot holds: the test card in the app, a circle grid in the tests.
    let content: UIView
    private let outline = CALayer()
    private(set) var rehearsal: ExternalOutputRehearsal?
    /// The transform last applied to the slot (tests).
    private(set) var previewTransform: RehearsalPreviewTransform?

    init(content: UIView) {
        self.content = content
        super.init(frame: .zero)
        backgroundColor = UIColor(white: 0.32, alpha: 1)   // the surround: bars stay visibly black
        clipsToBounds = true
        isUserInteractionEnabled = false
        outline.borderColor = UIColor(white: 0.85, alpha: 1).cgColor
        outline.borderWidth = 1
        outline.actions = ["bounds": NSNull(), "position": NSNull(), "frame": NSNull()]
        addSubview(slot)
        layer.addSublayer(outline)
        slot.hold(content)
        isAccessibilityElement = true
        accessibilityTraits = .image
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Shows `rehearsal`: the slot takes the profile's size and PAR and the correction; laid out now.
    func apply(_ rehearsal: ExternalOutputRehearsal) {
        self.rehearsal = rehearsal
        slot.standInPixelAspect = rehearsal.profile.pixelAspect
        slot.correction = rehearsal.correction
        slot.deviceAspect = rehearsal.deviceAspect
        accessibilityLabel = rehearsal.spokenDescription
        layoutPreview()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutPreview()
    }

    private func layoutPreview() {
        guard let rehearsal else { return }
        let t: RehearsalPreviewTransform = rehearsal.preview(width: Double(bounds.width), height: Double(bounds.height))
        previewTransform = t
        let slotSize = CGSize(width: CGFloat(rehearsal.profile.width), height: CGFloat(rehearsal.profile.height))
        let transform: CGAffineTransform = t.scaleX > 0
            ? CGAffineTransform(scaleX: CGFloat(t.scaleX), y: CGFloat(t.scaleY)) : CGAffineTransform(scaleX: 0.0001, y: 0.0001)
        // Bounds, centre and transform (never `frame`, which a transform makes undefined).
        slot.transform = .identity
        slot.bounds = CGRect(origin: .zero, size: slotSize)
        slot.center = CGPoint(x: CGFloat(t.originX + t.frameWidth / 2), y: CGFloat(t.originY + t.frameHeight / 2))
        slot.transform = transform
        slot.layoutIfNeeded()   // the OUT-004 placement for the new size, inside the call
        content.layoutIfNeeded()
        let frame = CGRect(x: CGFloat(t.originX), y: CGFloat(t.originY), width: CGFloat(t.frameWidth), height: CGFloat(t.frameHeight))
        outline.frame = frame.insetBy(dx: -1, dy: -1)
    }
}

/// OUT-012-D4: the stand-in picture: the source's bounds filled with a dark gradient-like tone, its
/// edges outlined, and (optional, OUT-012-R5) a test grid: 3 × 3 circles, a large centre circle and a
/// crosshair, sized from its own bounds as every visual is.
final class RehearsalCardView: UIView {
    private let edge = CAShapeLayer()
    private let grid = CAShapeLayer()

    var showsGrid: Bool = true {
        didSet { grid.isHidden = !showsGrid }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 0.10, green: 0.16, blue: 0.30, alpha: 1)
        edge.fillColor = nil
        edge.strokeColor = UIColor.systemTeal.cgColor
        grid.fillColor = nil
        grid.strokeColor = UIColor.white.cgColor
        for shape in [edge, grid] {
            shape.actions = ["path": NSNull(), "bounds": NSNull(), "position": NSNull(), "hidden": NSNull()]
            layer.addSublayer(shape)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let side: CGFloat = min(bounds.width, bounds.height)
        let line: CGFloat = max(side * 0.006, 1)
        edge.frame = bounds
        grid.frame = bounds
        edge.lineWidth = line * 2
        grid.lineWidth = line
        edge.path = CGPath(rect: bounds.insetBy(dx: line, dy: line), transform: nil)
        grid.path = Self.gridPath(in: bounds)
    }

    /// Circles of radius 0.14 · the short side on a 2.4-radius pitch, a centre circle of 0.45 · the short
    /// side and a full-size crosshair.
    static func gridPath(in bounds: CGRect) -> CGPath {
        let path = CGMutablePath()
        let radius: CGFloat = min(bounds.width, bounds.height) * 0.14
        let step: CGFloat = radius * 2.4
        for row in -1...1 {
            for column in -1...1 {
                let x: CGFloat = bounds.midX + CGFloat(column) * step
                let y: CGFloat = bounds.midY + CGFloat(row) * step
                path.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
            }
        }
        let big: CGFloat = min(bounds.width, bounds.height) * 0.45
        path.addEllipse(in: CGRect(x: bounds.midX - big, y: bounds.midY - big, width: big * 2, height: big * 2))
        path.move(to: CGPoint(x: bounds.minX, y: bounds.midY))
        path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.midY))
        path.move(to: CGPoint(x: bounds.midX, y: bounds.minY))
        path.addLine(to: CGPoint(x: bounds.midX, y: bounds.maxY))
        return path
    }
}
