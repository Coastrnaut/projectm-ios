// OneHandedLayout.swift — ACC-009 (specs/244-acc-009-one-handed-mode, contract C1, C2): the one-handed layout's
// critical actions and their geometry in a thumb zone.
//
// Pure value types (no UI import), tested on the host and on Linux, beside UIX-005's `PerformanceLayout`.
// Research ACC-009-D1: the thumb zone is the bottom corner of the safe area on the chosen side (portrait-shaped
// area: bottom 40 % × 75 % of the width; landscape-shaped: 40 % of the width × bottom 75 %). D2: rows fill from the
// zone's bottom upward, each aligned to the chosen edge: the pad group first (nearest the thumb), then the main group,
// Stop last (farthest). Main targets shrink in 4 pt steps to 44 pt when the stack is too tall; no action is dropped.

/// The hand that holds the phone (ACC-009-R1). Absent = the standard layout.
public enum OneHandedHand: String, CaseIterable, Equatable, Sendable {
    case left, right
}

/// The actions the one-handed layout must keep reachable (ACC-009-R2), in layout order.
public enum CriticalAction: String, CaseIterable, Equatable, Hashable, Sendable {
    // Pad group (UIX-005's four targets).
    case cuePrevious, cueNext, tapTempo, blackout
    // Main group (FR-082's main row, Stop last).
    case previous, next, random, pauseResume, presets, settings, stop

    /// True for the four actions the UIX-005 pad carries.
    public var isPadAction: Bool {
        switch self {
        case .cuePrevious, .cueNext, .tapTempo, .blackout: true
        default: false
        }
    }

    /// The standard controls' accessibility identifier (ACC-009-D4).
    public var identifier: String {
        switch self {
        case .cuePrevious: "showPreviousCue"
        case .cueNext: "showNextCue"
        case .tapTempo: "tapTempo"
        case .blackout: "blackout"
        case .previous: "previous"
        case .next: "next"
        case .random: "random"
        case .pauseResume: "pauseResume"
        case .presets: "presets"
        case .settings: "settings"
        case .stop: "stop"
        }
    }

    /// The performance pad's identifier for a pad action (UIX-005), nil for the main group.
    public var padIdentifier: String? {
        switch self {
        case .cuePrevious: "perfPreviousCue"
        case .cueNext: "perfNextCue"
        case .tapTempo: "perfTapTempo"
        case .blackout: "perfBlackout"
        default: nil
        }
    }
}

/// The state that decides which critical actions exist (contract C2).
public struct CriticalActionContext: Equatable, Sendable {
    /// The show has at least one cue (SHOW-001-R13).
    public var hasCues: Bool
    /// UIX-005's performance pad is on.
    public var padOn: Bool
    /// A native visual is shown: no preset actions (VIS-001-R13).
    public var alternateVisual: Bool
    /// The controls are shown.
    public var controlsVisible: Bool

    public init(hasCues: Bool, padOn: Bool, alternateVisual: Bool, controlsVisible: Bool) {
        self.hasCues = hasCues
        self.padOn = padOn
        self.alternateVisual = alternateVisual
        self.controlsVisible = controlsVisible
    }
}

extension CriticalAction {
    /// The critical actions the standard layout offers with the controls shown (and the pad, when on), in layout order.
    public static func standard(_ context: CriticalActionContext) -> [CriticalAction] {
        allCases.filter { (action: CriticalAction) -> Bool in
            switch action {
            case .cuePrevious, .cueNext: context.hasCues || context.padOn
            case .previous, .next, .random, .presets: !context.alternateVisual
            default: true
            }
        }
    }

    /// What the one-handed layout draws now: everything with the controls; without them, the pad group while the pad is on.
    public static func displayed(_ context: CriticalActionContext) -> [CriticalAction] {
        let all: [CriticalAction] = standard(context)
        if context.controlsVisible { return all }
        return context.padOn ? all.filter { (action: CriticalAction) -> Bool in action.isPadAction } : []
    }
}

/// The one-handed layout's geometry for one safe area (contract C1). Coordinates are in points, origin at the safe
/// area's top-left corner.
public struct OneHandedLayout: Equatable, Sendable {
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
        public var midX: Double { x + width / 2 }
        public var midY: Double { y + height / 2 }

        /// True when `other` lies wholly inside this rectangle (a tolerance of 0.01 pt for rounding).
        public func contains(_ other: Rect) -> Bool {
            let e = 0.01
            return other.x >= x - e && other.y >= y - e && other.maxX <= maxX + e && other.maxY <= maxY + e
        }

        /// True when the two rectangles share any area.
        public func intersects(_ other: Rect) -> Bool {
            x < other.maxX && other.x < maxX && y < other.maxY && other.y < maxY
        }
    }

    /// Apple's minimum target side; the base never goes below it (ACC-009-R4).
    public static let minimumTarget: Double = 44
    /// The largest Dynamic Type base side.
    public static let maximumTarget: Double = 56
    public static let margin: Double = 8
    public static let spacing: Double = 8
    /// The shrink step when the stack is too tall.
    public static let shrinkStep: Double = 4
    /// Thumb-zone fractions (research ACC-009-D1): the short side's share and the long side's share.
    public static let zoneShortFraction: Double = 0.4
    public static let zoneLongFraction: Double = 0.75

    public let width: Double
    public let height: Double
    public let hand: OneHandedHand
    /// The thumb zone.
    public let zone: Rect
    /// The main group's side after any shrinking.
    public let baseTarget: Double
    /// The pad group's side (the UIX-005 size while the pad is on, else the base side).
    public let padTarget: Double
    /// One frame per placed action, in layout order.
    public let frames: [(action: CriticalAction, rect: Rect)]
    /// True when every frame lies inside the zone.
    public let fits: Bool
    /// The height kept for the pad's readouts above the cluster in a portrait-shaped area (0: no readouts).
    public let readoutHeight: Double

    public static func == (lhs: OneHandedLayout, rhs: OneHandedLayout) -> Bool {
        lhs.width == rhs.width && lhs.height == rhs.height && lhs.hand == rhs.hand && lhs.zone == rhs.zone
            && lhs.baseTarget == rhs.baseTarget && lhs.padTarget == rhs.padTarget && lhs.fits == rhs.fits
            && lhs.readoutHeight == rhs.readoutHeight
            && lhs.frames.map(\.action) == rhs.frames.map(\.action) && lhs.frames.map(\.rect) == rhs.frames.map(\.rect)
    }

    /// The Dynamic Type base side: the scaled 44 pt clamped to 44…56 (research ACC-009-D5).
    public static func baseTarget(scaled: Double) -> Double {
        min(max(scaled, minimumTarget), maximumTarget)
    }

    /// True for an area wider than tall (the arrangement follows the area's shape, as UIX-005-D1).
    public var isLandscape: Bool { width > height }

    /// - Parameters:
    ///   - width: the safe area's width.
    ///   - height: the safe area's height.
    ///   - hand: the holding hand.
    ///   - baseTarget: the main group's side (`baseTarget(scaled:)`).
    ///   - padTarget: the pad's side while UIX-005's pad is on, nil otherwise.
    ///   - actions: the actions to place (`CriticalAction.displayed`); placed in `CriticalAction.allCases` order.
    public init(width: Double, height: Double, hand: OneHandedHand, baseTarget: Double, padTarget: Double?,
                actions: [CriticalAction], readoutHeight: Double = 0) {
        self.width = width
        self.height = height
        self.hand = hand
        self.readoutHeight = max(0, readoutHeight)
        let zone: Rect = Self.zone(width: width, height: height, hand: hand)
        self.zone = zone
        let wanted: Set<CriticalAction> = Set(actions)
        let ordered: [CriticalAction] = CriticalAction.allCases.filter { (action: CriticalAction) -> Bool in wanted.contains(action) }
        let start: Double = Self.baseTarget(scaled: baseTarget)
        let pad: Double = max(padTarget ?? start, Self.minimumTarget)
        var base: Double = start
        var placed: [(action: CriticalAction, rect: Rect)] = Self.place(ordered, zone: zone, hand: hand, base: base,
                                                                         pad: padTarget == nil ? base : pad)
        while !Self.allInside(placed, zone: zone) && base - Self.shrinkStep >= Self.minimumTarget {
            base -= Self.shrinkStep
            placed = Self.place(ordered, zone: zone, hand: hand, base: base, pad: padTarget == nil ? base : pad)
        }
        self.baseTarget = base
        self.padTarget = padTarget == nil ? base : pad
        frames = placed
        fits = Self.allInside(placed, zone: zone)
    }

    /// The frame of one action, nil when it is not placed.
    public func frame(of action: CriticalAction) -> Rect? {
        frames.first { (entry: (action: CriticalAction, rect: Rect)) -> Bool in entry.action == action }?.rect
    }

    /// The edges the cluster reserves (ACC-009-R5): bottom for a portrait-shaped area, the chosen side for a
    /// landscape-shaped one; zero when nothing is placed. Every frame lies inside the reserved band.
    public var reservedInsets: PerformanceLayout.Insets {
        guard !frames.isEmpty else { return PerformanceLayout.Insets() }
        if isLandscape {
            switch hand {
            case .right:
                let left: Double = frames.map { (entry: (action: CriticalAction, rect: Rect)) -> Double in entry.rect.x }.min() ?? width
                return PerformanceLayout.Insets(trailing: max(0, width - left + Self.margin))
            case .left:
                let right: Double = frames.map { (entry: (action: CriticalAction, rect: Rect)) -> Double in entry.rect.maxX }.max() ?? 0
                return PerformanceLayout.Insets(leading: right + Self.margin)
            }
        }
        let top: Double = frames.map { (entry: (action: CriticalAction, rect: Rect)) -> Double in entry.rect.y }.min() ?? height
        let readouts: Double = readoutHeight > 0 ? readoutHeight + Self.spacing : 0
        return PerformanceLayout.Insets(bottom: max(0, height - top + Self.margin + readouts))
    }

    /// The part of the safe area the reserved band covers.
    public var reservedRect: Rect {
        let insets: PerformanceLayout.Insets = reservedInsets
        if insets.bottom > 0 { return Rect(x: 0, y: height - insets.bottom, width: width, height: insets.bottom) }
        if insets.trailing > 0 { return Rect(x: width - insets.trailing, y: 0, width: insets.trailing, height: height) }
        if insets.leading > 0 { return Rect(x: 0, y: 0, width: insets.leading, height: height) }
        return Rect(x: 0, y: height, width: width, height: 0)
    }

    /// Where the pad's readouts go (ACC-009-R7), inside the reserved band and never over a target: in a portrait-shaped
    /// area a strip of `readoutHeight` above the cluster, across the zone's width; in a landscape-shaped one the band
    /// above the zone.
    public var asideRect: Rect {
        let band: Rect = reservedRect
        if isLandscape { return Rect(x: band.x, y: 0, width: band.width, height: zone.y) }
        return Rect(x: zone.x, y: band.y, width: zone.width, height: readoutHeight)
    }

    // MARK: Geometry

    /// The thumb zone (research ACC-009-D1).
    public static func zone(width: Double, height: Double, hand: OneHandedHand) -> Rect {
        let landscape: Bool = width > height
        let zoneWidth: Double = width * (landscape ? zoneShortFraction : zoneLongFraction)
        let zoneHeight: Double = height * (landscape ? zoneLongFraction : zoneShortFraction)
        let x: Double = hand == .right ? width - zoneWidth : 0
        return Rect(x: x, y: height - zoneHeight, width: zoneWidth, height: zoneHeight)
    }

    private static func allInside(_ frames: [(action: CriticalAction, rect: Rect)], zone: Rect) -> Bool {
        frames.allSatisfy { (entry: (action: CriticalAction, rect: Rect)) -> Bool in zone.contains(entry.rect) }
    }

    /// Rows from the zone's bottom upward: the pad group at `pad`, then the main group at `base`.
    private static func place(_ actions: [CriticalAction], zone: Rect, hand: OneHandedHand, base: Double,
                              pad: Double) -> [(action: CriticalAction, rect: Rect)] {
        let padGroup: [CriticalAction] = actions.filter { (action: CriticalAction) -> Bool in action.isPadAction }
        let mainGroup: [CriticalAction] = actions.filter { (action: CriticalAction) -> Bool in !action.isPadAction }
        var result: [(action: CriticalAction, rect: Rect)] = []
        var bottom: Double = zone.maxY - margin
        for (group, side) in [(padGroup, pad), (mainGroup, base)] where !group.isEmpty {
            let rows: [[CriticalAction]] = Self.rows(group, side: side, zoneWidth: zone.width)
            for row in rows {
                let top: Double = bottom - side
                result += Self.lay(row, top: top, side: side, zone: zone, hand: hand)
                bottom = top - spacing
            }
        }
        return result
    }

    /// Splits a group into rows of as many targets as fit the zone's width (at least one per row).
    private static func rows(_ group: [CriticalAction], side: Double, zoneWidth: Double) -> [[CriticalAction]] {
        let usable: Double = zoneWidth - 2 * margin + spacing
        let perRow: Int = max(1, Int((usable / (side + spacing)).rounded(.down)))
        return stride(from: 0, to: group.count, by: perRow).map { (start: Int) -> [CriticalAction] in
            Array(group[start..<min(start + perRow, group.count)])
        }
    }

    /// One row in reading order, aligned to the chosen edge.
    private static func lay(_ row: [CriticalAction], top: Double, side: Double, zone: Rect,
                            hand: OneHandedHand) -> [(action: CriticalAction, rect: Rect)] {
        let count: Double = Double(row.count)
        let rowWidth: Double = count * side + (count - 1) * spacing
        let left: Double = hand == .right ? zone.maxX - margin - rowWidth : zone.x + margin
        return row.enumerated().map { (pair: (offset: Int, element: CriticalAction)) -> (action: CriticalAction, rect: Rect) in
            let x: Double = left + Double(pair.offset) * (side + spacing)
            return (pair.element, Rect(x: x, y: top, width: side, height: side))
        }
    }
}
