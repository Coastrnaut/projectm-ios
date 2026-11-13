// EffectChainDescription.swift — a versioned, serializable description of an ordered effect chain,
// the format FX-020 will store in scene documents (FX-001-R2; research FX-001-D6; ADR-0010
// decision 3).
//
// JSON: {"formatVersion": 1, "effects": [{"id": "fx.bloom", "parameters": {…}}]}. Effect ids are
// stable and never reused. Unknown ids are kept (as `.unknown`) and skipped when a chain is built,
// so a document written by a newer app still opens; a newer format version or more than 16 effects
// fails decoding.

/// A stable effect identifier.
public struct EffectIdentifier: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// FX-001.
    public static let bloom = EffectIdentifier(rawValue: "fx.bloom")

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

/// One entry of a chain.
public enum EffectDescription: Sendable, Equatable, Codable {
    case bloom(BloomParameters)
    /// An effect this version does not know; kept, never run.
    case unknown(EffectIdentifier)

    public var identifier: EffectIdentifier {
        switch self {
        case .bloom: .bloom
        case .unknown(let id): id
        }
    }

    /// A known effect that changes the picture.
    public var isActive: Bool {
        switch self {
        case .bloom(let p): !p.isPassThrough
        case .unknown: false
        }
    }

    private enum CodingKeys: String, CodingKey { case id, parameters }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(EffectIdentifier.self, forKey: .id)
        switch id {
        case .bloom: self = .bloom(try c.decodeIfPresent(BloomParameters.self, forKey: .parameters) ?? BloomParameters())
        default: self = .unknown(id)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(identifier, forKey: .id)
        switch self {
        case .bloom(let p): try c.encode(p, forKey: .parameters)
        case .unknown: break
        }
    }
}

public enum EffectChainDescriptionError: Error, Equatable, Sendable {
    case unsupportedVersion(Int)
    case tooManyEffects(Int)
}

/// An ordered chain of effects.
public struct EffectChainDescription: Sendable, Equatable, Codable {
    public static let currentFormatVersion = 1
    public static let maximumEffectCount = 16

    public var formatVersion: Int
    public var effects: [EffectDescription]

    public init(effects: [EffectDescription] = []) {
        formatVersion = Self.currentFormatVersion
        self.effects = effects
    }

    /// The known, non-pass-through entries, in order.
    public var activeEffects: [EffectDescription] { effects.filter(\.isActive) }

    private enum CodingKeys: String, CodingKey { case formatVersion, effects }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decode(Int.self, forKey: .formatVersion)
        guard version <= Self.currentFormatVersion, version >= 1 else { throw EffectChainDescriptionError.unsupportedVersion(version) }
        let effects = try c.decode([EffectDescription].self, forKey: .effects)
        guard effects.count <= Self.maximumEffectCount else { throw EffectChainDescriptionError.tooManyEffects(effects.count) }
        formatVersion = version
        self.effects = effects
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(formatVersion, forKey: .formatVersion)
        try c.encode(effects, forKey: .effects)
    }
}
