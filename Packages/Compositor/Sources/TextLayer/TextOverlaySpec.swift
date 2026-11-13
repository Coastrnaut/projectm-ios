// TextOverlaySpec.swift — what the text layer draws (MED-009-R2, R3, R5, R10; data-model
// "TextOverlaySpec"; research MED-009-D9). Plain Swift, every platform.
//
// Every value satisfies the data model: the initializer and the decoder clamp numbers (non-finite →
// the default), clean the message (TextSanitizer) and read unknown enum raw values as the default.
// Stored as JSON with `"version": 1` and sorted keys; `decodeStored` tells a newer version (left
// untouched by the app) from a damaged value (removed by the app).
import Foundation

public enum TextFontFamily: String, CaseIterable, Codable, Sendable {
    case system, avenirNext, georgia, menlo

    public var title: String {
        switch self {
        case .system: "System"
        case .avenirNext: "Avenir Next"
        case .georgia: "Georgia"
        case .menlo: "Menlo"
        }
    }
}

public enum TextFontWeight: String, CaseIterable, Codable, Sendable {
    case regular, medium, bold, heavy

    public var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// CoreText's weight trait (-1…1): the values of the system's regular, medium, bold and heavy.
    public var weightTrait: Double {
        switch self {
        case .regular: 0
        case .medium: 0.23
        case .bold: 0.4
        case .heavy: 0.56
        }
    }
}

public enum TextAlignmentChoice: String, CaseIterable, Codable, Sendable {
    case leading, center, trailing

    public var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

public enum TextVerticalPosition: String, CaseIterable, Codable, Sendable {
    case top, middle, bottom

    public var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// An sRGB color with straight alpha, each component 0…1.
public struct TextColor: Codable, Equatable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = Self.unit(red)
        self.green = Self.unit(green)
        self.blue = Self.unit(blue)
        self.alpha = Self.unit(alpha)
    }

    public static let white = TextColor(red: 1, green: 1, blue: 1)
    public static let black = TextColor(red: 0, green: 0, blue: 0)

    static func unit(_ value: Double) -> Double { value.isFinite ? min(max(value, 0), 1) : 1 }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(red: try c.decode(Double.self, forKey: .red), green: try c.decode(Double.self, forKey: .green),
                  blue: try c.decode(Double.self, forKey: .blue), alpha: try c.decode(Double.self, forKey: .alpha))
    }
}

public struct TextOverlaySpec: Equatable, Hashable, Sendable {
    public static let currentVersion = 1
    public static let sizeRange: ClosedRange<Double> = 0.03...0.25
    public static let outlineWidthRange: ClosedRange<Double> = 0...0.15
    public static let defaultSize = 0.08
    public static let defaultOutlineWidth = 0.06
    public static let defaultBoxColor = TextColor(red: 0, green: 0, blue: 0, alpha: 0.5)

    /// Cleaned: at most 280 grapheme clusters and 8 lines (`TextSanitizer`).
    public private(set) var message: String
    public var font: TextFontFamily
    public var weight: TextFontWeight
    /// Share of the picture's height per line, 0.03…0.25.
    public var size: Double { didSet { size = Self.clamp(size, Self.sizeRange, Self.defaultSize) } }
    public var color: TextColor
    public var alignment: TextAlignmentChoice
    public var verticalPosition: TextVerticalPosition
    /// Share of the font size, 0…0.15 (0: no outline).
    public var outlineWidth: Double {
        didSet { outlineWidth = Self.clamp(outlineWidth, Self.outlineWidthRange, Self.defaultOutlineWidth) }
    }
    public var outlineColor: TextColor
    public var showsBox: Bool
    public var boxColor: TextColor

    public init(message: String = "", font: TextFontFamily = .system, weight: TextFontWeight = .bold,
                size: Double = TextOverlaySpec.defaultSize, color: TextColor = .white,
                alignment: TextAlignmentChoice = .center, verticalPosition: TextVerticalPosition = .middle,
                outlineWidth: Double = TextOverlaySpec.defaultOutlineWidth, outlineColor: TextColor = .black,
                showsBox: Bool = false, boxColor: TextColor = TextOverlaySpec.defaultBoxColor) {
        self.message = TextSanitizer.clean(message).message
        self.font = font
        self.weight = weight
        self.size = Self.clamp(size, Self.sizeRange, Self.defaultSize)
        self.color = color
        self.alignment = alignment
        self.verticalPosition = verticalPosition
        self.outlineWidth = Self.clamp(outlineWidth, Self.outlineWidthRange, Self.defaultOutlineWidth)
        self.outlineColor = outlineColor
        self.showsBox = showsBox
        self.boxColor = boxColor
    }

    /// The defaults (empty message): what a new install and Reset Text show.
    public static let `default` = TextOverlaySpec()

    /// Replaces the message with its cleaned form; true when the limit cut something.
    @discardableResult
    public mutating func setMessage(_ raw: String) -> Bool {
        let cleaned = TextSanitizer.clean(raw)
        message = cleaned.message
        return cleaned.wasCut
    }

    /// Nothing to draw.
    public var isEmpty: Bool { TextSanitizer.isBlank(message) }

    static func clamp(_ value: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
    }
}

// MARK: - Storage (versioned JSON)

/// What a stored value reads as.
public enum TextOverlayDecodeResult: Equatable, Sendable {
    case spec(TextOverlaySpec)
    /// Written by a newer app version: not shown, left untouched.
    case unsupportedVersion(Int)
    /// Not readable: treated as no text and removed by the app.
    case damaged
}

extension TextOverlaySpec: Codable {
    enum CodingKeys: String, CodingKey {
        case version, message, font, weight, size, color, alignment, verticalPosition, outlineWidth, outlineColor,
             showsBox, boxColor
    }

    private struct VersionProbe: Decodable { let version: Int }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.currentVersion, forKey: .version)
        try c.encode(message, forKey: .message)
        try c.encode(font, forKey: .font)
        try c.encode(weight, forKey: .weight)
        try c.encode(size, forKey: .size)
        try c.encode(color, forKey: .color)
        try c.encode(alignment, forKey: .alignment)
        try c.encode(verticalPosition, forKey: .verticalPosition)
        try c.encode(outlineWidth, forKey: .outlineWidth)
        try c.encode(outlineColor, forKey: .outlineColor)
        try c.encode(showsBox, forKey: .showsBox)
        try c.encode(boxColor, forKey: .boxColor)
    }

    /// Decodes version 1; unknown enum raw values read as the field's default. Callers go through
    /// `decodeStored`, which checks the version first.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func choice<E: RawRepresentable>(_ key: CodingKeys, _ fallback: E) throws -> E where E.RawValue == String {
            try c.decodeIfPresent(String.self, forKey: key).flatMap(E.init(rawValue:)) ?? fallback
        }
        let d = TextOverlaySpec.default
        self.init(message: try c.decodeIfPresent(String.self, forKey: .message) ?? "",
                  font: try choice(.font, d.font),
                  weight: try choice(.weight, d.weight),
                  size: try c.decodeIfPresent(Double.self, forKey: .size) ?? d.size,
                  color: try c.decodeIfPresent(TextColor.self, forKey: .color) ?? d.color,
                  alignment: try choice(.alignment, d.alignment),
                  verticalPosition: try choice(.verticalPosition, d.verticalPosition),
                  outlineWidth: try c.decodeIfPresent(Double.self, forKey: .outlineWidth) ?? d.outlineWidth,
                  outlineColor: try c.decodeIfPresent(TextColor.self, forKey: .outlineColor) ?? d.outlineColor,
                  showsBox: try c.decodeIfPresent(Bool.self, forKey: .showsBox) ?? d.showsBox,
                  boxColor: try c.decodeIfPresent(TextColor.self, forKey: .boxColor) ?? d.boxColor)
    }

    /// JSON with sorted keys and `"version": 1`.
    public func encodedForStorage() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Encoding plain strings, enums and finite doubles cannot fail.
        return (try? encoder.encode(self)) ?? Data()
    }

    public static func decodeStored(_ data: Data) -> TextOverlayDecodeResult {
        let decoder = JSONDecoder()
        guard let probe = try? decoder.decode(VersionProbe.self, from: data) else { return .damaged }
        guard probe.version == currentVersion else { return .unsupportedVersion(probe.version) }
        guard let spec = try? decoder.decode(TextOverlaySpec.self, from: data) else { return .damaged }
        return .spec(spec)
    }
}
