// CornerPinCardLayer.swift — OUT-007-T03 (spec specs/264-out-007-corner-pin, contract C2; research OUT-007-D4):
// the calibration pattern an external slot shows while the corner-pin editor is open. It is OUT-012's test
// card (an outlined edge, 3 × 3 circles, a centre circle and a crosshair, `RehearsalCardView.gridPath`) drawn
// as layers over an opaque background, filling the whole output so its edges show where the output's corners
// land. A layer, not a subview: the slot still holds only the visual (OUT-001, OUT-002 counts). It sits above
// the visual (zPosition 5 000) and below OUT-010's cover (10 000), so a blackout still blacks everything out.
import UIKit

final class CornerPinCardLayer: CALayer {
    private let edge = CAShapeLayer()
    private let grid = CAShapeLayer()

    override init() {
        super.init()
        backgroundColor = UIColor(red: 0.10, green: 0.16, blue: 0.30, alpha: 1).cgColor
        isOpaque = true
        zPosition = 5_000
        isHidden = true
        edge.fillColor = nil
        edge.strokeColor = UIColor.systemTeal.cgColor
        grid.fillColor = nil
        grid.strokeColor = UIColor.white.cgColor
        let still: [String: any CAAction] = ["path": NSNull(), "bounds": NSNull(), "position": NSNull(),
                                             "hidden": NSNull(), "frame": NSNull()]
        actions = still
        for shape in [edge, grid] {
            shape.actions = still
            addSublayer(shape)
        }
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSublayers() {
        super.layoutSublayers()
        let side: CGFloat = min(bounds.width, bounds.height)
        let line: CGFloat = max(side * 0.006, 1)
        edge.frame = bounds
        grid.frame = bounds
        edge.lineWidth = line * 2
        grid.lineWidth = line
        edge.path = CGPath(rect: bounds.insetBy(dx: line, dy: line), transform: nil)
        grid.path = RehearsalCardView.gridPath(in: bounds)
    }
}
