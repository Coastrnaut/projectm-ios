// PresetImportLimits.swift — the limits an imported preset must stay within (PRE-012-R3, R8, R10,
// R15, R18, R27). Each was set from measurements of the 14,604 `.milk` files built into the app
// (spec Clarifications, research D2); the largest built-in value is in the comment.
import Foundation

public enum PresetImportLimits {
    /// 512 KiB. Largest built-in preset: 168,391 bytes. The engine refuses files over 1 MiB.
    public static let maxFileBytes = 524_288
    /// Longest built-in line: 1,525 bytes.
    public static let maxLineBytes = 8_192
    /// Most lines in a built-in preset: 3,220.
    public static let maxLines = 20_000
    /// Largest built-in code block: 31,999 bytes.
    public static let maxBlockBytes = 131_072
    /// Longest built-in statement: 4,891 bytes (equations), 1,311 (shaders). Bounds the depth of
    /// the engine's recursion over one expression.
    public static let maxStatementBytes = 8_192
    /// Deepest built-in bracket nesting: 21.
    public static let maxNestingDepth = 64

    public static let maxLicenseLines = 5
    public static let maxLicenseLineCharacters = 200
    public static let maxWarnings = 50
    public static let maxNameCharacters = 120
    public static let maxFileNameCharacters = 255
    public static let maxDetailCharacters = 300

    /// Waiting or playable presets (R27).
    public static let maxUserPresets = 1_000
    public static let maxQuarantined = 200
    public static let maxIndexBytes = 4 << 20

    /// R15: a trial that has not finished by then is abandoned and the preset quarantined.
    public static let trialTimeout: Duration = .seconds(10)
    /// R14: frames the trial draws after loading the preset.
    public static let trialFrames = 30
    /// R18: how long a preset must draw on the visible renderer before it counts as proven.
    public static let provingPeriod: Duration = .seconds(3)

    /// "8,192": the same on every platform and locale.
    public static func grouped(_ value: Int) -> String {
        var digits = Array(String(value))
        var index = digits.count - 3
        while index > 0 {
            digits.insert(",", at: index)
            index -= 3
        }
        return String(digits)
    }
}
