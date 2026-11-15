// OutputProfile.swift — OUT-014 (spec specs/288-out-014-output-profile-export, contract C1; research OUT-014-D1-D3,
// D5): the external output's display transforms as one value, its local file (`.pmoutput`) and the display class it
// was made for. Pure Swift (Foundation's JSON coders only), builds on Linux.
//
// * A profile holds exactly Settings › External Display's transforms: fit, shape, pixel aspect (OUT-004), resolution
//   and its percentage (OUT-003), output mode (OUT-006), corner pin (OUT-007) and colour calibration (OUT-009), plus
//   the optional class of the display it was made for. It never holds a name, identifier or address.
// * The document is sorted-key JSON with a format tag and a version. Import is untrusted and all or nothing: at most
//   16 KB, the format tag, a known version, exactly the known fields at every level, and every value valid by the
//   settings' own rules (enum names, percentage 50…100, `CornerPin.isValid`, calibration ranges). Out-of-range values
//   are refused, never clamped: a clamped calibration would not reproduce the original (OUT-014-D2).
// * The calibration ranges mirror Compositor's `DisplayCalibration.gammaRange` and `trimRange` (this package cannot
//   depend on Compositor); an app test asserts they are equal.
// * OUT-008 (spec specs/309-out-008-grid-warp, contract C5): an optional `settings.gridWarp` ({columns, rows, points})
//   carries a non-identity grid warp; absent reads as the identity, and any invalid mesh (`GridWarp.isValid`) refuses
//   the import. The format version is unchanged: older files have no such field.
// * Same display class (spec Clarifications): same native pixel size, the screen's pixel aspect within 0.005 and, when
//   both report one, the same gamut. The refresh rate is recorded but not compared.
import Foundation

/// The class of display a profile was made for (OUT-014-R2; from OUT-011's readings).
public struct OutputDisplayClass: Equatable, Sendable {
    public var nativeWidth: Int
    public var nativeHeight: Int
    /// The screen's own pixel aspect ratio (not the user's override), sanitised as OUT-004 does.
    public var pixelAspect: Double
    public var refreshRate: Int?
    public var gamut: OutputReadings.Gamut?

    public static let sizeRange: ClosedRange<Int> = 1...32_768
    public static let pixelAspectRange: ClosedRange<Double> = 0.5...2
    public static let refreshRange: ClosedRange<Int> = 1...1_000
    /// Pixel aspects closer than this are the same.
    public static let pixelAspectTolerance = 0.005

    public init(nativeWidth: Int, nativeHeight: Int, pixelAspect: Double, refreshRate: Int? = nil,
                gamut: OutputReadings.Gamut? = nil) {
        self.nativeWidth = nativeWidth
        self.nativeHeight = nativeHeight
        self.pixelAspect = pixelAspect
        self.refreshRate = refreshRate
        self.gamut = gamut
    }

    /// The class of a connected display: nil without a native size. `screenPixelAspect` is sanitised (0.5…2, else 1).
    public init?(readings: OutputReadings, screenPixelAspect: Double?) {
        let r: OutputReadings = readings.sanitized()
        guard let w = r.nativeWidth, let h = r.nativeHeight, Self.sizeRange.contains(w), Self.sizeRange.contains(h) else { return nil }
        let fps: Int? = r.maximumFramesPerSecond.flatMap { (n: Int) -> Int? in Self.refreshRange.contains(n) ? n : nil }
        self.init(nativeWidth: w, nativeHeight: h, pixelAspect: ExternalPixelAspect.sanitized(screenPixelAspect),
                  refreshRate: fps, gamut: r.gamut)
    }

    /// Whether every value is in range (decoded files).
    public var isValid: Bool {
        guard Self.sizeRange.contains(nativeWidth), Self.sizeRange.contains(nativeHeight) else { return false }
        guard pixelAspect.isFinite, Self.pixelAspectRange.contains(pixelAspect) else { return false }
        if let refreshRate, !Self.refreshRange.contains(refreshRate) { return false }
        return true
    }

    /// The profile's class against the connected one (OUT-014-R8, R9).
    public static func match(profile: OutputDisplayClass?, connected: OutputDisplayClass?) -> OutputDisplayClassMatch {
        guard let profile, let connected else { return .unknown }
        var differences: [OutputDisplayClassMatch.Difference] = []
        if profile.nativeWidth != connected.nativeWidth || profile.nativeHeight != connected.nativeHeight {
            differences.append(.resolution)
        }
        if abs(profile.pixelAspect - connected.pixelAspect) > pixelAspectTolerance { differences.append(.pixelAspect) }
        if let a = profile.gamut, let b = connected.gamut, a != b { differences.append(.gamut) }
        return differences.isEmpty ? .same : .different(differences)
    }

    /// "1920 × 1080 px, pixel aspect 1.00, 60 Hz, sRGB" (refresh and gamut only when known).
    public var summary: String {
        var parts: [String] = [String(nativeWidth) + " × " + String(nativeHeight) + " px", "pixel aspect " + Self.twoDecimals(pixelAspect)]
        if let refreshRate { parts.append(String(refreshRate) + " Hz") }
        if let gamut { parts.append(Self.title(gamut)) }
        return parts.joined(separator: ", ")
    }

    static func title(_ gamut: OutputReadings.Gamut) -> String {
        switch gamut {
        case .sRGB: "sRGB"
        case .displayP3: "Display P3"
        }
    }

    static func twoDecimals(_ value: Double) -> String {
        let hundredths: Int = Int((value * 100).rounded())
        let fraction: Int = abs(hundredths) % 100
        let padded: String = fraction < 10 ? "0" + String(fraction) : String(fraction)
        return String(hundredths / 100) + "." + padded
    }
}

/// How a profile's display class compares with the connected display's.
public enum OutputDisplayClassMatch: Equatable, Sendable {
    public enum Difference: String, Equatable, Sendable, CaseIterable {
        case resolution, pixelAspect, gamut

        public var title: String {
            switch self {
            case .resolution: "resolution"
            case .pixelAspect: "pixel aspect"
            case .gamut: "color gamut"
            }
        }
    }

    case same
    case different([Difference])
    /// No display connected, or the profile names none: cannot be compared.
    case unknown
}

/// The display transforms of Settings › External Display (OUT-014-R2).
public struct OutputProfile: Equatable, Sendable {
    /// OUT-009's calibration values; the ranges mirror `DisplayCalibration` (an app test asserts it).
    public struct Calibration: Equatable, Sendable {
        public var gamma: Double
        public var red: Double
        public var green: Double
        public var blue: Double

        public static let gammaRange: ClosedRange<Double> = 0.5...2.5
        public static let trimRange: ClosedRange<Double> = 0.5...1.5
        public static let identity = Calibration(gamma: 1, red: 1, green: 1, blue: 1)

        public init(gamma: Double, red: Double, green: Double, blue: Double) {
            self.gamma = gamma
            self.red = red
            self.green = green
            self.blue = blue
        }

        /// The first value outside its range ("gamma", "red", …), nil when all are valid.
        public var invalidField: String? {
            if !(gamma.isFinite && Self.gammaRange.contains(gamma)) { return "gamma" }
            if !(red.isFinite && Self.trimRange.contains(red)) { return "red" }
            if !(green.isFinite && Self.trimRange.contains(green)) { return "green" }
            if !(blue.isFinite && Self.trimRange.contains(blue)) { return "blue" }
            return nil
        }
    }

    public var fit: ExternalOutputFit
    public var shape: ExternalOutputShape
    public var pixelAspect: ExternalPixelAspect
    public var resolution: ExternalOutputResolution
    public var outputMode: ExternalOutputMode
    public var cornerPin: CornerPin
    public var calibration: Calibration
    public var display: OutputDisplayClass?
    /// OUT-008: the grid warp (the identity when the file has none).
    public var gridWarp: GridWarp

    public init(fit: ExternalOutputFit = .fit, shape: ExternalOutputShape = .display, pixelAspect: ExternalPixelAspect = .automatic,
                resolution: ExternalOutputResolution = .native, outputMode: ExternalOutputMode = .default,
                cornerPin: CornerPin = .identity, calibration: Calibration = .identity, display: OutputDisplayClass? = nil,
                gridWarp: GridWarp = .identity) {
        self.fit = fit
        self.shape = shape
        self.pixelAspect = pixelAspect
        self.resolution = resolution
        self.outputMode = outputMode
        self.cornerPin = cornerPin
        self.calibration = calibration
        self.display = display
        self.gridWarp = gridWarp
    }
}

/// Why a document was refused (contract C1). Nothing is returned, so nothing can be applied, when one is thrown.
public enum OutputProfileImportError: Error, Sendable, Hashable {
    case empty
    case tooLarge
    case notAProfile
    case newerVersion(Int)
    case missingField(String)
    case unknownField(String)
    case invalidValue(String)

    public var message: String {
        switch self {
        case .empty: "The file is empty."
        case .tooLarge: "The file is too large to be an output profile."
        case .notAProfile: "The file is not a projectM output profile."
        case let .newerVersion(version): "The profile was made by a newer version of projectM (format " + String(version) + ")."
        case let .missingField(field): "The profile is incomplete (" + field + " is missing)."
        case let .unknownField(field): "The profile contains data this version does not use (" + field + ")."
        case let .invalidValue(field): "The profile has an invalid value (" + field + ")."
        }
    }
}

/// The exported document (research OUT-014-D4, data-model "Document").
public enum OutputProfileDocument {
    public static let format = "org.projectmios.output-profile"
    public static let version = 1
    public static let fileExtension = "pmoutput"
    public static let fileName = "projectM Output Profile." + fileExtension
    /// An imported document is read up to this size.
    public static let maxBytes = 16 * 1024

    private static let topKeys: Set<String> = ["format", "version", "settings", "display"]
    private static let requiredTopKeys: Set<String> = ["format", "version", "settings"]
    private static let settingsKeys: Set<String> = ["fit", "shape", "pixelAspect", "resolution", "resolutionPercent",
                                                    "outputMode", "cornerPin", "calibration"]
    private static let calibrationKeys: Set<String> = ["gamma", "red", "green", "blue"]
    private static let gridWarpKeys: Set<String> = ["columns", "rows", "points"]   // OUT-008
    private static let pointKeys: Set<String> = ["x", "y"]
    private static let displayKeys: Set<String> = ["nativeWidth", "nativeHeight", "pixelAspect", "refreshRate", "gamut"]
    private static let requiredDisplayKeys: Set<String> = ["nativeWidth", "nativeHeight", "pixelAspect"]

    private struct Point: Codable {
        let x: Double
        let y: Double
    }

    private struct CalibrationBody: Codable {
        let gamma: Double
        let red: Double
        let green: Double
        let blue: Double
    }

    private struct GridWarpBody: Codable {   // OUT-008
        let columns: Int
        let rows: Int
        let points: [Point]
    }

    private struct Settings: Codable {
        let fit: String
        let shape: String
        let pixelAspect: String
        let resolution: String
        let resolutionPercent: Int
        let outputMode: String
        let cornerPin: [Point]
        let calibration: CalibrationBody
        let gridWarp: GridWarpBody?   // OUT-008: written only when not the identity
    }

    private struct Display: Codable {
        let nativeWidth: Int
        let nativeHeight: Int
        let pixelAspect: Double
        let refreshRate: Int?
        let gamut: String?
    }

    private struct Body: Codable {
        let format: String
        let version: Int
        let settings: Settings
        let display: Display?
    }

    // MARK: Encode

    /// Sorted-key, pretty-printed JSON of the profile (no other data exists to write).
    public static func encode(_ profile: OutputProfile) -> Data {
        let points: [Point] = profile.cornerPin.corners.map { (p: CornerPinPoint) -> Point in Point(x: p.x, y: p.y) }
        let c: OutputProfile.Calibration = profile.calibration
        let settings = Settings(fit: profile.fit.rawValue, shape: profile.shape.rawValue, pixelAspect: profile.pixelAspect.rawValue,
                                resolution: profile.resolution.mode.rawValue, resolutionPercent: profile.resolution.percent,
                                outputMode: profile.outputMode.rawValue, cornerPin: points,
                                calibration: CalibrationBody(gamma: c.gamma, red: c.red, green: c.green, blue: c.blue),
                                gridWarp: Self.body(profile.gridWarp))
        let display: Display? = profile.display.map { (d: OutputDisplayClass) -> Display in
            Display(nativeWidth: d.nativeWidth, nativeHeight: d.nativeHeight, pixelAspect: d.pixelAspect,
                    refreshRate: d.refreshRate, gamut: d.gamut?.rawValue)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return (try? encoder.encode(Body(format: format, version: version, settings: settings, display: display))) ?? Data()
    }

    /// OUT-008: nil for the identity.
    private static func body(_ warp: GridWarp) -> GridWarpBody? {
        guard !warp.isIdentity else { return nil }
        let points: [Point] = warp.points.map { (p: GridWarpPoint) -> Point in Point(x: p.x, y: p.y) }
        return GridWarpBody(columns: warp.columns, rows: warp.rows, points: points)
    }

    // MARK: Decode

    /// Reads and validates a document (untrusted input); returns a profile only when every check passes.
    public static func decode(_ data: Data) throws(OutputProfileImportError) -> OutputProfile {
        guard !data.isEmpty else { throw .empty }
        guard data.count <= maxBytes else { throw .tooLarge }
        guard let object = try? JSONSerialization.jsonObject(with: data), let top = object as? [String: Any] else { throw .notAProfile }
        guard top["format"] as? String == format else { throw .notAProfile }
        guard let number = Self.number(top["version"]), number == number.rounded(), number >= 1, number < 1_000_000 else {
            throw .notAProfile
        }
        let fileVersion = Int(number)
        guard fileVersion <= version else { throw .newerVersion(fileVersion) }
        try checkKeys(top, allowed: topKeys, required: requiredTopKeys, path: "")
        try checkNested(top)
        let body: Body
        do {
            body = try JSONDecoder().decode(Body.self, from: data)
        } catch {
            throw .invalidValue(Self.path(of: error))
        }
        return try profile(body)
    }

    private static func checkNested(_ top: [String: Any]) throws(OutputProfileImportError) {
        guard let settings = top["settings"] as? [String: Any] else { throw .invalidValue("settings") }
        try checkKeys(settings, allowed: settingsKeys.union(["gridWarp"]), required: settingsKeys, path: "settings.")
        guard let percent = Self.number(settings["resolutionPercent"]), percent == percent.rounded() else {
            throw .invalidValue("settings.resolutionPercent")   // a whole number (JSONDecoder's error has no path here)
        }
        guard let calibration = settings["calibration"] as? [String: Any] else { throw .invalidValue("settings.calibration") }
        try checkKeys(calibration, allowed: calibrationKeys, required: calibrationKeys, path: "settings.calibration.")
        guard let corners = settings["cornerPin"] as? [Any], corners.count == 4 else { throw .invalidValue("settings.cornerPin") }
        for (index, corner) in corners.enumerated() {
            guard let point = corner as? [String: Any] else { throw .invalidValue("settings.cornerPin") }
            try checkKeys(point, allowed: pointKeys, required: pointKeys, path: "settings.cornerPin[" + String(index) + "].")
        }
        if let warp = settings["gridWarp"] {   // OUT-008
            guard let fields = warp as? [String: Any] else { throw .invalidValue("settings.gridWarp") }
            try checkKeys(fields, allowed: gridWarpKeys, required: gridWarpKeys, path: "settings.gridWarp.")
            guard let points = fields["points"] as? [Any] else { throw .invalidValue("settings.gridWarp") }
            for (index, point) in points.enumerated() {
                guard let fields = point as? [String: Any] else { throw .invalidValue("settings.gridWarp") }
                try checkKeys(fields, allowed: pointKeys, required: pointKeys, path: "settings.gridWarp.points[" + String(index) + "].")
            }
        }
        if let display = top["display"] {
            guard let fields = display as? [String: Any] else { throw .invalidValue("display") }
            try checkKeys(fields, allowed: displayKeys, required: requiredDisplayKeys, path: "display.")
        }
    }

    /// A JSON number as a Double (NSNumber on Apple platforms, Int or Double elsewhere); nil for anything else. A JSON
    /// `true` may read as 1 here; the typed decode that follows refuses it.
    private static func number(_ value: Any?) -> Double? {
        if let v = value as? Int { return Double(v) }
        if let v = value as? Double { return v }
        if let v = value as? NSNumber { return v.doubleValue }
        return nil
    }

    private static func checkKeys(_ object: [String: Any], allowed: Set<String>, required: Set<String>,
                                  path: String) throws(OutputProfileImportError) {
        if let unknown = object.keys.filter({ (key: String) -> Bool in !allowed.contains(key) }).sorted().first {
            throw .unknownField(path + unknown)
        }
        if let missing = required.filter({ (key: String) -> Bool in object[key] == nil }).sorted().first {
            throw .missingField(path + missing)
        }
    }

    /// The coding path of a decoding error ("settings.resolutionPercent"), or "file".
    private static func path(of error: any Error) -> String {
        let context: DecodingError.Context?
        switch error as? DecodingError {
        case let .typeMismatch(_, c)?: context = c
        case let .valueNotFound(_, c)?: context = c
        case let .keyNotFound(_, c)?: context = c
        case let .dataCorrupted(c)?: context = c
        default: context = nil
        }
        guard let keys = context?.codingPath, !keys.isEmpty else { return "file" }
        return keys.map { (key: any CodingKey) -> String in key.intValue.map { (i: Int) -> String in String(i) } ?? key.stringValue }
            .joined(separator: ".")
    }

    private static func profile(_ body: Body) throws(OutputProfileImportError) -> OutputProfile {
        let s: Settings = body.settings
        guard let fit = ExternalOutputFit(rawValue: s.fit) else { throw .invalidValue("settings.fit") }
        guard let shape = ExternalOutputShape(rawValue: s.shape) else { throw .invalidValue("settings.shape") }
        guard let aspect = ExternalPixelAspect(rawValue: s.pixelAspect) else { throw .invalidValue("settings.pixelAspect") }
        guard let mode = ExternalResolutionMode(rawValue: s.resolution) else { throw .invalidValue("settings.resolution") }
        guard ExternalOutputResolution.percentRange.contains(s.resolutionPercent) else { throw .invalidValue("settings.resolutionPercent") }
        guard let outputMode = ExternalOutputMode(rawValue: s.outputMode) else { throw .invalidValue("settings.outputMode") }
        let points: [CornerPinPoint] = s.cornerPin.map { (p: Point) -> CornerPinPoint in CornerPinPoint(x: p.x, y: p.y) }
        guard points.count == 4,
              let pin = CornerPin(topLeft: points[0], topRight: points[1], bottomRight: points[2], bottomLeft: points[3])
        else { throw .invalidValue("settings.cornerPin") }
        let c: CalibrationBody = s.calibration
        let calibration = OutputProfile.Calibration(gamma: c.gamma, red: c.red, green: c.green, blue: c.blue)
        if let field = calibration.invalidField { throw .invalidValue("settings.calibration." + field) }
        var warp: GridWarp = .identity   // OUT-008
        if let g = s.gridWarp {
            let points: [GridWarpPoint] = g.points.map { (p: Point) -> GridWarpPoint in GridWarpPoint(x: p.x, y: p.y) }
            guard let valid = GridWarp(columns: g.columns, rows: g.rows, points: points) else { throw .invalidValue("settings.gridWarp") }
            warp = valid
        }
        var display: OutputDisplayClass?
        if let d = body.display {
            var gamut: OutputReadings.Gamut?
            if let name = d.gamut {
                guard let known = OutputReadings.Gamut(rawValue: name) else { throw .invalidValue("display.gamut") }
                gamut = known
            }
            let candidate = OutputDisplayClass(nativeWidth: d.nativeWidth, nativeHeight: d.nativeHeight, pixelAspect: d.pixelAspect,
                                               refreshRate: d.refreshRate, gamut: gamut)
            guard candidate.isValid else { throw .invalidValue("display") }
            display = candidate
        }
        return OutputProfile(fit: fit, shape: shape, pixelAspect: aspect,
                             resolution: ExternalOutputResolution(mode: mode, percent: s.resolutionPercent),
                             outputMode: outputMode, cornerPin: pin, calibration: calibration, display: display, gridWarp: warp)
    }
}
