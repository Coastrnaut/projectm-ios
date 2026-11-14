// ExternalOutputPlacement.swift — OUT-004: how the one visual is placed on an external display of a
// different shape or with non-square pixels (spec specs/172-out-004-aspect-correction; research
// OUT-004-D1, D2; contracts/output-correction.md C1).
//
// Units are the slot's points. The display's pixels have the pixel aspect ratio p (pixel width ÷
// pixel height, UIKit's `UIScreenMode.pixelAspectRatio`), so the display is physically W·p wide and
// H tall. The source picture has the physical aspect a (width ÷ height): the display's own shape
// (a = W·p/H) or the device visualizer's shape.
//
//     fit      a ≥ W·p/H → (Pw, Ph) = (W·p, W·p/a)   else (H·a, H)     whole picture, black bars
//     fill     a ≥ W·p/H → (Pw, Ph) = (H·a, H)       else (W·p, W·p/a) screen covered, cropped
//     stretch  bounds = slot, scaleX = 1                                no correction
//
// The visual's view gets bounds (Pw, Ph), a horizontal scale 1/p and the slot's centre, so it is
// Pw/p × Ph on screen and a circle of radius r in its bounds is r/p pixels wide and r tall: r × r on
// the glass. Pure Swift with no UIKit (tested on the host and Linux).

/// How the picture meets the external display's shape (OUT-004-R1). Raw values are the stored names.
public enum ExternalOutputFit: String, Sendable, Equatable, CaseIterable {
    /// The whole picture, keeping its shape; black bars (pillarbox or letterbox).
    case fit
    /// The screen covered, keeping the picture's shape; the overflow is cropped at the centre.
    case fill
    /// The screen's pixels covered exactly; no shape or pixel-aspect correction.
    case stretch
}

/// The picture's shape (OUT-004-R2). Raw values are the stored names.
public enum ExternalOutputShape: String, Sendable, Equatable, CaseIterable {
    /// The display's own physical shape: no bars, nothing cropped; only the pixel aspect is corrected.
    case display
    /// The device visualizer's current shape: the same composition as on the device.
    case device
}

/// Where the pixel aspect ratio comes from (OUT-004-R4). Raw values are the stored names.
public enum ExternalPixelAspect: String, Sendable, Equatable, CaseIterable {
    case automatic = "auto"
    case square = "1.0"
    case narrow = "0.9"
    case wide = "1.2"

    /// The override's value; nil for Automatic.
    public var override: Double? {
        switch self {
        case .automatic: nil
        case .square: 1.0
        case .narrow: 0.9
        case .wide: 1.2
        }
    }

    /// The ratio to use: the override, else the screen's value sanitised.
    public func resolved(screen: Double?) -> Double {
        if let override { return override }
        return Self.sanitized(screen)
    }

    /// Finite and within 0.5…2, else 1 (a bad adapter value never distorts the picture badly).
    public static func sanitized(_ value: Double?) -> Double {
        guard let value, value.isFinite, value >= 0.5, value <= 2 else { return 1 }
        return value
    }
}

/// The user's three choices (defaults: Fit, Display, Automatic).
public struct ExternalOutputCorrection: Sendable, Equatable {
    public var fit: ExternalOutputFit
    public var shape: ExternalOutputShape
    public var pixelAspect: ExternalPixelAspect

    public init(fit: ExternalOutputFit = .fit, shape: ExternalOutputShape = .display,
                pixelAspect: ExternalPixelAspect = .automatic) {
        self.fit = fit
        self.shape = shape
        self.pixelAspect = pixelAspect
    }

    public static let `default` = ExternalOutputCorrection()
}

/// Which bars a placement leaves visible.
public enum ExternalOutputBars: String, Sendable, Equatable {
    case none, pillarbox, letterbox
}

/// The visual view's layout in an external slot (contract C1).
public struct ExternalOutputPlacement: Sendable, Equatable {
    /// The view's bounds size (slot points, square-corrected units).
    public let boundsWidth: Double
    public let boundsHeight: Double
    /// The horizontal scale applied to the view (1/PAR; 1 for Stretch).
    public let scaleX: Double
    /// The view's centre in the slot.
    public let centerX: Double
    public let centerY: Double
    /// The slot it was computed for.
    public let slotWidth: Double
    public let slotHeight: Double

    /// The view's frame on screen (slot points).
    public var frameWidth: Double { boundsWidth * scaleX }
    public var frameHeight: Double { boundsHeight }

    /// The view exactly fills the slot with no transform (the device's placement).
    public var isIdentity: Bool {
        scaleX == 1 && boundsWidth == slotWidth && boundsHeight == slotHeight
    }

    /// Bars left visible by Fit (a frame narrower or shorter than the slot by more than half a point).
    public var bars: ExternalOutputBars {
        if frameWidth < slotWidth - 0.5 { return .pillarbox }
        if frameHeight < slotHeight - 0.5 { return .letterbox }
        return .none
    }

    /// The view fills the slot (the device, an unusable size, or an identity correction).
    public static func filling(width: Double, height: Double) -> ExternalOutputPlacement {
        ExternalOutputPlacement(boundsWidth: width, boundsHeight: height, scaleX: 1,
                                centerX: width / 2, centerY: height / 2, slotWidth: width, slotHeight: height)
    }

    init(boundsWidth: Double, boundsHeight: Double, scaleX: Double, centerX: Double, centerY: Double,
         slotWidth: Double, slotHeight: Double) {
        self.boundsWidth = boundsWidth
        self.boundsHeight = boundsHeight
        self.scaleX = scaleX
        self.centerX = centerX
        self.centerY = centerY
        self.slotWidth = slotWidth
        self.slotHeight = slotHeight
    }

    /// `pixelAspectRatio` is used as given (resolve and sanitise it first); `sourceAspect` nil (or
    /// not usable) means the display's own physical shape. Unusable slot sizes or ratios fill.
    public init(slotWidth: Double, slotHeight: Double, pixelAspectRatio: Double, sourceAspect: Double?,
                fit: ExternalOutputFit) {
        let usable: Bool = slotWidth.isFinite && slotHeight.isFinite && slotWidth > 0 && slotHeight > 0
            && pixelAspectRatio.isFinite && pixelAspectRatio > 0
        guard usable, fit != .stretch else {
            self = .filling(width: slotWidth, height: slotHeight)
            return
        }
        let physicalWidth: Double = slotWidth * pixelAspectRatio
        let displayAspect: Double = physicalWidth / slotHeight
        var aspect: Double = displayAspect
        if let sourceAspect, sourceAspect.isFinite, sourceAspect > 0 { aspect = sourceAspect }
        let widerThanDisplay: Bool = aspect >= displayAspect
        let widthLimited: Bool = fit == .fit ? widerThanDisplay : !widerThanDisplay
        let width: Double = widthLimited ? physicalWidth : slotHeight * aspect
        let height: Double = widthLimited ? physicalWidth / aspect : slotHeight
        self.init(boundsWidth: width, boundsHeight: height, scaleX: 1 / pixelAspectRatio,
                  centerX: slotWidth / 2, centerY: slotHeight / 2, slotWidth: slotWidth, slotHeight: slotHeight)
    }

    /// The placement for a correction: PAR resolved from `screenPixelAspect`, source shape from
    /// `deviceAspect` when the shape is Device (nil device aspect: the display's shape).
    public init(slotWidth: Double, slotHeight: Double, correction: ExternalOutputCorrection,
                screenPixelAspect: Double?, deviceAspect: Double?) {
        let ratio: Double = correction.pixelAspect.resolved(screen: screenPixelAspect)
        let source: Double? = correction.shape == .device ? deviceAspect : nil
        self.init(slotWidth: slotWidth, slotHeight: slotHeight, pixelAspectRatio: ratio, sourceAspect: source,
                  fit: correction.fit)
    }
}
