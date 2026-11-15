// ParticleEmitterChoice.swift — the stored Particle emitter editor state (SHD-007-R8; specs/271-shd-007-particle-
// emitter-editor, data-model.md, research SHD-007-D8).
//
// Whether the Particle Fountain uses the edited emitter, plus the emitter's settings. Stored by `AppSettings` as JSON
// under `settings.particleFountain.emitter`, absent at the defaults (off, default settings). Reading is lenient:
// damaged data reads as the defaults, a missing switch reads as off, settings are decoded field by field and clamped
// (`ParticleEmitterSettings`). Backed up and erased with Settings (FILE-005, FILE-011). Scenes do not store it (the
// fountain is no compositor layer, VIS-008-R11).
import Foundation
import VisualGenerators

struct ParticleEmitterChoice: Hashable, Sendable, Codable {
    static let key = "settings.particleFountain.emitter"

    var enabled: Bool
    var settings: ParticleEmitterSettings

    init(enabled: Bool = false, settings: ParticleEmitterSettings = ParticleEmitterSettings()) {
        self.enabled = enabled
        self.settings = settings.clamped()
    }

    /// What the fountain receives: the settings when the switch is on, else nil (VIS-008 unchanged).
    var effective: ParticleEmitterSettings? { enabled ? settings : nil }

    var isDefault: Bool { self == ParticleEmitterChoice() }

    private enum CodingKeys: String, CodingKey { case enabled, settings }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = ((try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? nil) ?? false
        settings = ((try? c.decodeIfPresent(ParticleEmitterSettings.self, forKey: .settings)) ?? nil) ?? ParticleEmitterSettings()
    }

    /// Lenient read of the stored value (see the header).
    static func load(_ data: Data?) -> ParticleEmitterChoice {
        guard let data, let choice = try? JSONDecoder().decode(ParticleEmitterChoice.self, from: data) else {
            return ParticleEmitterChoice()
        }
        return choice
    }

    /// The stored form (sorted keys); nil at the defaults (the key is removed).
    static func encode(_ choice: ParticleEmitterChoice) -> Data? {
        guard !choice.isDefault else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(choice)
    }
}
