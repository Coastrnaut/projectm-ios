// PresetColorFamily.swift — roadmap PRE-004: the eleven named colour families a preset's thumbnail
// can show (spec PRE-004-R1; research PRE-004-D2). The declaration order is the fixed order of
// chips and of ties between equal shares. Names are what chips and VoiceOver say, never colour alone.
import Foundation

public enum PresetColorFamily: String, CaseIterable, Codable, Sendable, Hashable {
    case red, orange, yellow, green, cyan, blue, purple, pink, white, grey, black

    /// The spoken and shown name ("Red" … "Black").
    public var name: String {
        switch self {
        case .red: "Red"
        case .orange: "Orange"
        case .yellow: "Yellow"
        case .green: "Green"
        case .cyan: "Cyan"
        case .blue: "Blue"
        case .purple: "Purple"
        case .pink: "Pink"
        case .white: "White"
        case .grey: "Grey"
        case .black: "Black"
        }
    }

    /// The position in the fixed order (ties and chips).
    public var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}
