// PixelSort.swift — FX-011 "Pixel sorting approximation": the value, its ranges, the frame budget plan, the shader block
// and the CPU reference (specs/310-fx-011-pixel-sorting, contracts/pixel-sort.md C2, C3, research FX-011-D2 to D4;
// ADR-0121). Plain Swift (builds on Linux). The compositor's `cmp_pixel_sort` kernel does the same on the GPU:
//   rows (horizontal) or columns (vertical) are cut into tiles of `span` pixels from the left (top) edge; a pixel
//   qualifies when lum = 0.2126 r + 0.7152 g + 0.0722 b of its stored colour is finite and ≥ threshold; each maximal
//   qualifying run inside a tile is stably sorted by lum ascending in the reading direction; other pixels stay.
// The work per frame is W × H × span steps whatever the picture, capped by `frameBudget` (the span is reduced, else the
// pass is skipped). Off, or a frame under 2 pixels along the direction, runs no pass.
import Foundation

public struct PixelSort: Sendable, Equatable, Codable {
    public enum Direction: String, Sendable, Equatable, Codable, CaseIterable {
        case horizontal
        case vertical
    }

    public static let thresholdRange: ClosedRange<Double> = 0...1
    public static let defaultThreshold = 0.5
    /// VoiceOver step (1 %).
    public static let thresholdStep = 0.01
    /// The span choices (pixels per tile, the longest possible segment).
    public static let spans: [Int] = [4, 8, 16, 32, 64]
    public static let defaultSpan = 32
    public static let maxSpan = 64
    public static let defaultDirection: Direction = .horizontal
    /// FX-011-R6: the hard per-frame workload, in steps (W × H × span): 7680 × 4320 × 4 = 3840 × 2160 × 16.
    public static let frameBudget = 132_710_400

    /// Off (the default; output bit-identical to before FX-011).
    public static let off = PixelSort()

    public var isEnabled: Bool
    public var threshold: Double
    public var span: Int
    public var direction: Direction

    public init(isEnabled: Bool = false, threshold: Double = PixelSort.defaultThreshold, span: Int = PixelSort.defaultSpan,
                direction: Direction = PixelSort.defaultDirection) {
        self.isEnabled = isEnabled
        self.threshold = threshold
        self.span = span
        self.direction = direction
    }

    /// A user value made valid.
    public var clamped: PixelSort {
        PixelSort(isEnabled: isEnabled, threshold: Self.clampThreshold(threshold), span: Self.snapSpan(span),
                  direction: direction)
    }

    /// NaN → the default; out of range (±Inf) → the nearest bound.
    public static func clampThreshold(_ value: Double) -> Double {
        if value.isNaN { return defaultThreshold }
        return min(max(value, thresholdRange.lowerBound), thresholdRange.upperBound)
    }

    /// The largest choice not above `value`, at least the smallest choice.
    public static func snapSpan(_ value: Int) -> Int {
        var best: Int = spans[0]
        for s in spans where s <= value { best = s }
        return best
    }

    /// A stored or scene number made a span (NaN → the default).
    public static func snapSpan(_ value: Double) -> Int {
        if value.isNaN { return defaultSpan }
        let bounded: Double = min(max(value, Double(spans[0])), Double(maxSpan))
        return snapSpan(Int(bounded))
    }

    /// Rec. 709 luminance of a stored (linear, premultiplied) colour, in the shader's order of operations.
    @inline(__always)
    public static func luminance(_ c: SIMD4<Float>) -> Float {
        let r: Float = c.x * 0.2126
        let g: Float = c.y * 0.7152
        let b: Float = c.z * 0.0722
        return (r + g) + b
    }

    // MARK: - Budget (contract C3)

    /// What the compositor encodes for a frame.
    public struct Plan: Sendable, Equatable {
        /// The pass is encoded.
        public var runs: Bool
        /// The span used (0 when not run).
        public var effectiveSpan: Int
        /// W × H × effectiveSpan (0 when not run).
        public var workload: Int
        /// On and large enough, but no span fits the budget.
        public var budgetSkipped: Bool

        public static let none = Plan(runs: false, effectiveSpan: 0, workload: 0, budgetSkipped: false)
    }

    /// The plan for a frame: the largest span ≤ the chosen one whose workload fits `budget`, or a skip.
    public func plan(width: Int, height: Int, budget: Int = PixelSort.frameBudget) -> Plan {
        guard isEnabled, width >= 1, height >= 1 else { return .none }
        let along: Int = direction == .horizontal ? width : height
        guard along >= 2 else { return .none }
        let chosen: Int = Self.snapSpan(span)
        let (pixels, overflow) = width.multipliedReportingOverflow(by: height)
        var effective = 0
        if !overflow {
            for s in Self.spans where s <= chosen {
                let (work, over) = pixels.multipliedReportingOverflow(by: s)
                if !over && work <= budget { effective = s }
            }
        }
        guard effective > 0 else { return Plan(runs: false, effectiveSpan: 0, workload: 0, budgetSkipped: true) }
        return Plan(runs: true, effectiveSpan: effective, workload: pixels * effective, budgetSkipped: false)
    }

    /// The compositor runs the pass for this frame.
    public func isActive(width: Int, height: Int, budget: Int = PixelSort.frameBudget) -> Bool {
        plan(width: width, height: height, budget: budget).runs
    }

    /// The shader block (`CMPPixelSort`, 16 bytes) for an effective span.
    public func block(effectiveSpan: Int) -> Block {
        Block(threshold: Float(Self.clampThreshold(threshold)), span: UInt32(effectiveSpan),
              vertical: direction == .vertical ? 1 : 0, pad: 0)
    }

    /// `CMPPixelSort` in the shader.
    public struct Block: Sendable, Equatable {
        public var threshold: Float
        public var span: UInt32
        public var vertical: UInt32
        public var pad: UInt32

        public init(threshold: Float, span: UInt32, vertical: UInt32, pad: UInt32) {
            self.threshold = threshold
            self.span = span
            self.vertical = vertical
            self.pad = pad
        }
    }

    // MARK: - CPU reference (contract C2)

    /// A pixel qualifies for sorting.
    @inline(__always)
    public static func qualifies(_ c: SIMD4<Float>, threshold: Float) -> Bool {
        let l: Float = luminance(c)
        return l.isFinite && l >= threshold
    }

    /// One line (a row or a column, in reading order) sorted with tiles of `span`.
    public static func referenceLine(_ line: [SIMD4<Float>], span: Int, threshold: Float) -> [SIMD4<Float>] {
        var out: [SIMD4<Float>] = line
        var tileStart = 0
        while tileStart < line.count {
            let tileEnd: Int = min(tileStart + span, line.count)
            var i: Int = tileStart
            while i < tileEnd {
                guard qualifies(line[i], threshold: threshold) else { i += 1; continue }
                var j: Int = i
                while j < tileEnd && qualifies(line[j], threshold: threshold) { j += 1 }
                let run: [(Float, Int)] = (i..<j).map { (k: Int) -> (Float, Int) in (luminance(line[k]), k) }
                let sorted: [(Float, Int)] = run.sorted { (a: (Float, Int), b: (Float, Int)) -> Bool in
                    a.0 < b.0 || (a.0 == b.0 && a.1 < b.1)
                }
                for (offset, item) in sorted.enumerated() { out[i + offset] = line[item.1] }
                i = j
            }
            tileStart = tileEnd
        }
        return out
    }

    /// The whole frame (row-major) sorted with `span` (the effective span), whatever `isEnabled` says.
    public func referenceAlways(_ pixels: [SIMD4<Float>], width: Int, height: Int, span: Int) -> [SIMD4<Float>] {
        let t: Float = Float(Self.clampThreshold(threshold))
        var out: [SIMD4<Float>] = pixels
        if direction == .horizontal {
            for y in 0..<height {
                let row: [SIMD4<Float>] = Array(pixels[(y * width)..<((y + 1) * width)])
                let sorted: [SIMD4<Float>] = Self.referenceLine(row, span: span, threshold: t)
                for x in 0..<width { out[y * width + x] = sorted[x] }
            }
        } else {
            for x in 0..<width {
                let column: [SIMD4<Float>] = (0..<height).map { (y: Int) -> SIMD4<Float> in pixels[y * width + x] }
                let sorted: [SIMD4<Float>] = Self.referenceLine(column, span: span, threshold: t)
                for y in 0..<height { out[y * width + x] = sorted[y] }
            }
        }
        return out
    }

    /// The whole frame through the effect as the compositor would draw it (the input itself when not run).
    public func reference(_ pixels: [SIMD4<Float>], width: Int, height: Int,
                          budget: Int = PixelSort.frameBudget) -> [SIMD4<Float>] {
        let p: Plan = plan(width: width, height: height, budget: budget)
        guard p.runs else { return pixels }
        return referenceAlways(pixels, width: width, height: height, span: p.effectiveSpan)
    }
}
