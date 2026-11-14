// SplitEditorLayout.swift — UIX-007 (specs/205-uix-007-split-preview-editor): the geometry of the iPad
// split preview/editor: the live output on the leading side, a divider, the editor on the trailing side.
//
// Pure value type (no UI import), so it is tested on the host and on Linux (like UIX-005's
// PerformanceLayout). Research UIX-007-D1: the output keeps the window's shape and is scaled uniformly
// into its pane, so its rect's aspect equals the output aspect exactly; D3: editor 320-560 pt, an output
// pane of at least 320 pt, a 24 pt divider, snaps at 320 / 400 / 480 pt within 24 pt.

/// The split editor's geometry for one window (UIX-007-R2, R3, R5, R6).
public struct SplitEditorLayout: Equatable, Sendable {
    /// A rectangle in points (window coordinates, origin top leading).
    public struct Rect: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        public var maxX: Double { x + width }
        public var maxY: Double { y + height }
        /// Width ÷ height (0 when the height is 0).
        public var aspect: Double { height > 0 ? width / height : 0 }

        /// Whether `other` lies inside this rectangle, allowing `tolerance` points of rounding.
        public func contains(_ other: Rect, tolerance: Double = 1e-9) -> Bool {
            other.x >= x - tolerance && other.y >= y - tolerance
                && other.maxX <= maxX + tolerance && other.maxY <= maxY + tolerance
        }
    }

    /// A named snap point of the editor width.
    public struct Snap: Equatable, Sendable {
        public let width: Double
        public let name: String
    }

    public static let minEditorWidth: Double = 320
    public static let maxEditorLimit: Double = 560
    public static let minOutputWidth: Double = 320
    public static let dividerWidth: Double = 24
    public static let defaultEditorWidth: Double = 400
    public static let snapRadius: Double = 24
    public static let snaps: [Snap] = [Snap(width: 320, name: "Narrow"), Snap(width: 400, name: "Standard"),
                                       Snap(width: 480, name: "Wide")]
    /// The narrowest window that fits the split (664 pt).
    public static let minContainerWidth: Double = minEditorWidth + dividerWidth + minOutputWidth

    public let containerWidth: Double
    public let containerHeight: Double
    /// Width ÷ height of the output (the full window's shape unless given).
    public let outputAspect: Double
    /// Whether the window is wide enough for the split (else Settings stays a sheet).
    public let fits: Bool
    /// The widest editor this window allows (≥ `minEditorWidth` when `fits`).
    public let maxEditorWidth: Double
    /// The requested width clamped to the bounds.
    public let editorWidth: Double
    /// The leading pane that holds the output.
    public let outputPane: Rect
    /// The divider's hit area.
    public let divider: Rect
    /// The editor's pane.
    public let editorPane: Rect
    /// The output as shown: `outputAspect` exactly, scaled to fit the pane and centred in it.
    public let outputRect: Rect
    /// The uniform scale from the full-window output to `outputRect`.
    public let scale: Double

    /// - Parameters:
    ///   - containerWidth: the window's width in points.
    ///   - containerHeight: the window's height in points.
    ///   - editorWidth: the requested (stored or dragged) editor width; non-finite → the default.
    ///   - outputAspect: the output's width ÷ height; nil, non-finite or ≤ 0 → the window's.
    public init(containerWidth: Double, containerHeight: Double, editorWidth: Double, outputAspect: Double? = nil) {
        let width: Double = max(0, containerWidth.isFinite ? containerWidth : 0)
        let height: Double = max(0, containerHeight.isFinite ? containerHeight : 0)
        self.containerWidth = width
        self.containerHeight = height
        let windowAspect: Double = height > 0 ? width / height : 1
        let aspect: Double = outputAspect.flatMap { (a: Double) -> Double? in a.isFinite && a > 0 ? a : nil } ?? windowAspect
        self.outputAspect = aspect > 0 ? aspect : 1
        fits = width >= Self.minContainerWidth && height > 0
        let maxEditor: Double = max(Self.minEditorWidth, min(Self.maxEditorLimit, width - Self.dividerWidth - Self.minOutputWidth))
        maxEditorWidth = maxEditor
        let editor: Double = Self.clamp(editorWidth, max: maxEditor)
        self.editorWidth = editor
        let paneWidth: Double = max(0, width - Self.dividerWidth - editor)
        outputPane = Rect(x: 0, y: 0, width: paneWidth, height: height)
        divider = Rect(x: paneWidth, y: 0, width: Self.dividerWidth, height: height)
        editorPane = Rect(x: paneWidth + Self.dividerWidth, y: 0, width: editor, height: height)
        let fitted: (rect: Rect, scale: Double) = Self.fit(aspect: self.outputAspect, fullHeight: height, in: outputPane)
        outputRect = fitted.rect
        scale = fitted.scale
    }

    /// The requested width within `minEditorWidth ... max`; non-finite → the default (clamped).
    static func clamp(_ requested: Double, max upper: Double) -> Double {
        let value: Double = requested.isFinite ? requested : defaultEditorWidth
        return Swift.min(upper, Swift.max(minEditorWidth, value))
    }

    /// The output (full height `fullHeight`, width `aspect × fullHeight`) scaled uniformly to fit `pane`, centred.
    static func fit(aspect: Double, fullHeight: Double, in pane: Rect) -> (rect: Rect, scale: Double) {
        guard fullHeight > 0, pane.width > 0, pane.height > 0 else {
            return (Rect(x: pane.x, y: pane.y, width: 0, height: 0), 0)
        }
        let fullWidth: Double = aspect * fullHeight
        let scale: Double = Swift.min(pane.width / fullWidth, pane.height / fullHeight)
        // Derive one side from the other through the aspect so the rect's aspect is exact (no drift from two products).
        let byWidth: Bool = pane.width / fullWidth <= pane.height / fullHeight
        let w: Double = byWidth ? pane.width : pane.height * aspect
        let h: Double = byWidth ? pane.width / aspect : pane.height
        let rect = Rect(x: pane.x + (pane.width - w) / 2, y: pane.y + (pane.height - h) / 2, width: w, height: h)
        return (rect, scale)
    }

    // MARK: - Snapping and stepping (UIX-007-R5, R6)

    /// A released width: the nearest snap point within `snapRadius` that the window allows, else the clamped width.
    public func snapped(_ width: Double) -> Double {
        let clamped: Double = Self.clamp(width, max: maxEditorWidth)
        let reachable: [Snap] = Self.snaps.filter { (s: Snap) -> Bool in s.width <= maxEditorWidth }
        guard let nearest = reachable.min(by: { (a: Snap, b: Snap) -> Bool in abs(a.width - clamped) < abs(b.width - clamped) }),
              abs(nearest.width - clamped) <= Self.snapRadius else { return clamped }
        return nearest.width
    }

    /// The stops an adjustable step moves through: the reachable snap points, then the maximum.
    var stops: [Double] {
        var values: [Double] = Self.snaps.map { (s: Snap) -> Double in s.width }.filter { (w: Double) -> Bool in w <= maxEditorWidth }
        if let last = values.last, last < maxEditorWidth { values.append(maxEditorWidth) }
        return values
    }

    /// The next stop wider than `width` (or the maximum).
    public func nextSnap(after width: Double) -> Double {
        stops.first { (w: Double) -> Bool in w > width + 1e-9 } ?? maxEditorWidth
    }

    /// The previous stop narrower than `width` (or the minimum).
    public func previousSnap(before width: Double) -> Double {
        stops.last { (w: Double) -> Bool in w < width - 1e-9 } ?? Self.minEditorWidth
    }

    /// The snap point's name when `width` is one ("Standard"), else nil.
    public static func snapName(for width: Double) -> String? {
        snaps.first { (s: Snap) -> Bool in abs(s.width - width) < 0.5 }?.name
    }
}
