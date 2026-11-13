// GoldenComparison.swift — the fixed QA-002 comparison rule (QA-002-R7; research D7; contract G3).
// QA-003 (visual diff tolerances) replaces `GoldenTolerance.qa002` with configurable color and
// geometry thresholds; everything here takes the tolerance as a value so that swap is local.

public struct GoldenTolerance: Sendable, Equatable {
    /// A pixel "exceeds" when its largest channel difference (alpha included) is above this (of 255).
    public let channelThreshold: Int
    /// The fraction of pixels allowed to exceed, rounded down.
    public let allowedFraction: Double

    public init(channelThreshold: Int, allowedFraction: Double) {
        self.channelThreshold = channelThreshold
        self.allowedFraction = allowedFraction
    }

    /// QA-002: ≤ 2/255 per channel, and at most 0.1 % of the pixels above that.
    public static let qa002 = GoldenTolerance(channelThreshold: 2, allowedFraction: 0.001)

    /// ⌊fraction × total⌋ (12 of 12,288 at 128 × 96; 49 of 49,152 at 256 × 192).
    public func allowedPixels(total: Int) -> Int {
        let product: Double = allowedFraction * Double(total)
        return Int(product.rounded(.down))
    }
}

public struct GoldenComparisonResult: Sendable, Equatable {
    public enum Outcome: String, Sendable, Equatable {
        case identical
        case withinTolerance
        case sizeMismatch
        case exceedsTolerance
    }

    public let outcome: Outcome
    /// Pixels with any difference.
    public let changedPixels: Int
    /// Pixels whose largest channel difference is above the threshold.
    public let exceedingPixels: Int
    public let maxChannelDifference: Int
    public let allowedPixels: Int
    public let totalPixels: Int

    public init(outcome: Outcome, changedPixels: Int, exceedingPixels: Int, maxChannelDifference: Int, allowedPixels: Int,
                totalPixels: Int) {
        self.outcome = outcome
        self.changedPixels = changedPixels
        self.exceedingPixels = exceedingPixels
        self.maxChannelDifference = maxChannelDifference
        self.allowedPixels = allowedPixels
        self.totalPixels = totalPixels
    }

    public var passed: Bool { outcome == .identical || outcome == .withinTolerance }

    /// One line for logs and the diff summary.
    public var summary: String {
        switch outcome {
        case .sizeMismatch:
            return "size mismatch"
        default:
            return "\(outcome.rawValue): \(changedPixels) of \(totalPixels) pixels changed, \(exceedingPixels) above the threshold "
                + "(allowed \(allowedPixels)), largest channel difference \(maxChannelDifference)/255"
        }
    }
}

public enum GoldenComparison {
    public static func compare(expected: GoldenImage, actual: GoldenImage,
                               tolerance: GoldenTolerance = .qa002) -> GoldenComparisonResult {
        guard expected.width == actual.width, expected.height == actual.height else {
            return GoldenComparisonResult(outcome: .sizeMismatch, changedPixels: 0, exceedingPixels: 0, maxChannelDifference: 255,
                                          allowedPixels: 0, totalPixels: max(expected.pixelCount, actual.pixelCount))
        }
        let total = expected.pixelCount
        let allowed = tolerance.allowedPixels(total: total)
        var changed = 0, exceeding = 0, maxDiff = 0
        expected.rgba.withUnsafeBufferPointer { (e: UnsafeBufferPointer<UInt8>) in
            actual.rgba.withUnsafeBufferPointer { (a: UnsafeBufferPointer<UInt8>) in
                for p in 0..<total {
                    let i = p * 4
                    let d = pixelDifference(e, a, at: i)
                    if d > 0 { changed += 1 }
                    if d > tolerance.channelThreshold { exceeding += 1 }
                    if d > maxDiff { maxDiff = d }
                }
            }
        }
        let outcome: GoldenComparisonResult.Outcome
        if changed == 0 {
            outcome = .identical
        } else if exceeding <= allowed {
            outcome = .withinTolerance
        } else {
            outcome = .exceedsTolerance
        }
        return GoldenComparisonResult(outcome: outcome, changedPixels: changed, exceedingPixels: exceeding,
                                      maxChannelDifference: maxDiff, allowedPixels: allowed, totalPixels: total)
    }

    /// The largest absolute channel difference of the pixel starting at byte `i`.
    @inline(__always)
    static func pixelDifference(_ e: UnsafeBufferPointer<UInt8>, _ a: UnsafeBufferPointer<UInt8>, at i: Int) -> Int {
        var d = 0
        for c in 0..<4 {
            let v = abs(Int(e[i + c]) - Int(a[i + c]))
            if v > d { d = v }
        }
        return d
    }
}
