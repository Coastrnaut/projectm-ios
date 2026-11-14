// SnapshotBatchNaming.swift — REC-002 file names for an image batch (specs/234-rec-002-image-batch-export; R5;
// contract B1; research REC-002-D6).
//
// * `safeName`: letters, marks and digits of any script, spaces, "-", "_", "(" and ")" are kept; path separators,
//   other punctuation, emoji, symbols and control characters each become "-"; runs of "-" or of spaces collapse to
//   one; leading and trailing spaces, "-" and "." are trimmed; at most 48 characters; an empty result is "Snapshot".
// * `fileNames`: `<NN>-<safe name>.png`, NN the 1-based position (two digits, more for 100+), with " (2)", " (3)"…
//   when a name is already used in the batch, compared ignoring case.
import Foundation

enum SnapshotBatchNaming {
    static let fallback = "Snapshot"
    static let maximumLength = 48
    static let fileExtension = "png"

    /// The snapshot name as a safe file-name part.
    static func safeName(_ name: String) -> String {
        var out = ""
        for character in name.precomposedStringWithCanonicalMapping {
            let next: Character = mapped(character)
            if next == "-" && out.last == "-" { continue }
            if next == " " && (out.last == " " || out.isEmpty) { continue }
            out.append(next)
        }
        var result: String = trimmed(out)
        if result.count > maximumLength { result = trimmed(String(result.prefix(maximumLength))) }
        return result.isEmpty ? fallback : result
    }

    /// One file name per name, in order.
    static func fileNames(_ names: [String]) -> [String] {
        let width: Int = max(2, String(names.count).count)
        var used: Set<String> = []
        var result: [String] = []
        for (offset, name) in names.enumerated() {
            let number: String = String(offset + 1)
            let padded: String = String(repeating: "0", count: max(0, width - number.count)) + number
            let base: String = padded + "-" + safeName(name)
            var candidate: String = base + "." + fileExtension
            var copy = 2
            while used.contains(candidate.lowercased()) {
                candidate = base + " (" + String(copy) + ")." + fileExtension
                copy += 1
            }
            used.insert(candidate.lowercased())
            result.append(candidate)
        }
        return result
    }

    private static func mapped(_ character: Character) -> Character {
        if character == "-" || character == "_" || character == "(" || character == ")" { return character }
        if character.isWhitespace { return " " }
        return isWordCharacter(character) ? character : "-"
    }

    /// Letters, marks and digits only; anything carrying an emoji scalar or a keycap is not.
    private static func isWordCharacter(_ character: Character) -> Bool {
        for scalar in character.unicodeScalars {
            if scalar.properties.isEmojiPresentation || scalar.value == 0xFE0F || scalar.value == 0x20E3 { return false }
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
                 .nonspacingMark, .spacingMark, .enclosingMark, .decimalNumber, .letterNumber, .otherNumber:
                continue
            default:
                return false
            }
        }
        return true
    }

    private static func trimmed(_ text: String) -> String {
        let edges: Set<Character> = [" ", "-", "."]
        var slice = Substring(text)
        while let first = slice.first, edges.contains(first) { slice = slice.dropFirst() }
        while let last = slice.last, edges.contains(last) { slice = slice.dropLast() }
        return String(slice)
    }
}
