// PerformanceLayout.swift — UIX-005 (specs/193-uix-005-performance-controls): the geometry of the
// performance pad (Previous cue, Next cue, Tap tempo, Blackout) from the space the visualizer has.
//
// Pure value type (no UI import), so it is tested on the host and on Linux. Research UIX-005-D1:
// the arrangement follows the space (wider than tall → side columns), not the device orientation;
// D2: 60 pt targets, 72 pt when both size classes are regular; a bar that does not fit one row wraps
// to two rows of two; D3: the pad reports the edges it reserves so nothing else sits under it.

/// The performance pad's geometry for one area (UIX-005-R3, R4).
public struct PerformanceLayout: Equatable, Sendable {
    public enum Arrangement: String, Equatable, Sendable {
        /// One row at the bottom (portrait-shaped area).
        case bottomBar
        /// Two rows of two at the bottom (an area too narrow for one row).
        case bottomGrid
        /// Cue targets in a leading column, tempo and blackout in a trailing one (landscape-shaped area).
        case sideColumns
    }

    /// Edges the pad uses, which the rest of the visualizer keeps clear.
    public struct Insets: Equatable, Sendable {
        public var top: Double
        public var leading: Double
        public var bottom: Double
        public var trailing: Double

        public init(top: Double = 0, leading: Double = 0, bottom: Double = 0, trailing: Double = 0) {
            self.top = top
            self.leading = leading
            self.bottom = bottom
            self.trailing = trailing
        }
    }

    /// The smallest target side (Apple's minimum is 44 pt; larger on purpose, UIX-005-D2).
    public static let compactTarget: Double = 60
    /// The target side when both size classes are regular (iPad).
    public static let regularTarget: Double = 72
    /// Space around the pad inside the safe area.
    public static let margin: Double = 8
    /// The number of targets.
    public static let targetCount = 4

    public let arrangement: Arrangement
    /// The side of each square target, in points.
    public let target: Double
    /// Space between targets.
    public let spacing: Double

    public var margin: Double { Self.margin }
    /// The width of one side column: a target with the margin on both sides.
    public var columnWidth: Double { target + 2 * Self.margin }

    /// - Parameters:
    ///   - width: the safe area's width.
    ///   - height: the safe area's height.
    ///   - regular: both the horizontal and the vertical size classes are regular.
    public init(width: Double, height: Double, regular: Bool) {
        let target: Double = regular ? Self.regularTarget : Self.compactTarget
        let spacing: Double = regular ? 16 : 12
        self.target = target
        self.spacing = spacing
        if width > height {
            arrangement = .sideColumns
        } else if Self.rowWidth(target: target, spacing: spacing) <= width {
            arrangement = .bottomBar
        } else {
            arrangement = .bottomGrid
        }
    }

    /// The width one row of all targets needs, margins included.
    public static func rowWidth(target: Double, spacing: Double) -> Double {
        let count = Double(targetCount)
        return count * target + (count - 1) * spacing + 2 * margin
    }

    /// The edges the pad reserves. For a bar, `barHeight` is its measured height (readouts and targets).
    public func reservedInsets(barHeight: Double) -> Insets {
        switch arrangement {
        case .sideColumns:
            Insets(leading: columnWidth, trailing: columnWidth)
        case .bottomBar, .bottomGrid:
            Insets(bottom: max(0, barHeight) + Self.margin)
        }
    }
}
