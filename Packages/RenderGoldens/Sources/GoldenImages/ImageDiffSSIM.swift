// ImageDiffSSIM.swift — QA-003 structural measure (research D4): mean SSIM of luma over 8 × 8
// windows at stride 4. Reported for every comparison; a gate only when the tolerance sets a minimum.
// Plain Swift.

public enum ImageDiffSSIM {
    public static let window = 8
    public static let stride = 4
    static let c1: Double = (0.01 * 255) * (0.01 * 255)
    static let c2: Double = (0.03 * 255) * (0.03 * 255)

    /// nil unless both images have the same size of at least 8 × 8.
    public static func mean(_ expected: GoldenImage, _ actual: GoldenImage) -> Double? {
        guard expected.width == actual.width, expected.height == actual.height,
              expected.width >= window, expected.height >= window else { return nil }
        let x = luma(expected), y = luma(actual)
        let width = expected.width, height = expected.height
        let n = Double(window * window)
        var sum = 0.0
        var count = 0
        var top = 0
        while top + window <= height {
            var left = 0
            while left + window <= width {
                var sx = 0.0, sy = 0.0, sxx = 0.0, syy = 0.0, sxy = 0.0
                for row in top..<(top + window) {
                    let base = row * width
                    for col in left..<(left + window) {
                        let a = x[base + col], b = y[base + col]
                        sx += a
                        sy += b
                        sxx += a * a
                        syy += b * b
                        sxy += a * b
                    }
                }
                let mx: Double = sx / n
                let my: Double = sy / n
                let vx: Double = sxx / n - mx * mx
                let vy: Double = syy / n - my * my
                let cov: Double = sxy / n - mx * my
                let numerator: Double = (2 * mx * my + c1) * (2 * cov + c2)
                let denominator: Double = (mx * mx + my * my + c1) * (vx + vy + c2)
                sum += numerator / denominator
                count += 1
                left += stride
            }
            top += stride
        }
        return sum / Double(count)
    }

    /// Rec. 709 luma of straight RGB (alpha ignored), 0-255.
    static func luma(_ image: GoldenImage) -> [Double] {
        var out = [Double](repeating: 0, count: image.pixelCount)
        for p in 0..<image.pixelCount {
            let i = p * 4
            let r: Double = 0.2126 * Double(image.rgba[i])
            let g: Double = 0.7152 * Double(image.rgba[i + 1])
            let b: Double = 0.0722 * Double(image.rgba[i + 2])
            out[p] = r + g + b
        }
        return out
    }
}
