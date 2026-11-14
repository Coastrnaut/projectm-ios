// ScenePalettes.swift — UIX-011 colour palettes (UIX-011-R1 to R5; research UIX-011-D1, D2, D4;
// specs/225-uix-011-color-palette-picker/contracts/palettes.md P1 to P3).
//
// * `ColorPalette`: an ID, a name (1…40 characters), a style (gradient or swatches) and 2…8 opaque sRGB colours.
//   Built-ins (Spectrum, Ice, Mono, Colour-blind safe) have fixed IDs, are read-only and are never written.
// * `PaletteLibrary`: the built-ins plus at most 64 user palettes, with the editing operations and their limits.
// * `PaletteFile`: the `projectm-ios.palettes` file, version 1, written canonically with the scene writer (sorted
//   keys, one byte sequence per library) and read leniently (damaged entries dropped and counted; a newer version
//   refused so the app never overwrites it).
// * Links: the document's and each layer's `palette` field, kept in `extra` (SCN-001-R10): no decoder change, no
//   version bump. `resolve` gives layer link → scene link → Spectrum, and reports a link to a missing palette.
// Plain Swift: no files, no Foundation.

/// An opaque sRGB colour, 8 bits per channel.
public struct PaletteColor: Sendable, Hashable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// From `#RRGGBB` (case-insensitive); nil otherwise.
    public init?(hex text: String) {
        let u = Array(text.utf8)
        guard u.count == 7, u[0] == UInt8(ascii: "#") else { return nil }
        var values: [UInt8] = []
        var i = 1
        while i < 7 {
            guard let high = Self.nibble(u[i]), let low = Self.nibble(u[i + 1]) else { return nil }
            values.append(high << 4 | low)
            i += 2
        }
        self.init(red: values[0], green: values[1], blue: values[2])
    }

    private static func nibble(_ b: UInt8) -> UInt8? {
        switch b {
        case 0x30...0x39: b - 0x30
        case 0x41...0x46: b - 0x41 + 10
        case 0x61...0x66: b - 0x61 + 10
        default: nil
        }
    }

    /// `#RRGGBB`, uppercase.
    public var hex: String {
        let digits: [Character] = Array("0123456789ABCDEF")
        var text = "#"
        for v in [red, green, blue] {
            text.append(digits[Int(v >> 4)])
            text.append(digits[Int(v & 0x0F)])
        }
        return text
    }

    /// 0…1 sRGB-encoded components.
    public var components: (red: Double, green: Double, blue: Double) {
        (Double(red) / 255, Double(green) / 255, Double(blue) / 255)
    }

    /// From 0…1 sRGB-encoded components (clamped, rounded).
    public init(fractionRed red: Double, green: Double, blue: Double) {
        func byte(_ v: Double) -> UInt8 {
            let c: Double = v.isNaN ? 0 : min(max(v, 0), 1)
            return UInt8((c * 255).rounded())
        }
        self.init(red: byte(red), green: byte(green), blue: byte(blue))
    }
}

public enum PaletteStyle: String, Sendable, Hashable, CaseIterable {
    /// Blends evenly between the colours (in linear light).
    case gradient
    /// Each colour is a solid band of equal size.
    case swatches

    public var title: String { self == .gradient ? "Gradient" : "Swatches" }
}

public struct ColorPalette: Sendable, Hashable, Identifiable {
    public static let minimumColors = 2
    public static let maximumColors = 8
    public static let maximumNameLength = 40

    public var id: String
    public var name: String
    public var style: PaletteStyle
    public var colors: [PaletteColor]
    public var isBuiltIn: Bool

    public init(id: String, name: String, style: PaletteStyle = .gradient, colors: [PaletteColor], isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.style = style
        self.colors = colors
        self.isBuiltIn = isBuiltIn
    }

    /// A user palette's name: trimmed; nil when empty or longer than 40 characters.
    public static func validName(_ name: String) -> String? {
        let trimmed: String = String(name.drop { (c: Character) -> Bool in c.isWhitespace }.reversed()
            .drop { (c: Character) -> Bool in c.isWhitespace }.reversed())
        guard !trimmed.isEmpty, trimmed.count <= maximumNameLength else { return nil }
        return trimmed
    }

    // MARK: Built-ins (VIS-001 and ACC-003 palettes; the app draws them exactly with VisualPalette)

    public static let spectrumID = "builtin.spectrum"
    public static let iceID = "builtin.ice"
    public static let monoID = "builtin.mono"
    public static let colorBlindSafeID = "builtin.colorBlindSafe"
    /// The palette drawn without a link, or for a link to a missing palette.
    public static let defaultID = spectrumID

    private static func colors(_ hexes: [String]) -> [PaletteColor] {
        hexes.compactMap { (text: String) -> PaletteColor? in PaletteColor(hex: text) }
    }

    /// Spectrum's swatches are its hue ramp (0°…270°) sampled every 45°.
    public static let builtIns: [ColorPalette] = [
        ColorPalette(id: spectrumID, name: "Spectrum",
                     colors: colors(["#FF0000", "#FFBF00", "#80FF00", "#00FF40", "#00FFFF", "#0040FF", "#8000FF"]), isBuiltIn: true),
        ColorPalette(id: iceID, name: "Ice", colors: colors(["#2EC4FF", "#E8F7FF"]), isBuiltIn: true),
        ColorPalette(id: monoID, name: "Mono", colors: colors(["#FFFFFF", "#FFFFFF"]), isBuiltIn: true),
        ColorPalette(id: colorBlindSafeID, name: "Colour-blind safe",
                     colors: colors(["#4D5C7B", "#6B6F7A", "#8F8A78", "#BBAE6E", "#FDE738"]), isBuiltIn: true),
    ]

    public static func isBuiltInID(_ id: String) -> Bool { builtIns.contains { (p: ColorPalette) -> Bool in p.id == id } }

    /// A user palette entry is valid: canonical UUID, valid name, 2…8 colours.
    var isValidUserPalette: Bool {
        !isBuiltIn && SceneDocument.isCanonicalUUID(id) && Self.validName(name) == name
            && (Self.minimumColors...Self.maximumColors).contains(colors.count)
    }
}

public enum PaletteEditError: Error, Sendable, Hashable {
    case builtIn
    case notFound
    case tooManyPalettes(limit: Int)
    case invalidName
    case colorLimit
    case readOnly

    public var message: String {
        switch self {
        case .builtIn: "Built-in palettes can't be changed. Duplicate it to edit a copy."
        case .notFound: "That palette no longer exists."
        case let .tooManyPalettes(limit): "You can keep at most \(limit) palettes. Delete one to make another."
        case .invalidName: "A palette name needs 1 to \(ColorPalette.maximumNameLength) characters."
        case .colorLimit: "A palette has \(ColorPalette.minimumColors) to \(ColorPalette.maximumColors) colours."
        case .readOnly: "Palettes were saved by a newer version of the app. Update the app to edit them."
        }
    }
}

public struct PaletteLibrary: Sendable, Hashable {
    public static let maximumUserPalettes = 64

    /// File order = display order.
    public private(set) var user: [ColorPalette]

    public init(user: [ColorPalette] = []) {
        self.user = Array(user.prefix(Self.maximumUserPalettes))
    }

    /// Built-ins first, then the user palettes.
    public var all: [ColorPalette] { ColorPalette.builtIns + user }

    public func palette(_ id: String) -> ColorPalette? {
        all.first { (p: ColorPalette) -> Bool in p.id == id }
    }

    public var canCreate: Bool { user.count < Self.maximumUserPalettes }

    // MARK: Editing (every operation leaves the library valid)

    /// A new user palette with `id` (a fresh canonical UUID from the caller).
    public mutating func create(id: String, name: String, style: PaletteStyle = .gradient,
                                colors: [PaletteColor]) throws(PaletteEditError) {
        guard canCreate else { throw .tooManyPalettes(limit: Self.maximumUserPalettes) }
        guard let valid = ColorPalette.validName(name) else { throw .invalidName }
        guard (ColorPalette.minimumColors...ColorPalette.maximumColors).contains(colors.count) else { throw .colorLimit }
        guard SceneDocument.isCanonicalUUID(id), palette(id) == nil else { throw .notFound }
        user.append(ColorPalette(id: id, name: valid, style: style, colors: colors))
    }

    /// A copy of any palette (built-in or user) as a new user palette named "<name> copy".
    public mutating func duplicate(_ sourceID: String, newID: String) throws(PaletteEditError) {
        guard let source = palette(sourceID) else { throw .notFound }
        try create(id: newID, name: Self.copyName(source.name, taken: Set(all.map(\.name))), style: source.style,
                   colors: source.colors)
    }

    /// "<name> copy", "<name> copy 2", … not taken, at most 40 characters.
    public static func copyName(_ name: String, taken: Set<String>) -> String {
        var number = 1
        while true {
            let suffix: String = number == 1 ? " copy" : " copy " + String(number)
            let base: String = String(name.prefix(ColorPalette.maximumNameLength - suffix.count))
            let candidate: String = (ColorPalette.validName(base) ?? "Palette") + suffix
            if !taken.contains(candidate) { return candidate }
            number += 1
        }
    }

    public mutating func rename(_ id: String, to name: String) throws(PaletteEditError) {
        guard let valid = ColorPalette.validName(name) else { throw .invalidName }
        try edit(id) { (p: inout ColorPalette) in p.name = valid }
    }

    public mutating func setStyle(_ id: String, _ style: PaletteStyle) throws(PaletteEditError) {
        try edit(id) { (p: inout ColorPalette) in p.style = style }
    }

    public mutating func setColor(_ id: String, at index: Int, to color: PaletteColor) throws(PaletteEditError) {
        let i: Int = try userIndex(id)
        guard user[i].colors.indices.contains(index) else { throw .colorLimit }
        user[i].colors[index] = color
    }

    /// Appends a colour (a copy of the last one by default) up to 8.
    public mutating func addColor(_ id: String, _ color: PaletteColor? = nil) throws(PaletteEditError) {
        let i: Int = try userIndex(id)
        let colors: [PaletteColor] = user[i].colors
        guard colors.count < ColorPalette.maximumColors, let last = colors.last else { throw .colorLimit }
        user[i].colors.append(color ?? last)
    }

    /// Removes colour `index` down to 2.
    public mutating func removeColor(_ id: String, at index: Int) throws(PaletteEditError) {
        let i: Int = try userIndex(id)
        guard user[i].colors.count > ColorPalette.minimumColors, user[i].colors.indices.contains(index) else { throw .colorLimit }
        user[i].colors.remove(at: index)
    }

    public mutating func delete(_ id: String) throws(PaletteEditError) {
        let i: Int = try userIndex(id)
        user.remove(at: i)
    }

    /// Replaces (or appends, within the limit) a whole user palette; used by restores.
    public mutating func upsert(_ palette: ColorPalette) throws(PaletteEditError) {
        guard palette.isValidUserPalette else { throw .invalidName }
        if let i = user.firstIndex(where: { (p: ColorPalette) -> Bool in p.id == palette.id }) {
            user[i] = palette
        } else {
            guard canCreate else { throw .tooManyPalettes(limit: Self.maximumUserPalettes) }
            user.append(palette)
        }
    }

    private mutating func edit(_ id: String, _ change: (inout ColorPalette) -> Void) throws(PaletteEditError) {
        let i: Int = try userIndex(id)
        change(&user[i])
    }

    private func userIndex(_ id: String) throws(PaletteEditError) -> Int {
        if ColorPalette.isBuiltInID(id) { throw .builtIn }
        guard let i = user.firstIndex(where: { (p: ColorPalette) -> Bool in p.id == id }) else { throw .notFound }
        return i
    }

    // MARK: Resolution (contract P3)

    /// The palette for a link (nil = no link): the linked palette, or Spectrum with `isMissing` for an unknown ID.
    public func resolve(_ link: String?) -> PaletteResolution {
        let fallback: ColorPalette = ColorPalette.builtIns[0]
        guard let link else { return PaletteResolution(palette: fallback, requestedID: nil, isMissing: false) }
        guard let found = palette(link) else { return PaletteResolution(palette: fallback, requestedID: link, isMissing: true) }
        return PaletteResolution(palette: found, requestedID: link, isMissing: false)
    }

    /// Layer `index` of `document`: the layer's link, else the scene's, else none.
    public func resolve(layer index: Int, in document: SceneDocument) -> PaletteResolution {
        let layerLink: String? = document.layers.indices.contains(index) ? document.layers[index].paletteID : nil
        return resolve(layerLink ?? document.paletteID)
    }
}

public struct PaletteResolution: Sendable, Hashable {
    public let palette: ColorPalette
    /// The link as stored (nil: no link).
    public let requestedID: String?
    /// The link names a palette the library does not have; the default is drawn.
    public let isMissing: Bool
}

// MARK: - The file (contract P1)

public enum PaletteFileError: Error, Sendable, Hashable {
    case notAPaletteFile
    case newerVersion(Int)
    case unreadable
}

public enum PaletteFile {
    public static let formatName = "projectm-ios.palettes"
    public static let currentVersion = 1
    public static let fileName = "palettes.json"
    public static let folderName = "Palettes"

    /// Canonical bytes (built-ins are never written).
    public static func encode(_ library: PaletteLibrary) -> [UInt8] {
        let entries: [SceneJSON] = library.user.map { (p: ColorPalette) -> SceneJSON in entry(p) }
        let root: [String: SceneJSON] = ["format": .string(formatName), "version": .integer(Int64(currentVersion)),
                                         "palettes": .array(entries)]
        return SceneJSONWriter.write(.object(root))
    }

    /// One palette's canonical bytes (FILE-005 compares palettes by these).
    public static func encode(_ palette: ColorPalette) -> [UInt8] { SceneJSONWriter.write(entry(palette)) }

    static func entry(_ p: ColorPalette) -> SceneJSON {
        let colors: [SceneJSON] = p.colors.map { (c: PaletteColor) -> SceneJSON in .string(c.hex) }
        return .object(["id": .string(p.id), "name": .string(p.name), "style": .string(p.style.rawValue), "colors": .array(colors)])
    }

    /// The library and how many entries were dropped as damaged (or duplicates, or beyond 64).
    public static func decode(_ bytes: [UInt8]) throws(PaletteFileError) -> (library: PaletteLibrary, dropped: Int) {
        let json: SceneJSON
        do { json = try SceneJSON.parse(bytes) } catch { throw .unreadable }
        guard let root = json.objectValue, root["format"]?.stringValue == formatName else { throw .notAPaletteFile }
        guard let version = root["version"]?.numberValue?.int64Value, version >= 1 else { throw .unreadable }
        guard version <= Int64(currentVersion) else { throw .newerVersion(Int(version)) }
        guard let items = root["palettes"]?.arrayValue else { throw .unreadable }
        var kept: [ColorPalette] = []
        var ids: Set<String> = []
        var dropped = 0
        for item in items {
            guard let palette = decodeEntry(item), !ids.contains(palette.id),
                  kept.count < PaletteLibrary.maximumUserPalettes else { dropped += 1; continue }
            ids.insert(palette.id)
            kept.append(palette)
        }
        return (PaletteLibrary(user: kept), dropped)
    }

    static func decodeEntry(_ item: SceneJSON) -> ColorPalette? {
        guard let o = item.objectValue, let id = o["id"]?.stringValue, let name = o["name"]?.stringValue,
              let styleText = o["style"]?.stringValue, let style = PaletteStyle(rawValue: styleText),
              let list = o["colors"]?.arrayValue else { return nil }
        let colors: [PaletteColor] = list.compactMap { (c: SceneJSON) -> PaletteColor? in c.stringValue.flatMap(PaletteColor.init(hex:)) }
        guard colors.count == list.count else { return nil }
        let palette = ColorPalette(id: id, name: name, style: style, colors: colors)
        return palette.isValidUserPalette ? palette : nil
    }
}

// MARK: - Scene links (contract P2)

public enum ScenePaletteLink {
    /// The field name on the document and on layers.
    public static let field = "palette"
    /// Layer kinds that draw with a palette (the app writes the scene's choice on them).
    public static let paletteKinds: Set<String> = ["spectrum.circular", "spectrum.linear"]
}

extension SceneDocument {
    /// UIX-011: the scene's palette ID (nil: no link).
    public var paletteID: String? {
        get { extra[ScenePaletteLink.field]?.stringValue }
        set { extra[ScenePaletteLink.field] = newValue.map { (id: String) -> SceneJSON in .string(id) } }
    }
}

extension SceneLayer {
    /// UIX-011: this layer's palette ID (nil: the scene's).
    public var paletteID: String? {
        get { extra[ScenePaletteLink.field]?.stringValue }
        set { extra[ScenePaletteLink.field] = newValue.map { (id: String) -> SceneJSON in .string(id) } }
    }
}
