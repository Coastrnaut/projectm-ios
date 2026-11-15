// SafeAreaGuides.swift — OUT-005: the geometry of the device-only safe-area guides (spec
// specs/258-out-005-safe-area-guides; research OUT-005-D1, D3; contracts/safe-area-guides.md C1).
//
// Units are the device view's points. The output frame is the whole view, or (an external display
// showing the visual) the largest rect of the display's physical shape fitted and centred in it. The
// action-safe ("stage-safe") and title-safe rects are that frame scaled about its centre by their
// percentages (SMPTE ST 2046-1 defaults: 93 % and 90 %); title-safe is never drawn outside
// action-safe. Pure Swift with no Foundation or UIKit (tested on the host and Linux).

/// The user's guide choice (OUT-005-R2, R3). Percentages are clamped into their bounds.
public struct SafeAreaGuideChoice: Sendable, Equatable {
    public static let defaultActionPercent: Int = 93
    public static let defaultTitlePercent: Int = 90
    public static let actionRange: ClosedRange<Int> = 80...100
    public static let titleRange: ClosedRange<Int> = 70...100

    public var actionPercent: Int
    public var titlePercent: Int
    public var showsCentreCross: Bool

    public init(actionPercent: Int = SafeAreaGuideChoice.defaultActionPercent,
                titlePercent: Int = SafeAreaGuideChoice.defaultTitlePercent, showsCentreCross: Bool = false) {
        self.actionPercent = Self.clampAction(actionPercent)
        self.titlePercent = Self.clampTitle(titlePercent)
        self.showsCentreCross = showsCentreCross
    }

    public static func clampAction(_ value: Int) -> Int { min(max(value, actionRange.lowerBound), actionRange.upperBound) }
    public static func clampTitle(_ value: Int) -> Int { min(max(value, titleRange.lowerBound), titleRange.upperBound) }

    /// The title-safe percentage as drawn: never outside action-safe.
    public var drawnTitlePercent: Int { min(titlePercent, actionPercent) }

    public static let `default` = SafeAreaGuideChoice()
}

/// A rectangle in the device view's points (top-left origin).
public struct SafeAreaGuideRect: Sendable, Equatable {
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

    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }

    /// This rect scaled by `fraction` about its centre.
    public func scaled(_ fraction: Double) -> SafeAreaGuideRect {
        let w: Double = width * fraction
        let h: Double = height * fraction
        return SafeAreaGuideRect(x: midX - w / 2, y: midY - h / 2, width: w, height: h)
    }
}

/// Where the guides are drawn (contract C1).
public struct SafeAreaGuideGeometry: Sendable, Equatable {
    /// The output frame: the whole view, or the external display's shape fitted and centred.
    public let output: SafeAreaGuideRect
    public let actionSafe: SafeAreaGuideRect
    public let titleSafe: SafeAreaGuideRect
    /// Half-length of each centre-cross stroke (4 % of the output's shorter side); nil when off.
    public let crossArm: Double?

    /// The cross arm as a fraction of the output frame's shorter side.
    public static let crossArmFraction: Double = 0.04

    /// nil for an unusable view size. `outputAspect` nil (or not finite and positive) is the whole view.
    public static func make(viewWidth: Double, viewHeight: Double, outputAspect: Double?,
                            choice: SafeAreaGuideChoice) -> SafeAreaGuideGeometry? {
        guard viewWidth.isFinite, viewHeight.isFinite, viewWidth > 0, viewHeight > 0 else { return nil }
        var output = SafeAreaGuideRect(x: 0, y: 0, width: viewWidth, height: viewHeight)
        if let aspect = outputAspect, aspect.isFinite, aspect > 0 {
            let viewAspect: Double = viewWidth / viewHeight
            let width: Double = aspect >= viewAspect ? viewWidth : viewHeight * aspect
            let height: Double = aspect >= viewAspect ? viewWidth / aspect : viewHeight
            output = SafeAreaGuideRect(x: (viewWidth - width) / 2, y: (viewHeight - height) / 2, width: width, height: height)
        }
        let action: SafeAreaGuideRect = output.scaled(Double(choice.actionPercent) / 100)
        let title: SafeAreaGuideRect = output.scaled(Double(choice.drawnTitlePercent) / 100)
        let arm: Double? = choice.showsCentreCross ? min(output.width, output.height) * crossArmFraction : nil
        return SafeAreaGuideGeometry(output: output, actionSafe: action, titleSafe: title, crossArm: arm)
    }

    /// An external display's physical shape: points width × pixel aspect ÷ height; nil when unusable.
    public static func externalAspect(width: Double, height: Double, pixelAspect: Double) -> Double? {
        guard width.isFinite, height.isFinite, pixelAspect.isFinite, width > 0, height > 0, pixelAspect > 0 else { return nil }
        return width * pixelAspect / height
    }
}
