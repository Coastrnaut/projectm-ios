// ScenePaletteColorNames.swift — UIX-011-R9 (research UIX-011-D5, D6): words and contrast for palette swatches.
//
// * `PaletteColor.name`: a plain colour word for VoiceOver ("dark blue", "teal", "light grey") from HSL: low
//   saturation reads black, grey or white by lightness; otherwise the hue's sector, with "dark" or "light". The
//   hex is always read after it, so the description stays exact.
// * `PaletteColor.namedColors`: the editor's named-colour menu (16 entries).
// * Contrast on black: WCAG relative luminance (sRGB decoded), ratio (L + 0.05) / 0.05; under 3:1 (the ACC-003
//   threshold for a bar on the black background) is low contrast.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

extension PaletteColor {
    public static let minimumContrastOnBlack = 3.0

    /// Name and hex of each entry of the named-colour menu.
    private static let namedHexes: [[String]] = [
        ["Black", "#000000"], ["Dark grey", "#555555"], ["Grey", "#808080"], ["Light grey", "#C0C0C0"], ["White", "#FFFFFF"],
        ["Red", "#FF0000"], ["Orange", "#FF8000"], ["Yellow", "#FFE000"], ["Lime", "#80FF00"], ["Green", "#00C040"],
        ["Teal", "#008080"], ["Cyan", "#00FFFF"], ["Blue", "#0040FF"], ["Purple", "#8000FF"], ["Magenta", "#FF00FF"],
        ["Pink", "#FF80C0"],
    ]

    public static let namedColors: [(name: String, color: PaletteColor)] = namedHexes.compactMap {
        (pair: [String]) -> (name: String, color: PaletteColor)? in
        guard pair.count == 2, let color = PaletteColor(hex: pair[1]) else { return nil }
        return (pair[0], color)
    }

    /// Hue in degrees (0…360), saturation and lightness (0…1).
    public var hsl: (hue: Double, saturation: Double, lightness: Double) {
        let (r, g, b) = components
        let high: Double = max(r, g, b)
        let low: Double = min(r, g, b)
        let lightness: Double = (high + low) / 2
        let delta: Double = high - low
        guard delta > 0 else { return (0, 0, lightness) }
        let saturation: Double = delta / (1 - abs(2 * lightness - 1))
        var hue: Double
        if high == r {
            hue = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6)
        } else if high == g {
            hue = 60 * ((b - r) / delta + 2)
        } else {
            hue = 60 * ((r - g) / delta + 4)
        }
        if hue < 0 { hue += 360 }
        return (hue, saturation, lightness)
    }

    /// A plain colour word for VoiceOver (lowercase).
    public var name: String {
        if let named = Self.namedColors.first(where: { (entry: (name: String, color: PaletteColor)) -> Bool in entry.color == self }) {
            return named.name.lowercased()
        }
        let (h, s, l) = hsl
        if s < 0.15 || l < 0.06 || l > 0.96 {
            if l < 0.12 { return "black" }
            if l < 0.4 { return "dark grey" }
            if l < 0.7 { return "grey" }
            if l < 0.92 { return "light grey" }
            return "white"
        }
        let base: String = Self.hueName(h)
        if base == "cyan" && l < 0.4 { return "teal" }
        if (base == "magenta" || base == "red") && l > 0.7 { return "pink" }
        if l < 0.3 { return "dark " + base }
        if l > 0.75 { return "light " + base }
        return base
    }

    static func hueName(_ hue: Double) -> String {
        switch hue {
        case ..<15: "red"
        case ..<45: "orange"
        case ..<70: "yellow"
        case ..<160: "green"
        case ..<195: "cyan"
        case ..<255: "blue"
        case ..<290: "purple"
        case ..<335: "magenta"
        default: "red"
        }
    }

    /// WCAG relative luminance.
    public var relativeLuminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let (r, g, b) = components
        let lr: Double = linear(r)
        let lg: Double = linear(g)
        let lb: Double = linear(b)
        return 0.2126 * lr + 0.7152 * lg + 0.0722 * lb
    }

    /// Contrast ratio against black (1…21).
    public var contrastOnBlack: Double { (relativeLuminance + 0.05) / 0.05 }

    public var hasLowContrastOnBlack: Bool { contrastOnBlack < Self.minimumContrastOnBlack }

    /// VoiceOver description of swatch `index` (0-based) of `count`: "Colour 2 of 4, teal, #008080".
    public func spokenDescription(index: Int, count: Int) -> String {
        "Colour \(index + 1) of \(count), \(name), \(hex)"
    }
}
