// PresetEnergy.swift — roadmap PRE-005: how much a preset moves in its thumbnail run (spec PRE-005-R3;
// research PRE-005-D3). The declaration order is the fixed order of chips.
import Foundation

public enum PresetEnergy: String, CaseIterable, Codable, Sendable, Hashable {
    case calm, moderate, energetic

    /// The shown name ("Calm", "Moderate", "Energetic").
    public var name: String {
        switch self {
        case .calm: "Calm"
        case .moderate: "Moderate"
        case .energetic: "Energetic"
        }
    }

    /// What VoiceOver says for a chip (PRE-005-R10).
    public var spokenName: String { "\(name) motion" }

    /// The class of a motion score (thousandths of a brightness level, PresetMotionScore).
    public static func of(score: Int) -> PresetEnergy {
        if score < PresetMotionScore.moderateThreshold { return .calm }
        if score < PresetMotionScore.energeticThreshold { return .moderate }
        return .energetic
    }
}
