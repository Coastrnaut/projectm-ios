// ImageDiff.swift — QA-003 visual diff tolerances (specs/133-qa-003-visual-diff, contract I1-I2;
// research D2-D6). A reusable comparator for 8-bit RGBA images with configurable colour and geometry
// thresholds. Plain Swift (no Foundation needed): builds and tests on Linux.
//
// Rules, all on pixels whose largest channel difference (alpha included) exceeds `channelThreshold`:
// * neighbourhood forgiveness (radius r > 0): an exceeding pixel is forgiven when, within Chebyshev
//   distance r, the expected pixel has a matching actual pixel AND the actual pixel has a matching
//   expected pixel (a one-pixel rasterization shift); "matching" uses the same colour threshold;
// * count: the remaining (unmatched) pixels must not exceed the allowed count;
// * cluster: the largest 8-connected cluster of unmatched pixels must not exceed `maxClusterPixels`
//   (scattered noise forms clusters of 1-2 pixels; a moved, scaled or missing shape one large blob);
// * SSIM (opt-in): mean luma SSIM must not drop below `minimumSSIM`.

/// Thresholds for one comparison (QA-003 data-model "ImageDiffTolerance"). QA-002's name for it is
/// `GoldenTolerance`.
public struct ImageDiffTolerance: Sendable, Equatable {
    /// A pixel exceeds when its largest channel difference (alpha included) is above this (0-255).
    public let channelThreshold: Int
    /// Allowed unmatched pixels as a fraction of all pixels, rounded down.
    public let allowedFraction: Double
    /// When set, the allowed count is the smaller of this and the fraction's count.
    public let maxExceedingPixels: Int?
    /// Chebyshev radius of the neighbourhood forgiveness (0-8); 0 disables it.
    public let neighborhoodRadius: Int
    /// When set, the largest 8-connected cluster of unmatched pixels must not exceed it.
    public let maxClusterPixels: Int?
    /// When set (and SSIM is computable), a mean luma SSIM below it fails.
    public let minimumSSIM: Double?

    public init(channelThreshold: Int, allowedFraction: Double, maxExceedingPixels: Int? = nil, neighborhoodRadius: Int = 0,
                maxClusterPixels: Int? = nil, minimumSSIM: Double? = nil) {
        self.channelThreshold = min(255, max(0, channelThreshold))
        self.allowedFraction = allowedFraction.isFinite ? max(0, allowedFraction) : 0
        self.maxExceedingPixels = maxExceedingPixels.map { (n: Int) -> Int in max(0, n) }
        self.neighborhoodRadius = min(8, max(0, neighborhoodRadius))
        self.maxClusterPixels = maxClusterPixels.map { (n: Int) -> Int in max(0, n) }
        self.minimumSSIM = minimumSSIM
    }

    /// No difference at all.
    public static let exact = ImageDiffTolerance(channelThreshold: 0, allowedFraction: 0, maxExceedingPixels: 0)

    /// QA-002's rule: ≤ 2/255 per channel, and at most 0.1 % of the pixels above that.
    public static let qa002 = ImageDiffTolerance(channelThreshold: 2, allowedFraction: 0.001)

    /// QA-003 default for GPU goldens: QA-002's colour rule, one-pixel shifts forgiven, and no
    /// unmatched cluster larger than 8 pixels.
    public static let golden = ImageDiffTolerance(channelThreshold: 2, allowedFraction: 0.001, neighborhoodRadius: 1,
                                                  maxClusterPixels: 8)

    /// ⌊fraction × total⌋, capped by `maxExceedingPixels` (12 of 12,288 at 128 × 96 for `qa002`).
    public func allowedPixels(total: Int) -> Int {
        let product: Double = allowedFraction * Double(total)
        let byFraction = Int(product.rounded(.down))
        guard let cap = maxExceedingPixels else { return byFraction }
        return min(cap, byFraction)
    }
}

/// Inclusive pixel rectangle of the differences.
public struct ImageDiffBoundingBox: Sendable, Equatable, CustomStringConvertible {
    public let minX: Int
    public let minY: Int
    public let maxX: Int
    public let maxY: Int

    public init(minX: Int, minY: Int, maxX: Int, maxY: Int) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    public var width: Int { maxX - minX + 1 }
    public var height: Int { maxY - minY + 1 }
    public var description: String { "x \(minX)-\(maxX), y \(minY)-\(maxY)" }
}

/// A rule a comparison can fail.
public enum ImageDiffRule: String, Sendable, Equatable, CaseIterable {
    case size
    case count
    case cluster
    case ssim
}

/// Everything a reviewer needs about one comparison (QA-003-R7).
public struct ImageDiffReport: Sendable, Equatable {
    public let expectedWidth: Int
    public let expectedHeight: Int
    public let actualWidth: Int
    public let actualHeight: Int
    public let tolerance: ImageDiffTolerance
    public let totalPixels: Int
    public let changedPixels: Int
    public let exceedingPixels: Int
    public let forgivenPixels: Int
    public let allowedPixels: Int
    public let maxChannelDifference: Int
    public let largestCluster: Int
    public let boundingBox: ImageDiffBoundingBox?
    public let ssim: Double?
    public let failures: [ImageDiffRule]

    public var unmatchedPixels: Int { exceedingPixels - forgivenPixels }
    public var passed: Bool { failures.isEmpty }
    public var identical: Bool { failures.isEmpty && changedPixels == 0 }
    public var sizeMismatch: Bool { failures.contains(.size) }

    /// One line (contract I2).
    public var summary: String {
        if sizeMismatch {
            return "FAIL [size]: expected \(expectedWidth)x\(expectedHeight), actual \(actualWidth)x\(actualHeight)"
        }
        let verdict: String = passed ? "PASS" : "FAIL [" + failures.map(\.rawValue).joined(separator: ", ") + "]"
        var parts: [String] = []
        parts.append("\(changedPixels) of \(totalPixels) pixels changed")
        parts.append("\(exceedingPixels) above the threshold \(tolerance.channelThreshold)/255 (\(forgivenPixels) forgiven as shifts, "
            + "\(unmatchedPixels) unmatched, allowed \(allowedPixels))")
        parts.append("largest channel difference \(maxChannelDifference)/255")
        var cluster = "largest cluster \(largestCluster)"
        if let limit = tolerance.maxClusterPixels { cluster += " (limit \(limit))" }
        parts.append(cluster)
        parts.append("box " + (boundingBox.map { (b: ImageDiffBoundingBox) -> String in b.description } ?? "none"))
        var structural = "SSIM " + (ssim.map { (s: Double) -> String in ImageDiff.format(s) } ?? "n/a")
        if let minimum = tolerance.minimumSSIM { structural += " (minimum \(ImageDiff.format(minimum)))" }
        parts.append(structural)
        return verdict + ": " + parts.joined(separator: ", ")
    }
}

public enum ImageDiff {
    /// Per-pixel class used by the diff image.
    public enum PixelClass: UInt8, Sendable {
        case unchanged = 0
        case withinTolerance = 1
        case forgiven = 2
        case unmatched = 3
    }

    /// Compares `actual` with `expected` under `tolerance` (contract I1).
    public static func compare(expected: GoldenImage, actual: GoldenImage, tolerance: ImageDiffTolerance = .golden) -> ImageDiffReport {
        analyze(expected: expected, actual: actual, tolerance: tolerance).report
    }

    /// The report plus each pixel's class (empty on a size mismatch), row-major.
    public static func analyze(expected: GoldenImage, actual: GoldenImage,
                               tolerance: ImageDiffTolerance) -> (report: ImageDiffReport, classes: [PixelClass]) {
        guard expected.width == actual.width, expected.height == actual.height else {
            let total = max(expected.pixelCount, actual.pixelCount)
            let report = ImageDiffReport(expectedWidth: expected.width, expectedHeight: expected.height, actualWidth: actual.width,
                                         actualHeight: actual.height, tolerance: tolerance, totalPixels: total, changedPixels: 0,
                                         exceedingPixels: 0, forgivenPixels: 0, allowedPixels: 0, maxChannelDifference: 255,
                                         largestCluster: 0, boundingBox: nil, ssim: nil, failures: [.size])
            return (report, [])
        }
        let width = expected.width, height = expected.height, total = expected.pixelCount
        let threshold = tolerance.channelThreshold
        let radius = tolerance.neighborhoodRadius
        var classes = [PixelClass](repeating: .unchanged, count: total)
        var changed = 0, exceeding = 0, forgiven = 0, maxDiff = 0
        expected.rgba.withUnsafeBufferPointer { (e: UnsafeBufferPointer<UInt8>) in
            actual.rgba.withUnsafeBufferPointer { (a: UnsafeBufferPointer<UInt8>) in
                for p in 0..<total {
                    let d = difference(e, p * 4, a, p * 4)
                    if d > maxDiff { maxDiff = d }
                    guard d > 0 else { continue }
                    changed += 1
                    guard d > threshold else {
                        classes[p] = .withinTolerance
                        continue
                    }
                    exceeding += 1
                    let x = p % width, y = p / width
                    if radius > 0,
                       hasMatch(of: e, at: p, in: a, x: x, y: y, width: width, height: height, radius: radius, threshold: threshold),
                       hasMatch(of: a, at: p, in: e, x: x, y: y, width: width, height: height, radius: radius, threshold: threshold) {
                        classes[p] = .forgiven
                        forgiven += 1
                    } else {
                        classes[p] = .unmatched
                    }
                }
            }
        }
        let largest = largestCluster(classes, width: width, height: height)
        let box = boundingBox(classes, width: width, preferring: .unmatched)
            ?? boundingBox(classes, width: width, preferring: .forgiven)
        let ssim = ImageDiffSSIM.mean(expected, actual)
        let allowed = tolerance.allowedPixels(total: total)
        var failures: [ImageDiffRule] = []
        if exceeding - forgiven > allowed { failures.append(.count) }
        if let limit = tolerance.maxClusterPixels, largest > limit { failures.append(.cluster) }
        if let minimum = tolerance.minimumSSIM, let ssim, ssim < minimum { failures.append(.ssim) }
        let report = ImageDiffReport(expectedWidth: width, expectedHeight: height, actualWidth: width, actualHeight: height,
                                     tolerance: tolerance, totalPixels: total, changedPixels: changed, exceedingPixels: exceeding,
                                     forgivenPixels: forgiven, allowedPixels: allowed, maxChannelDifference: maxDiff,
                                     largestCluster: largest, boundingBox: box, ssim: ssim, failures: failures)
        return (report, classes)
    }

    /// Largest absolute channel difference between the pixels at byte offsets `i` and `j`.
    @inline(__always)
    static func difference(_ x: UnsafeBufferPointer<UInt8>, _ i: Int, _ y: UnsafeBufferPointer<UInt8>, _ j: Int) -> Int {
        var d = 0
        for c in 0..<4 {
            let v = abs(Int(x[i + c]) - Int(y[j + c]))
            if v > d { d = v }
        }
        return d
    }

    /// True when `source`'s pixel `p` matches some pixel of `other` within the radius.
    static func hasMatch(of source: UnsafeBufferPointer<UInt8>, at p: Int, in other: UnsafeBufferPointer<UInt8>, x: Int, y: Int,
                         width: Int, height: Int, radius: Int, threshold: Int) -> Bool {
        let y0 = max(0, y - radius), y1 = min(height - 1, y + radius)
        let x0 = max(0, x - radius), x1 = min(width - 1, x + radius)
        for ny in y0...y1 {
            for nx in x0...x1 where difference(source, p * 4, other, (ny * width + nx) * 4) <= threshold {
                return true
            }
        }
        return false
    }

    /// Pixels in the largest 8-connected cluster of unmatched pixels (iterative flood fill).
    static func largestCluster(_ classes: [PixelClass], width: Int, height: Int) -> Int {
        var visited = [Bool](repeating: false, count: classes.count)
        var stack: [Int] = []
        var largest = 0
        for start in 0..<classes.count where classes[start] == .unmatched && !visited[start] {
            visited[start] = true
            stack.append(start)
            var size = 0
            while let p = stack.popLast() {
                size += 1
                let x = p % width, y = p / width
                for dy in -1...1 {
                    let ny = y + dy
                    guard ny >= 0, ny < height else { continue }
                    for dx in -1...1 {
                        let nx = x + dx
                        guard nx >= 0, nx < width else { continue }
                        let q = ny * width + nx
                        if classes[q] == .unmatched, !visited[q] {
                            visited[q] = true
                            stack.append(q)
                        }
                    }
                }
            }
            if size > largest { largest = size }
        }
        return largest
    }

    /// The bounding box of pixels of class `kind` (and, for `.forgiven`, all exceeding pixels).
    static func boundingBox(_ classes: [PixelClass], width: Int, preferring kind: PixelClass) -> ImageDiffBoundingBox? {
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for (p, c) in classes.enumerated() {
            let counts: Bool = kind == .unmatched ? c == .unmatched : (c == .forgiven || c == .unmatched)
            guard counts else { continue }
            let x = p % width, y = p / width
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
        }
        guard maxX >= 0 else { return nil }
        return ImageDiffBoundingBox(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }

    /// Four decimals without Foundation.
    static func format(_ value: Double) -> String {
        guard value.isFinite else { return "\(value)" }
        let scaled = Int((value * 10_000).rounded())
        let sign: String = scaled < 0 ? "-" : ""
        let magnitude = abs(scaled)
        let fraction = String(magnitude % 10_000)
        let padded = String(repeating: "0", count: 4 - fraction.count) + fraction
        return sign + String(magnitude / 10_000) + "." + padded
    }
}
