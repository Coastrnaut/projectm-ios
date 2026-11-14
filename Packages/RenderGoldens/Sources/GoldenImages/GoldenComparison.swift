// GoldenComparison.swift — the golden suite's comparison (QA-002-R7; research D7; contract G3), backed
// by QA-003's `ImageDiff` since 2026-11-14 (specs/133-qa-003-visual-diff, contract I3). The tolerance
// is a value: `.qa002` keeps QA-002's colour-only rule, `.golden` (the default) adds one-pixel shift
// forgiveness and the unmatched-cluster limit.

/// QA-002's name for the comparison thresholds.
public typealias GoldenTolerance = ImageDiffTolerance

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
    /// Pixels that count against the allowance: above the threshold and not forgiven as a shift
    /// (QA-002's "above the threshold" figure when the radius is 0).
    public let exceedingPixels: Int
    public let maxChannelDifference: Int
    public let allowedPixels: Int
    public let totalPixels: Int
    /// The full QA-003 report (nil only for results built by hand).
    public let report: ImageDiffReport?

    public init(outcome: Outcome, changedPixels: Int, exceedingPixels: Int, maxChannelDifference: Int, allowedPixels: Int,
                totalPixels: Int, report: ImageDiffReport? = nil) {
        self.outcome = outcome
        self.changedPixels = changedPixels
        self.exceedingPixels = exceedingPixels
        self.maxChannelDifference = maxChannelDifference
        self.allowedPixels = allowedPixels
        self.totalPixels = totalPixels
        self.report = report
    }

    public init(report: ImageDiffReport) {
        let outcome: Outcome
        if report.sizeMismatch {
            outcome = .sizeMismatch
        } else if report.identical {
            outcome = .identical
        } else if report.passed {
            outcome = .withinTolerance
        } else {
            outcome = .exceedsTolerance
        }
        self.init(outcome: outcome, changedPixels: report.changedPixels, exceedingPixels: report.unmatchedPixels,
                  maxChannelDifference: report.maxChannelDifference, allowedPixels: report.allowedPixels,
                  totalPixels: report.totalPixels, report: report)
    }

    public var passed: Bool { outcome == .identical || outcome == .withinTolerance }

    /// One line for logs and the diff summary.
    public var summary: String {
        if let report {
            return "\(outcome.rawValue): " + report.summary
        }
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
                               tolerance: GoldenTolerance = .golden) -> GoldenComparisonResult {
        GoldenComparisonResult(report: ImageDiff.compare(expected: expected, actual: actual, tolerance: tolerance))
    }
}
