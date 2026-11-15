// ClockOverlay.swift — the clock overlay's time, format and settings (MED-011-R2, R3, R5, R8; research
// MED-011-D2, D3, D5; contracts/clock-overlay.md C1, C2). Plain Swift, every platform.
//
// * `ClockSource` gives the date and the time zone to show it in. The app's `SystemClockSource` reads the
//   device's wall clock and `TimeZone.current` (no network time); tests inject `FixedClockSource`.
// * `ClockFormatter` formats with a fixed `DateFormatter` pattern (`HH:mm`, `HH:mm:ss`, `h:mm a`, `h:mm:ss a`)
//   and an injected locale and time zone, so a fixed date gives byte-identical strings.
// * `ClockText` reports a string only when it differs from the last one; the MED-009 text layer is given a new
//   spec only then, so it rasterizes once per change and stays cached (CMP-013) in between.
// * `ClockSchedule` gives the delay to the next whole second (updates at most once per second, aligned).
// * `ClockOverlaySettings` is stored as JSON with `"version": 1`; the style is a `TextOverlaySpec` whose message
//   is ignored (stored empty).
import Foundation

/// Where the clock's time comes from (MED-011-R2).
public protocol ClockSource: Sendable {
    var now: Date { get }
    var timeZone: TimeZone { get }
}

/// The device's wall clock in its current time zone.
public struct SystemClockSource: ClockSource {
    public init() {}
    public var now: Date { Date() }
    public var timeZone: TimeZone { TimeZone.current }
}

/// A fixed date and time zone (tests, the DEBUG fixture).
public struct FixedClockSource: ClockSource {
    public var now: Date
    public var timeZone: TimeZone

    public init(now: Date, timeZone: TimeZone) {
        self.now = now
        self.timeZone = timeZone
    }
}

public enum ClockHourCycle: String, CaseIterable, Codable, Sendable {
    case twentyFourHour, twelveHour

    public var title: String {
        switch self {
        case .twentyFourHour: "24-hour"
        case .twelveHour: "12-hour"
        }
    }

    /// The `DateFormatter` pattern (research MED-011-D3).
    public func pattern(showsSeconds: Bool) -> String {
        switch (self, showsSeconds) {
        case (.twentyFourHour, false): "HH:mm"
        case (.twentyFourHour, true): "HH:mm:ss"
        case (.twelveHour, false): "h:mm a"
        case (.twelveHour, true): "h:mm:ss a"
        }
    }
}

/// Formats dates for the clock (contract C1). Not Sendable: one owner (the app's main actor, or a test).
public final class ClockFormatter {
    public let pattern: String
    private let formatter: DateFormatter

    public init(hourCycle: ClockHourCycle, showsSeconds: Bool, locale: Locale, timeZone: TimeZone) {
        pattern = hourCycle.pattern(showsSeconds: showsSeconds)
        formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
    }

    public var timeZone: TimeZone {
        get { formatter.timeZone }
        set { if newValue != formatter.timeZone { formatter.timeZone = newValue } }
    }

    public func string(for date: Date) -> String { formatter.string(from: date) }
}

/// An overlay's string, reported only when it changes (MED-011 contract C2; shared with MED-012's countdown). The
/// text layer is given a new spec only for a reported string, so it rasterizes once per change.
public struct ChangedText: Equatable, Sendable {
    public private(set) var current: String?

    public init() {}

    /// `next` when it differs from the last string reported; nil otherwise.
    public mutating func report(_ next: String) -> String? {
        guard next != current else { return nil }
        current = next
        return next
    }

    /// Forgets the last string, so the next one is always reported (a new style or format).
    public mutating func clear() { current = nil }
}

/// The clock's string, reported only when it changes (contract C2).
public final class ClockText {
    public let formatter: ClockFormatter
    private var text = ChangedText()
    public var current: String? { text.current }

    public init(formatter: ClockFormatter) {
        self.formatter = formatter
    }

    /// The string for `date` in `timeZone` when it differs from the last one reported; nil otherwise.
    public func update(at date: Date, timeZone: TimeZone) -> String? {
        formatter.timeZone = timeZone
        return text.report(formatter.string(for: date))
    }
}

public enum ClockSchedule {
    /// Seconds from `date` to the next whole second (0 < delay ≤ 1).
    public static func delay(after date: Date) -> TimeInterval {
        let t = date.timeIntervalSince1970
        let next = (t + 1e-6).rounded(.down) + 1
        return min(max(next - t, 0.001), 1)
    }
}

/// The clock's settings (data-model "ClockOverlaySettings").
public struct ClockOverlaySettings: Equatable, Sendable {
    public static let currentVersion = 1
    /// Top trailing, 6 % of the picture height, white bold Menlo (fixed-width digits) with the default outline.
    public static let defaultStyle = TextOverlaySpec(font: .menlo, weight: .bold, size: 0.06, alignment: .trailing,
                                                     verticalPosition: .top)
    public static let `default` = ClockOverlaySettings()

    public var isShown: Bool
    public var hourCycle: ClockHourCycle
    public var showsSeconds: Bool
    /// Placement and look; the message is always empty here.
    public var style: TextOverlaySpec {
        didSet { if !style.message.isEmpty { style.setMessage("") } }
    }

    public init(isShown: Bool = false, hourCycle: ClockHourCycle = .twentyFourHour, showsSeconds: Bool = false,
                style: TextOverlaySpec = ClockOverlaySettings.defaultStyle) {
        self.isShown = isShown
        self.hourCycle = hourCycle
        self.showsSeconds = showsSeconds
        var clean = style
        clean.setMessage("")
        self.style = clean
    }

    /// What the text layer draws for `text`: the style with the time as its message (empty when hidden).
    public func spec(for text: String?) -> TextOverlaySpec {
        var spec = style
        spec.setMessage(isShown ? (text ?? "") : "")
        return spec
    }

    public func makeFormatter(locale: Locale, timeZone: TimeZone) -> ClockFormatter {
        ClockFormatter(hourCycle: hourCycle, showsSeconds: showsSeconds, locale: locale, timeZone: timeZone)
    }
}

/// What a stored overlay setting reads as (MED-011, shared with MED-012).
public enum StoredOverlayDecodeResult<Settings: Sendable>: Sendable {
    case settings(Settings)
    /// Written by a newer app version: not used, left untouched.
    case unsupportedVersion(Int)
    /// Not readable: the defaults are used and the app removes the value.
    case damaged
}

extension StoredOverlayDecodeResult: Equatable where Settings: Equatable {}

public enum StoredOverlayCodec {
    private struct VersionProbe: Decodable { let version: Int }

    /// JSON with sorted keys (the value writes its own `"version"`).
    public static func encode<S: Encodable>(_ value: S) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(value)) ?? Data()
    }

    /// Reads `data` written with `"version": currentVersion`.
    public static func decode<S: Decodable & Sendable>(_ type: S.Type, from data: Data, currentVersion: Int) -> StoredOverlayDecodeResult<S> {
        let decoder = JSONDecoder()
        guard let probe = try? decoder.decode(VersionProbe.self, from: data) else { return .damaged }
        guard probe.version == currentVersion else { return .unsupportedVersion(probe.version) }
        guard let value = try? decoder.decode(S.self, from: data) else { return .damaged }
        return .settings(value)
    }
}

/// What a stored clock value reads as.
public typealias ClockOverlayDecodeResult = StoredOverlayDecodeResult<ClockOverlaySettings>

extension ClockOverlaySettings: Codable {
    enum CodingKeys: String, CodingKey {
        case version, isShown, hourCycle, showsSeconds, style
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.currentVersion, forKey: .version)
        try c.encode(isShown, forKey: .isShown)
        try c.encode(hourCycle, forKey: .hourCycle)
        try c.encode(showsSeconds, forKey: .showsSeconds)
        try c.encode(style, forKey: .style)
    }

    /// Version 1; an unknown hour cycle reads as the default. Callers go through `decodeStored`.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ClockOverlaySettings.default
        let cycle: ClockHourCycle = try c.decodeIfPresent(String.self, forKey: .hourCycle).flatMap(ClockHourCycle.init(rawValue:)) ?? d.hourCycle
        self.init(isShown: try c.decodeIfPresent(Bool.self, forKey: .isShown) ?? d.isShown,
                  hourCycle: cycle,
                  showsSeconds: try c.decodeIfPresent(Bool.self, forKey: .showsSeconds) ?? d.showsSeconds,
                  style: try c.decodeIfPresent(TextOverlaySpec.self, forKey: .style) ?? d.style)
    }

    /// JSON with sorted keys and `"version": 1`.
    public func encodedForStorage() -> Data { StoredOverlayCodec.encode(self) }

    public static func decodeStored(_ data: Data) -> ClockOverlayDecodeResult {
        StoredOverlayCodec.decode(ClockOverlaySettings.self, from: data, currentVersion: currentVersion)
    }
}
