// TextDirection.swift — the message's direction and the side each alignment means (MED-009-R6;
// research MED-009-D5). Plain Swift, every platform.
//
// The direction is that of the first strong letter of the whole message (Unicode's paragraph rule,
// UAX #9 P2, applied to the message as one unit; spec Clarifications). A scalar is strong when its
// general category is a letter; it is right to left when it lies in a right-to-left block. RLM
// (U+200F) and ALM (U+061C) count as right to left, LRM (U+200E) as left to right. No strong letter
// (digits, emoji, punctuation only) → left to right.

public enum TextDirection: Sendable, Equatable {
    case leftToRight
    case rightToLeft

    public static func of(_ message: String) -> TextDirection {
        for scalar in message.unicodeScalars {
            switch scalar.value {
            case 0x200F, 0x061C: return .rightToLeft
            case 0x200E: return .leftToRight
            default: break
            }
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter:
                return isRightToLeftBlock(scalar.value) ? .rightToLeft : .leftToRight
            default:
                continue
            }
        }
        return .leftToRight
    }

    /// Hebrew, Arabic, Syriac, Arabic Supplement, Thaana, N'Ko, Samaritan, Mandaic, Syriac
    /// Supplement, Arabic Extended-B/A, the Hebrew and Arabic presentation forms, and the
    /// supplementary right-to-left ranges.
    static func isRightToLeftBlock(_ v: UInt32) -> Bool {
        switch v {
        case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF, 0x10800...0x10FFF, 0x1E800...0x1EFFF: true
        default: false
        }
    }
}

/// Where lines sit horizontally in the text area.
public enum TextHorizontalSide: Sendable, Equatable {
    case left, center, right
}

extension TextAlignmentChoice {
    /// Leading is the start side of the message's direction, trailing the end side.
    public func side(for direction: TextDirection) -> TextHorizontalSide {
        switch (self, direction) {
        case (.center, _): .center
        case (.leading, .leftToRight), (.trailing, .rightToLeft): .left
        case (.leading, .rightToLeft), (.trailing, .leftToRight): .right
        }
    }
}
