// ShowCueNote.swift — SHOW-012 private operator notes on cues (specs/285-show-012-cue-annotations; R1; research D3;
// contract show-cue-note.md).
//
// A note is plain text: line breaks are kept (CR LF, CR, U+2028 and U+2029 become one line feed), every other control
// character (Unicode general category Cc: tab, NUL, ESC, DEL, C1) is removed, leading and trailing whitespace and blank
// lines are trimmed, and it holds at most 500 characters as the user sees them (grapheme clusters). Empty text is no
// note. Notes are operator-only: no output, HUD, OSC, caption, announcement, diagnostics or report source may name them
// (SHOW-012-R9, R11; enforced by scripts/check_compliance.py). Foundation only (builds on Linux).
import Foundation

public enum ShowCueNote {
    public static let maximumCharacters = 500

    /// The text with line separators unified, control characters other than line feed removed, and trimmed.
    public static func cleaned(_ text: String) -> String {
        let unified: String = text.replacingOccurrences(of: "\r\n", with: "\n")
        var scalars = String.UnicodeScalarView()
        for scalar in unified.unicodeScalars {
            switch scalar.value {
            case 0x0D, 0x2028, 0x2029: scalars.append("\n")
            case 0x0A: scalars.append(scalar)
            default:
                if scalar.properties.generalCategory == .control { continue }
                scalars.append(scalar)
            }
        }
        return String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The stored form of an edited note: nil when empty after cleaning or longer than `maximumCharacters`.
    public static func normalized(_ text: String) -> String? {
        let clean: String = cleaned(text)
        guard !clean.isEmpty, clean.count <= maximumCharacters else { return nil }
        return clean
    }

    /// The stored form of a note read from a file (contract N2): cleaned and cut to `maximumCharacters`; nil when empty.
    public static func stored(_ text: String) -> String? {
        var clean: String = cleaned(text)
        if clean.count > maximumCharacters {
            clean = String(clean.prefix(maximumCharacters)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return clean.isEmpty ? nil : clean
    }

    /// The editor row's preview: the first line, at most 60 characters, "…" when anything was left out.
    public static func preview(_ note: String, limit: Int = 60) -> String {
        let firstLine: Substring = note.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first ?? ""
        let line: String = String(firstLine)
        let more: Bool = line.count > limit || line.count < note.count
        let shown: String = line.count > limit ? String(line.prefix(limit)) : line
        return more ? shown + "…" : shown
    }
}
