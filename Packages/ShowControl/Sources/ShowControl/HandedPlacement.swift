// HandedPlacement.swift — ACC-010 (specs/248-acc-010-left-handed-layout, contract C1): which side the performance
// controls favour, and where UIX-005's pad puts each target on that side.
//
// Pure value types (no UI import), tested on the host and on Linux beside `PerformanceLayout` and `OneHandedLayout`.
// Research ACC-010-D1: slots are explicit, never a layout-direction flip, so text and symbols are untouched. D3: the
// left-handed rows are the right-handed rows reversed, then Previous cue takes the left slot of the cue pair (its arrow
// points backward); side columns swap whole. D2: ACC-009's one-handed hand, while active, decides the side.

/// The side the edge-anchored performance controls favour (ACC-010-R6).
public enum ControlsSide: String, CaseIterable, Equatable, Sendable {
    case right, left

    /// The one-handed hand while ACC-009's layout is active (non-nil), else the Left-handed controls switch.
    public static func resolve(oneHanded: OneHandedHand?, leftHanded: Bool) -> ControlsSide {
        if let hand = oneHanded { return hand == .left ? .left : .right }
        return leftHanded ? .left : .right
    }
}

/// UIX-005's four pad targets.
public enum PadTarget: String, CaseIterable, Equatable, Hashable, Sendable {
    case previousCue, nextCue, tapTempo, blackout

    /// The pad's accessibility identifier (UIX-005; unchanged on both sides, ACC-010-R5).
    public var identifier: String {
        switch self {
        case .previousCue: "perfPreviousCue"
        case .nextCue: "perfNextCue"
        case .tapTempo: "perfTapTempo"
        case .blackout: "perfBlackout"
        }
    }

    /// True for the directional cue pair, which keeps its reading order (research ACC-010-D3).
    public var isCue: Bool { self == .previousCue || self == .nextCue }
}

/// Where the pad's targets and readouts go for one side (contract C1).
public struct PadPlacement: Equatable, Sendable {
    /// Bar: one row; grid: two rows; left to right.
    public let rows: [[PadTarget]]
    /// Side columns, top to bottom.
    public let leadingColumn: [PadTarget]
    public let trailingColumn: [PadTarget]
    /// The cue readout is on the left (the tempo readout takes the other side).
    public let cueReadoutLeading: Bool

    /// The right-handed placement (UIX-005 as built) for an arrangement.
    static func right(_ arrangement: PerformanceLayout.Arrangement) -> PadPlacement {
        let rows: [[PadTarget]] = arrangement == .bottomGrid
            ? [[.previousCue, .nextCue], [.tapTempo, .blackout]]
            : [[.previousCue, .nextCue, .tapTempo, .blackout]]
        return PadPlacement(rows: rows, leadingColumn: [.previousCue, .nextCue], trailingColumn: [.tapTempo, .blackout],
                            cueReadoutLeading: true)
    }

    /// The horizontal mirror: rows reversed with the cue pair kept in reading order; columns swapped.
    public var mirrored: PadPlacement {
        let mirroredRows: [[PadTarget]] = rows.map { (row: [PadTarget]) -> [PadTarget] in Self.keepCueOrder(row.reversed()) }
        return PadPlacement(rows: mirroredRows, leadingColumn: trailingColumn, trailingColumn: leadingColumn,
                            cueReadoutLeading: !cueReadoutLeading)
    }

    /// Puts Previous cue before Next cue within the slots the pair occupies.
    private static func keepCueOrder(_ row: [PadTarget]) -> [PadTarget] {
        var result: [PadTarget] = row
        if let p = result.firstIndex(of: .previousCue), let n = result.firstIndex(of: .nextCue), n < p {
            result.swapAt(p, n)
        }
        return result
    }

    /// Every target placed (the same set on both sides, ACC-010-R5).
    public var targets: Set<PadTarget> { Set(rows.flatMap { (row: [PadTarget]) -> [PadTarget] in row }) }
}

extension PerformanceLayout {
    /// The placement for a side (contract C1).
    public func placement(_ side: ControlsSide) -> PadPlacement {
        let right: PadPlacement = PadPlacement.right(arrangement)
        return side == .right ? right : right.mirrored
    }

    /// Each target's frame in safe-area coordinates (origin top-left), following the pad view's stacks: a bar or grid
    /// centred at the bottom, side columns inset by the margin and centred vertically under a readout of
    /// `readoutHeight`. Used to prove the mirror (ACC-010-S1); the UI test checks the drawn frames.
    public func targetFrames(width: Double, height: Double, side: ControlsSide,
                             readoutHeight: Double = 0) -> [PadTarget: OneHandedLayout.Rect] {
        let place: PadPlacement = placement(side)
        var frames: [PadTarget: OneHandedLayout.Rect] = [:]
        switch arrangement {
        case .sideColumns:
            let total: Double = readoutHeight + 2 * spacing + 2 * target
            let firstY: Double = (height - total) / 2 + readoutHeight + spacing
            let columns: [(x: Double, targets: [PadTarget])] = [
                (margin, place.leadingColumn), (width - margin - target, place.trailingColumn),
            ]
            for column in columns {
                for (index, item) in column.targets.enumerated() {
                    let y: Double = firstY + Double(index) * (target + spacing)
                    frames[item] = OneHandedLayout.Rect(x: column.x, y: y, width: target, height: target)
                }
            }
        case .bottomBar, .bottomGrid:
            let rowCount: Int = place.rows.count
            for (rowIndex, row) in place.rows.enumerated() {
                let count: Double = Double(row.count)
                let rowWidth: Double = count * target + (count - 1) * spacing
                let left: Double = (width - rowWidth) / 2
                let fromBottom: Double = Double(rowCount - rowIndex)
                let y: Double = height - fromBottom * target - (fromBottom - 1) * spacing
                for (index, item) in row.enumerated() {
                    let x: Double = left + Double(index) * (target + spacing)
                    frames[item] = OneHandedLayout.Rect(x: x, y: y, width: target, height: target)
                }
            }
        }
        return frames
    }
}
