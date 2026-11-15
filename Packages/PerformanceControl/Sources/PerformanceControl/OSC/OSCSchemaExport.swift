// OSCSchemaExport.swift — the OSC route schema as a Markdown document (OSC-010-R2 to R5;
// specs/282-osc-010-osc-schema-export, contracts/osc-schema-export.md C1).
//
// * One row per route of the OSC-003 table, in table order: address, parameter ID, display name, arguments, input
//   range, value range, unit, origin and whether the route is on. Ranges come from the parameter's MOD-001
//   descriptor (the same descriptors SHD-003 metadata produces).
// * The header carries the app version and the export time in UTC from an injected instant, so the same inputs
//   always give the same bytes (no time zone, no locale).
// * Privacy by construction (OSC-010-R5): the inputs are the route table, the disabled addresses, descriptors, a
//   name function, the version and the instant. No settings store, peer, port, send destination or received value
//   is ever an input, so none can appear in the file.
// Pure Swift, Foundation-free, Linux-testable.
import ParameterGraph

/// One documented route (data-model.md).
public struct OSCSchemaRow: Sendable, Hashable {
    public let address: String
    public let parameterID: String
    public let displayName: String
    public let arguments: String
    public let inputRange: String
    public let valueRange: String
    public let unit: String
    public let origin: String
    public let isEnabled: Bool

    public init(address: String, parameterID: String, displayName: String, arguments: String, inputRange: String,
                valueRange: String, unit: String, origin: String, isEnabled: Bool) {
        self.address = address
        self.parameterID = parameterID
        self.displayName = displayName
        self.arguments = arguments
        self.inputRange = inputRange
        self.valueRange = valueRange
        self.unit = unit
        self.origin = origin
        self.isEnabled = isEnabled
    }

    /// The table cells in column order.
    public var cells: [String] {
        [address, parameterID, displayName, arguments, inputRange, valueRange, unit, origin, isEnabled ? "on" : "off"]
    }
}

public enum OSCSchemaExport {
    public static let title = "# projectM-iOS OSC routes"
    public static let columns: [String] = ["Address", "Parameter ID", "Name", "Arguments", "Input", "Value range", "Unit",
                                           "Origin", "Enabled"]
    public static let arguments = "one number (f, i, h or d)"
    public static let unknown = "unknown"

    // MARK: Rows

    /// One row per route in `table`, in table order. `descriptors` must include every target (the test value's
    /// descriptor too); a missing one gives `unknown` ranges.
    public static func rows(table: [OSCParameterRoute], disabled: Set<String>, descriptors: [ParameterDescriptor],
                            displayName: (ParameterID) -> String) -> [OSCSchemaRow] {
        var byID: [ParameterID: ParameterDescriptor] = [:]
        for descriptor in descriptors { byID[descriptor.id] = descriptor }
        return table.map { (route: OSCParameterRoute) -> OSCSchemaRow in
            row(route, descriptor: byID[route.parameter], name: displayName(route.parameter),
                enabled: !disabled.contains(route.address))
        }
    }

    static func row(_ route: OSCParameterRoute, descriptor: ParameterDescriptor?, name: String, enabled: Bool) -> OSCSchemaRow {
        let valueRange: String = descriptor.map(rangeText) ?? unknown
        let input: String
        switch route.scale {
        case .normalized: input = "0…1, mapped linearly"
        case .raw: input = valueRange + ", raw"
        }
        let unit: String = descriptor.map { (d: ParameterDescriptor) -> String in unitText(d.unit) } ?? unknown
        return OSCSchemaRow(address: route.address, parameterID: route.parameter.rawValue, displayName: name,
                            arguments: arguments, inputRange: input, valueRange: valueRange, unit: unit,
                            origin: originText(route.origin), isEnabled: enabled)
    }

    /// `min…max` for continuous and integer parameters; `unknown` for other kinds (never routable).
    public static func rangeText(_ descriptor: ParameterDescriptor) -> String {
        switch descriptor.kind {
        case let .continuous(minimum, maximum, _, _, _):
            return number(minimum) + "…" + number(maximum)
        case let .integer(minimum, maximum, _, _):
            return String(minimum) + "…" + String(maximum)
        default:
            return unknown
        }
    }

    public static func unitText(_ unit: ParameterUnit) -> String {
        switch unit {
        case .none: return "none"
        case .normalized: return "fraction 0-1"
        case .fractionOfOutput: return "fraction of output"
        case .seconds: return "seconds"
        case .perSecond: return "per second"
        case .degrees: return "degrees"
        case .count: return "count"
        }
    }

    public static func originText(_ origin: OSCRouteOrigin) -> String {
        switch origin {
        case .test: return "test"
        case .standard: return "standard"
        case .builtInAlias: return "built-in alias"
        case .userAlias: return "your alias"
        }
    }

    /// Shortest round-trip form, whole numbers without a fraction (`2`, `0.25`); locale-independent.
    public static func number(_ value: Double) -> String {
        if value.isFinite, value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        return String(value)
    }

    // MARK: Document

    /// The Markdown document: header, then the table. LF line endings, ends with a newline.
    public static func document(rows: [OSCSchemaRow], appVersion: String, exportedAt secondsSince1970: Int64) -> String {
        var lines: [String] = [
            title,
            "",
            "- App version: " + cell(appVersion),
            "- Exported: " + utcStamp(secondsSince1970),
            "- Routes: " + String(rows.count),
            "",
            "Send one number to an address. Standard routes and aliases take a position from 0 to 1, clamped, and map it "
                + "linearly over the value range. The test route takes the value itself. Addresses not listed here, "
                + "and routes that are off, are ignored.",
            "",
        ]
        lines.append(tableLine(columns))
        lines.append(tableLine(columns.map { (_: String) -> String in "---" }))
        for row in rows { lines.append(tableLine(row.cells.map(cell))) }
        return lines.joined(separator: "\n") + "\n"
    }

    static func tableLine(_ cells: [String]) -> String { "| " + cells.joined(separator: " | ") + " |" }

    /// A table cell: `|` escaped, line breaks as spaces.
    public static func cell(_ text: String) -> String {
        var out: String = ""
        for character in text {
            switch character {
            case "|": out += "\\|"
            case "\n", "\r", "\r\n": out += " "
            default: out.append(character)
            }
        }
        return out
    }

    // MARK: Time

    /// `projectM-osc-routes-YYYYMMDD-hhmmssZ.md`.
    public static func fileName(exportedAt secondsSince1970: Int64) -> String {
        let t: UTCTime = UTCTime(secondsSince1970)
        return "projectM-osc-routes-" + pad(t.year, 4) + pad(t.month, 2) + pad(t.day, 2) + "-" + pad(t.hour, 2)
            + pad(t.minute, 2) + pad(t.second, 2) + "Z.md"
    }

    /// `YYYY-MM-DDThh:mm:ssZ`.
    public static func utcStamp(_ secondsSince1970: Int64) -> String {
        let t: UTCTime = UTCTime(secondsSince1970)
        let date: String = pad(t.year, 4) + "-" + pad(t.month, 2) + "-" + pad(t.day, 2)
        return date + "T" + pad(t.hour, 2) + ":" + pad(t.minute, 2) + ":" + pad(t.second, 2) + "Z"
    }

    static func pad(_ value: Int64, _ width: Int) -> String {
        let text: String = String(value)
        return text.count >= width ? text : String(repeating: "0", count: width - text.count) + text
    }
}

/// A UTC calendar time from seconds since 1970 (days-to-civil, proleptic Gregorian).
struct UTCTime {
    let year: Int64, month: Int64, day: Int64, hour: Int64, minute: Int64, second: Int64

    init(_ secondsSince1970: Int64) {
        var days: Int64 = secondsSince1970 / 86_400
        var rest: Int64 = secondsSince1970 % 86_400
        if rest < 0 {
            rest += 86_400
            days -= 1
        }
        hour = rest / 3_600
        minute = (rest % 3_600) / 60
        second = rest % 60
        let z: Int64 = days + 719_468
        let era: Int64 = (z >= 0 ? z : z - 146_096) / 146_097
        let doe: Int64 = z - era * 146_097
        let yoe: Int64 = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365
        let doy: Int64 = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp: Int64 = (5 * doy + 2) / 153
        day = doy - (153 * mp + 2) / 5 + 1
        month = mp < 10 ? mp + 3 : mp - 9
        year = yoe + era * 400 + (month <= 2 ? 1 : 0)
    }
}
