// TextSanitizer.swift — cleans a typed or stored message before it is stored or drawn (MED-009-R3,
// R4; research MED-009-D4). Plain Swift, every platform.
//
// 1. Unicode scalars: CR LF, CR, U+2028 (line separator) and U+2029 (paragraph separator) become LF;
//    tab becomes a space; every other control character (general category Cc) is removed. Format
//    characters (Cf: ZWJ, direction marks, ...) and variation selectors are kept: emoji sequences
//    and right-to-left text need them.
// 2. Characters (extended grapheme clusters, what the viewer sees as one character): at most 280;
//    the cut never splits a cluster (an emoji family or a letter with its combining marks).
// 3. Lines: at most 8; line breaks after the 8th line become spaces.

public enum TextSanitizer {
    public static let maximumCharacters = 280
    public static let maximumLines = 8

    /// The cleaned message and whether the character limit dropped anything.
    public static func clean(_ raw: String) -> (message: String, wasCut: Bool) {
        var scalars = String.UnicodeScalarView()
        var previousWasCR = false
        for scalar in raw.unicodeScalars {
            defer { previousWasCR = scalar == "\r" }
            switch scalar {
            case "\n":
                if previousWasCR { continue }   // CR LF: the CR already became LF
                scalars.append("\n")
            case "\r", "\u{2028}", "\u{2029}":
                scalars.append("\n")
            case "\t":
                scalars.append(" ")
            default:
                if scalar.properties.generalCategory == .control { continue }
                scalars.append(scalar)
            }
        }
        let cleaned = String(scalars)
        var result = ""
        var count = 0
        var lineBreaks = 0
        var wasCut = false
        for character in cleaned {
            if count == maximumCharacters {
                wasCut = true
                break
            }
            if character == "\n" {
                lineBreaks += 1
                result.append(lineBreaks < maximumLines ? "\n" : " ")
            } else {
                result.append(character)
            }
            count += 1
        }
        return (result, wasCut)
    }

    /// True when the message has nothing to draw (empty, or only spaces and line breaks).
    public static func isBlank(_ message: String) -> Bool {
        message.unicodeScalars.allSatisfy { $0.properties.isWhitespace }
    }
}
