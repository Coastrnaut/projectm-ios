// LogoPlacement.swift — where the MED-010 logo sits on the output, and the logo's import limits
// (MED-010-R3, R6, R7; research MED-010-D5; specs/131-med-010-logo-overlay/contracts/logo-overlay.md C1, C4).
//
// Plain Swift (builds on Linux). With output W × H, s = min(W, H) and a logo of w × h pixels:
//
//     longer side L = size · s            drawn = (L·w/max(w,h), L·h/max(w,h))
//     margin p = margin · s
//     x = p + anchorX · (W − 2p − drawnW)  y = p + anchorY · (H − 2p − drawnH)   (top-left origin)
//
// That is CMP-006's `offset = anchor · (1 − visible)` rule inside the margins: the anchor's point of
// the logo lands on the same fraction of the area inside the margins at every output size. Corners
// are fixed anchors; `custom` uses the stored one. Every intermediate is a named, typed value
// (CMP-006-D4: long mixed expressions time out the type checker).
import Compositor
import Foundation

/// The placement presets. Raw values are the saved names.
public enum LogoCorner: String, Sendable, Equatable, CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight, center, custom

    /// Display name for Settings.
    public var title: String {
        switch self {
        case .topLeft: "Top left"
        case .topRight: "Top right"
        case .bottomLeft: "Bottom left"
        case .bottomRight: "Bottom right"
        case .center: "Centre"
        case .custom: "Custom"
        }
    }

    /// The preset's anchor (nil for `custom`).
    public var presetAnchor: LayerPoint? {
        switch self {
        case .topLeft: LayerPoint(x: 0, y: 0)
        case .topRight: LayerPoint(x: 1, y: 0)
        case .bottomLeft: LayerPoint(x: 0, y: 1)
        case .bottomRight: LayerPoint(x: 1, y: 1)
        case .center: LayerPoint(x: 0.5, y: 0.5)
        case .custom: nil
        }
    }
}

/// A logo's rectangle in output pixels (top-left origin).
public struct LogoRect: Sendable, Equatable {
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

    public static let empty = LogoRect(x: 0, y: 0, width: 0, height: 0)
    public var isEmpty: Bool { width <= 0 || height <= 0 }
}

public struct LogoPlacement: Sendable, Equatable {
    public static let sizeRange: ClosedRange<Double> = 0.05...0.5
    public static let marginRange: ClosedRange<Double> = 0...0.2
    public static let opacityRange: ClosedRange<Double> = 0...1
    public static let defaultSize = 0.15
    public static let defaultMargin = 0.04

    public let corner: LogoCorner
    /// The custom anchor (kept while a preset is chosen, so switching back restores it).
    public let customAnchor: LayerPoint
    public let size: Double
    public let margin: Double
    public let opacity: Double

    public init(corner: LogoCorner = .bottomRight, anchorX: Double = 1, anchorY: Double = 1,
                size: Double = LogoPlacement.defaultSize, margin: Double = LogoPlacement.defaultMargin, opacity: Double = 1) {
        self.corner = corner
        customAnchor = LayerPoint(x: Self.unit(anchorX, fallback: 0.5), y: Self.unit(anchorY, fallback: 0.5))
        self.size = Self.clamp(size, Self.sizeRange, fallback: Self.defaultSize)
        self.margin = Self.clamp(margin, Self.marginRange, fallback: Self.defaultMargin)
        self.opacity = Self.clamp(opacity, Self.opacityRange, fallback: 1)
    }

    public static let `default` = LogoPlacement()

    /// The anchor in use: the corner's, or the custom one.
    public var anchor: LayerPoint { corner.presetAnchor ?? customAnchor }

    public func with(corner: LogoCorner? = nil, anchorX: Double? = nil, anchorY: Double? = nil, size: Double? = nil,
                     margin: Double? = nil, opacity: Double? = nil) -> LogoPlacement {
        LogoPlacement(corner: corner ?? self.corner, anchorX: anchorX ?? customAnchor.x, anchorY: anchorY ?? customAnchor.y,
                      size: size ?? self.size, margin: margin ?? self.margin, opacity: opacity ?? self.opacity)
    }

    /// The logo's rectangle for one logo size and output size (research MED-010-D5). Any size ≤ 0
    /// gives `.empty`.
    public func rect(logoWidth: Int, logoHeight: Int, outputWidth: Int, outputHeight: Int) -> LogoRect {
        guard logoWidth > 0, logoHeight > 0, outputWidth > 0, outputHeight > 0 else { return .empty }
        let wo: Double = Double(outputWidth)
        let ho: Double = Double(outputHeight)
        let shorter: Double = min(wo, ho)
        let wl: Double = Double(logoWidth)
        let hl: Double = Double(logoHeight)
        let longest: Double = max(wl, hl)
        let side: Double = size * shorter
        let drawnW: Double = side * wl / longest
        let drawnH: Double = side * hl / longest
        let pad: Double = margin * shorter
        let spareW: Double = wo - 2 * pad - drawnW
        let spareH: Double = ho - 2 * pad - drawnH
        let a: LayerPoint = anchor
        let x: Double = pad + a.x * spareW
        let y: Double = pad + a.y * spareH
        return LogoRect(x: x, y: y, width: drawnW, height: drawnH)
    }

    // MARK: JSON (UserDefaults and scene assets)

    /// The placement as plain JSON values (keys: corner, anchorX, anchorY, size, margin, opacity).
    public var dictionary: [String: Any] {
        ["corner": corner.rawValue, "anchorX": customAnchor.x, "anchorY": customAnchor.y,
         "size": size, "margin": margin, "opacity": opacity]
    }

    /// Lenient: missing or malformed fields read as their defaults; numbers are clamped.
    public init(dictionary: [String: Any]) {
        func number(_ key: String, _ fallback: Double) -> Double {
            let value: Any? = dictionary[key]
            if let d = value as? Double { return d }
            if let i = value as? Int { return Double(i) }
            return (value as? NSNumber)?.doubleValue ?? fallback
        }
        let corner: LogoCorner = (dictionary["corner"] as? String).flatMap { (raw: String) -> LogoCorner? in LogoCorner(rawValue: raw) } ?? .bottomRight
        self.init(corner: corner, anchorX: number("anchorX", 1), anchorY: number("anchorY", 1),
                  size: number("size", Self.defaultSize), margin: number("margin", Self.defaultMargin), opacity: number("opacity", 1))
    }

    /// UTF-8 JSON with sorted keys.
    public var jsonData: Data {
        (try? JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys])) ?? Data()
    }

    /// nil or unreadable data reads as the default placement.
    public init(jsonData: Data?) {
        guard let jsonData, let object = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            self = .default
            return
        }
        self.init(dictionary: object)
    }

    private static func unit(_ v: Double, fallback: Double) -> Double {
        guard v.isFinite else { return fallback }
        let c: Double = min(max(v, 0), 1)
        return c == 0 ? 0 : c   // −0 is stored as 0
    }

    private static func clamp(_ v: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
        guard v.isFinite else { return fallback }
        let c: Double = min(max(v, range.lowerBound), range.upperBound)
        return c == 0 ? 0 : c
    }
}

/// MED-010-R3: the logo's import limits and notices (spec Clarifications).
public enum LogoImport {
    /// 10 MB picked file, 16,777,216 pixels (4096 × 4096), stored at most 1024 px on its longer side.
    public static let limits = ImageImportLimits(maxFileBytes: 10 * 1024 * 1024, maxPixelCount: 16_777_216,
                                                 maxStoredLongestSide: 1024)

    /// The notice for a refused or failed logo import.
    public static func message(for error: ImageImportError) -> String {
        switch error {
        case .notAnImage: "That file isn't an image the app can use as a logo."
        case .tooLarge: "That image is larger than 10 MB, so it wasn't used as a logo."
        case .tooManyPixels: "That image is larger than 4096 × 4096 pixels, so it wasn't used as a logo."
        case .damaged: "That image couldn't be read. It may be damaged."
        case .unreadable: "The image couldn't be opened."
        case .saveFailed: "The logo couldn't be saved on this device."
        }
    }
}
