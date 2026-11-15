// OutputDiagnostics.swift — OUT-011 (spec specs/275-out-011-output-diagnostics, contract C1): what a connected external
// display reports, as a value built at read time from the live screen, or `.disconnected`. It is never cached across
// reads or connections (OUT-011-R4), so an unplugged display can only read as disconnected, never as stale numbers.
// Formats are fixed (spec Clarifications, speckit-clarify); anything the system does not report reads "Not available"
// (OUT-011-R3). Pure Swift: no UIKit, builds on Linux.
import Foundation

/// One display's readings. Every field is optional: nil means the system did not report it.
public struct OutputReadings: Equatable, Sendable {
    public enum Gamut: String, Equatable, Sendable { case sRGB, displayP3 }
    public enum Overscan: String, Equatable, Sendable { case scale, insetBounds, off }

    public var nativeWidth: Int?
    public var nativeHeight: Int?
    public var nativeScale: Double?
    public var pointWidth: Double?
    public var pointHeight: Double?
    public var scale: Double?
    public var maximumFramesPerSecond: Int?
    public var gamut: Gamut?
    public var potentialEDRHeadroom: Double?
    public var currentEDRHeadroom: Double?
    public var mirrored: Bool?
    public var overscan: Overscan?
    /// OUT-003: the drawable the visual renders at on this display (nil while the visual is elsewhere).
    public var drawableWidth: Int?
    public var drawableHeight: Int?
    /// OUT-004: the resolved pixel aspect ratio.
    public var pixelAspect: Double?
    /// OUT-006: the output mode's title.
    public var outputMode: String?

    public init(nativeWidth: Int? = nil, nativeHeight: Int? = nil, nativeScale: Double? = nil,
                pointWidth: Double? = nil, pointHeight: Double? = nil, scale: Double? = nil,
                maximumFramesPerSecond: Int? = nil, gamut: Gamut? = nil,
                potentialEDRHeadroom: Double? = nil, currentEDRHeadroom: Double? = nil,
                mirrored: Bool? = nil, overscan: Overscan? = nil,
                drawableWidth: Int? = nil, drawableHeight: Int? = nil,
                pixelAspect: Double? = nil, outputMode: String? = nil) {
        self.nativeWidth = nativeWidth
        self.nativeHeight = nativeHeight
        self.nativeScale = nativeScale
        self.pointWidth = pointWidth
        self.pointHeight = pointHeight
        self.scale = scale
        self.maximumFramesPerSecond = maximumFramesPerSecond
        self.gamut = gamut
        self.potentialEDRHeadroom = potentialEDRHeadroom
        self.currentEDRHeadroom = currentEDRHeadroom
        self.mirrored = mirrored
        self.overscan = overscan
        self.drawableWidth = drawableWidth
        self.drawableHeight = drawableHeight
        self.pixelAspect = pixelAspect
        self.outputMode = outputMode
    }

    /// OUT-011-D3: zero, negative and non-finite readings become nil ("Not available"); a size needs both sides.
    public func sanitized() -> OutputReadings {
        var r = self
        if !Self.isSize(nativeWidth, nativeHeight) { r.nativeWidth = nil; r.nativeHeight = nil }
        if !Self.isSize(drawableWidth, drawableHeight) { r.drawableWidth = nil; r.drawableHeight = nil }
        if !Self.isPositive(pointWidth) || !Self.isPositive(pointHeight) || (pointWidth ?? 0) < 1 || (pointHeight ?? 0) < 1 {
            r.pointWidth = nil
            r.pointHeight = nil
        }
        r.nativeScale = Self.positive(nativeScale)
        r.scale = Self.positive(scale)
        r.potentialEDRHeadroom = Self.positive(potentialEDRHeadroom)
        r.currentEDRHeadroom = Self.positive(currentEDRHeadroom)
        r.pixelAspect = Self.positive(pixelAspect)
        if let fps = maximumFramesPerSecond, fps <= 0 { r.maximumFramesPerSecond = nil }
        if let mode = outputMode, mode.isEmpty { r.outputMode = nil }
        return r
    }

    private static func isSize(_ w: Int?, _ h: Int?) -> Bool {
        guard let w, let h else { return false }
        return w >= 1 && h >= 1
    }

    private static func isPositive(_ value: Double?) -> Bool {
        guard let value else { return false }
        return value.isFinite && value > 0
    }

    private static func positive(_ value: Double?) -> Double? { isPositive(value) ? value : nil }
}

/// One labelled row of the panel (VoiceOver: label = title, value = value; OUT-011-R7).
public struct OutputDiagnosticsRow: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let value: String

    public init(id: String, title: String, value: String) {
        self.id = id
        self.title = title
        self.value = value
    }
}

/// OUT-011 (contract C1): disconnected, or one connected display's sanitised readings.
public enum OutputDiagnostics: Equatable, Sendable {
    case disconnected
    case connected(OutputReadings)

    public static let notAvailable = "Not available"
    public static let disconnectedText = "No external display connected"

    /// Sanitises the readings (OUT-011-R3).
    public static func make(_ readings: OutputReadings) -> OutputDiagnostics { .connected(readings.sanitized()) }

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    /// Disconnected: one status row. Connected: ten rows in a fixed order (OUT-011-R2).
    public var rows: [OutputDiagnosticsRow] {
        switch self {
        case .disconnected:
            return [OutputDiagnosticsRow(id: "status", title: "Status", value: Self.disconnectedText)]
        case let .connected(r):
            return Self.rows(r)
        }
    }

    /// "Title: value" per row, one per line (the copy text; OUT-011-R8).
    public var text: String {
        rows.map { (row: OutputDiagnosticsRow) -> String in row.title + ": " + row.value }.joined(separator: "\n")
    }

    /// The DEBUG probe: "disconnected", or "connected native=WxH pt=WxH@s fps=N drawable=WxH" ("na" for missing).
    public var summary: String {
        guard case let .connected(r) = self else { return "disconnected" }
        let native: String = Self.pair(r.nativeWidth, r.nativeHeight, separator: "x") ?? "na"
        let points: String = Self.pointPair(r, separator: "x") ?? "na"
        let scale: String = r.scale.map { (s: Double) -> String in Self.decimal(s, places: 2, trim: true) } ?? "na"
        let fps: String = r.maximumFramesPerSecond.map { (n: Int) -> String in String(n) } ?? "na"
        let drawable: String = Self.pair(r.drawableWidth, r.drawableHeight, separator: "x") ?? "na"
        return "connected native=" + native + " pt=" + points + "@" + scale + " fps=" + fps + " drawable=" + drawable
    }

    // MARK: - Formatting

    private static func rows(_ r: OutputReadings) -> [OutputDiagnosticsRow] {
        let na: String = notAvailable
        let native: String = pair(r.nativeWidth, r.nativeHeight).map { (s: String) -> String in s + " px" } ?? na
        let drawable: String = pair(r.drawableWidth, r.drawableHeight).map { (s: String) -> String in s + " px" } ?? na
        let refresh: String = r.maximumFramesPerSecond.map { (n: Int) -> String in String(n) + " Hz" } ?? na
        let aspect: String = r.pixelAspect.map { (p: Double) -> String in decimal(p, places: 2, trim: false) } ?? na
        return [
            OutputDiagnosticsRow(id: "nativeResolution", title: "Native resolution", value: native),
            OutputDiagnosticsRow(id: "size", title: "Size", value: sizeText(r)),
            OutputDiagnosticsRow(id: "refreshRate", title: "Refresh rate", value: refresh),
            OutputDiagnosticsRow(id: "gamut", title: "Color gamut", value: gamutText(r.gamut)),
            OutputDiagnosticsRow(id: "edr", title: "EDR headroom", value: edrText(r)),
            OutputDiagnosticsRow(id: "mirroring", title: "Mirroring", value: mirroringText(r.mirrored)),
            OutputDiagnosticsRow(id: "drawable", title: "Drawable", value: drawable),
            OutputDiagnosticsRow(id: "overscan", title: "Overscan", value: overscanText(r.overscan)),
            OutputDiagnosticsRow(id: "pixelAspect", title: "Pixel aspect", value: aspect),
            OutputDiagnosticsRow(id: "outputMode", title: "Output", value: r.outputMode ?? na),
        ]
    }

    private static func pair(_ w: Int?, _ h: Int?, separator: String = " × ") -> String? {
        guard let w, let h else { return nil }
        return String(w) + separator + String(h)
    }

    private static func pointPair(_ r: OutputReadings, separator: String = " × ") -> String? {
        guard let w = r.pointWidth, let h = r.pointHeight else { return nil }
        return decimal(w, places: 1, trim: true) + separator + decimal(h, places: 1, trim: true)
    }

    /// "1920 × 1080 pt @1x"; the scale alone, or the size alone, when only one is reported.
    private static func sizeText(_ r: OutputReadings) -> String {
        let points: String? = pointPair(r).map { (s: String) -> String in s + " pt" }
        let scale: String? = r.scale.map { (s: Double) -> String in "@" + decimal(s, places: 2, trim: true) + "x" }
        switch (points, scale) {
        case let (p?, s?): return p + " " + s
        case let (p?, nil): return p
        case let (nil, s?): return s
        case (nil, nil): return notAvailable
        }
    }

    private static func gamutText(_ gamut: OutputReadings.Gamut?) -> String {
        switch gamut {
        case .sRGB?: return "sRGB"
        case .displayP3?: return "Display P3"
        case nil: return notAvailable
        }
    }

    private static func edrText(_ r: OutputReadings) -> String {
        let potential: String = r.potentialEDRHeadroom.map { (h: Double) -> String in decimal(h, places: 1, trim: false) + "×" } ?? notAvailable
        let current: String = r.currentEDRHeadroom.map { (h: Double) -> String in decimal(h, places: 1, trim: false) + "×" } ?? notAvailable
        if r.potentialEDRHeadroom == nil, r.currentEDRHeadroom == nil { return notAvailable }
        return potential + " potential, " + current + " current"
    }

    private static func mirroringText(_ mirrored: Bool?) -> String {
        guard let mirrored else { return notAvailable }
        return mirrored ? "Mirrored" : "Extended"
    }

    private static func overscanText(_ overscan: OutputReadings.Overscan?) -> String {
        switch overscan {
        case .scale?: return "Scale"
        case .insetBounds?: return "Inset bounds"
        case .off?: return "None"
        case nil: return notAvailable
        }
    }

    /// Locale-independent decimal ("1.5", "2", "1.00"): `places` digits, trailing zeros dropped when `trim`.
    static func decimal(_ value: Double, places: Int, trim: Bool) -> String {
        var factor: Double = 1
        for _ in 0..<places { factor *= 10 }
        let scaled: Double = (value * factor).rounded()
        let whole: Int = Int(scaled / factor)
        let fractionValue: Int = abs(Int(scaled) - whole * Int(factor))
        guard places > 0 else { return String(whole) }
        var fraction: String = String(fractionValue)
        while fraction.count < places { fraction = "0" + fraction }
        if trim {
            while fraction.hasSuffix("0") { fraction.removeLast() }
            if fraction.isEmpty { return String(whole) }
        }
        return String(whole) + "." + fraction
    }
}
