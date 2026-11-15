// ExternalOutputResolution.swift — OUT-003: the external display's output resolution, independent of
// the device screen (spec specs/255-out-003-output-resolution; research OUT-003-D3, D4; contract
// contracts/output-resolution.md C1).
//
// The visual's view keeps its size in points (the scene's coordinate space); only the display scale
// it reads changes, so its drawable has fewer (never more) pixels than the screen. For a slot of
// W × H points on a screen of native scale s (native pixels W·s × H·s, long side L, short side S):
//
//     factor = min(1, choice, budget)
//       choice  native 1 · 1080p min(1920/L, 1080/S) · 720p min(1280/L, 720/S) · custom p/100
//       budget  min(maxSide/L, sqrt(maxPixels/(L·S)))           (REC-014's cap per device class)
//     scale   = s · factor,   pixels = round(W·s·factor) × round(H·s·factor)
//
// One uniform factor keeps the screen's shape. Pure Swift with no UIKit (tested on the host and Linux).

/// The user's choice (OUT-003-R1). Raw values are the stored names.
public enum ExternalResolutionMode: String, Sendable, Equatable, CaseIterable {
    case native
    case hd1080 = "1080p"
    case hd720 = "720p"
    case custom

    /// The box (long side, short side) a fixed mode fits in; nil for native and custom.
    public var box: (long: Double, short: Double)? {
        switch self {
        case .hd1080: (1920, 1080)
        case .hd720: (1280, 720)
        case .native, .custom: nil
        }
    }
}

/// The largest drawable this device class may render (OUT-003-R3; REC-014's `RecordingOutputCap`).
public struct ExternalPixelBudget: Sendable, Equatable {
    public let maxSide: Int
    public let maxPixels: Int

    public init(maxSide: Int, maxPixels: Int) {
        self.maxSide = Swift.max(maxSide, 2)
        self.maxPixels = Swift.max(maxPixels, 4)
    }

    /// No limit (tests that check only the choice).
    public static let unlimited = ExternalPixelBudget(maxSide: Int.max / 4, maxPixels: Int.max / 4)
}

/// The resolution the external visual renders at.
public struct ResolvedExternalOutput: Sendable, Equatable {
    /// The display scale the visual reads (native scale × factor).
    public let scale: Double
    /// The drawable's size before FR-049's render scale.
    public let pixelWidth: Int
    public let pixelHeight: Int
    /// The device's pixel budget was the limit (OUT-003-R3).
    public let clamped: Bool
    /// The factor is 1: the visual renders at the screen's native scale (no override).
    public let isNative: Bool

    public init(scale: Double, pixelWidth: Int, pixelHeight: Int, clamped: Bool, isNative: Bool) {
        self.scale = scale
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.clamped = clamped
        self.isNative = isNative
    }
}

/// The user's resolution choice (defaults: Native, 75 % for Custom).
public struct ExternalOutputResolution: Sendable, Equatable {
    public static let percentRange: ClosedRange<Int> = 50...100
    public static let percentStep = 5
    public static let defaultPercent = 75

    public var mode: ExternalResolutionMode
    /// Custom's percentage of native, clamped to 50…100.
    public var percent: Int {
        didSet { percent = Self.clampPercent(percent) }
    }

    public init(mode: ExternalResolutionMode = .native, percent: Int = ExternalOutputResolution.defaultPercent) {
        self.mode = mode
        self.percent = Self.clampPercent(percent)
    }

    public static let native = ExternalOutputResolution()

    public static func clampPercent(_ value: Int) -> Int {
        Swift.min(Swift.max(value, percentRange.lowerBound), percentRange.upperBound)
    }

    /// The output for a slot of `width` × `height` points on a screen of native `nativeScale`.
    /// Invalid input (zero, negative or non-finite) gives the native scale and no pixels.
    public func resolve(width: Double, height: Double, nativeScale: Double,
                        budget: ExternalPixelBudget) -> ResolvedExternalOutput {
        guard width.isFinite, height.isFinite, nativeScale.isFinite, width > 0, height > 0, nativeScale > 0 else {
            let scale: Double = nativeScale.isFinite && nativeScale > 0 ? nativeScale : 0
            return ResolvedExternalOutput(scale: scale, pixelWidth: 0, pixelHeight: 0, clamped: false, isNative: true)
        }
        let nativeWidth: Double = width * nativeScale
        let nativeHeight: Double = height * nativeScale
        let long: Double = Swift.max(nativeWidth, nativeHeight)
        let short: Double = Swift.min(nativeWidth, nativeHeight)
        let choice: Double = choiceFactor(long: long, short: short)
        let sideLimit: Double = Double(budget.maxSide) / long
        let pixelLimit: Double = (Double(budget.maxPixels) / (long * short)).squareRoot()
        let budgetFactor: Double = Swift.min(sideLimit, pixelLimit)
        let wanted: Double = Swift.min(1, choice)
        let clamped: Bool = budgetFactor < wanted
        var factor: Double = Swift.min(wanted, budgetFactor)
        var w: Int = Int((nativeWidth * factor).rounded())
        var h: Int = Int((nativeHeight * factor).rounded())
        // Rounding must never land above the budget or the choice's box.
        while (Swift.max(w, h) > budget.maxSide || w * h > budget.maxPixels || exceedsBox(w, h)) && w > 1 && h > 1 {
            factor *= 0.999
            w = Int((nativeWidth * factor).rounded())
            h = Int((nativeHeight * factor).rounded())
        }
        let isNative: Bool = factor >= 1
        return ResolvedExternalOutput(scale: nativeScale * factor, pixelWidth: w, pixelHeight: h,
                                      clamped: clamped, isNative: isNative)
    }

    private func choiceFactor(long: Double, short: Double) -> Double {
        switch mode {
        case .native: return 1
        case .custom: return Double(percent) / 100
        case .hd1080, .hd720:
            guard let box = mode.box else { return 1 }
            return Swift.min(box.long / long, box.short / short)
        }
    }

    private func exceedsBox(_ w: Int, _ h: Int) -> Bool {
        guard let box = mode.box else { return false }
        return Double(Swift.max(w, h)) > box.long || Double(Swift.min(w, h)) > box.short
    }
}
