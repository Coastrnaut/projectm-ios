// SceneEffectChainPresets.swift — FX-020 named chain presets (FX-020-R10; research FX-020-D8;
// specs/142-fx-020-effect-chains/contracts/effect-chain.md E3).
//
// Canonical JSON `{"version": 1, "presets": [{"name": "…", "effects": [scene effect entries]}]}`, read with the scene
// reader's bounds. At most 32 presets; names are trimmed and 1…60 characters; a name that exists (compared without
// case) is replaced in place. Entries use the scene format, so unknown kinds survive in presets too. Plain Swift.

/// One named chain.
public struct EffectChainPreset: Sendable, Hashable {
    public var name: String
    public var effects: [SceneEffectEntry]

    public init(name: String, effects: [SceneEffectEntry]) {
        self.name = name
        self.effects = effects
    }
}

/// The saved presets, in the order first saved.
public struct EffectChainPresetList: Sendable, Hashable {
    public static let version = 1
    public static let maximumPresets = 32
    public static let maximumNameLength = 60

    public private(set) var presets: [EffectChainPreset]

    public init(presets: [EffectChainPreset] = []) { self.presets = presets }

    /// The trimmed name, or nil when it is empty or longer than 60 characters.
    public static func normalizedName(_ text: String) -> String? {
        let trimmed: String = String(text.drop { (c: Character) -> Bool in c.isWhitespace }.reversed().drop { (c: Character) -> Bool in
            c.isWhitespace
        }.reversed())
        guard !trimmed.isEmpty, trimmed.count <= maximumNameLength else { return nil }
        return trimmed
    }

    public func preset(named name: String) -> EffectChainPreset? {
        presets.first { (p: EffectChainPreset) -> Bool in p.name.lowercased() == name.lowercased() }
    }

    /// Saves `effects` under `name` (replacing a preset of that name); nil when the name is invalid or the list is full.
    public func saving(name: String, effects: [SceneEffectEntry]) -> EffectChainPresetList? {
        guard let clean = Self.normalizedName(name), effects.count <= SceneLimits.maximumEffects else { return nil }
        var list = presets
        let preset = EffectChainPreset(name: clean, effects: effects)
        if let i = list.firstIndex(where: { (p: EffectChainPreset) -> Bool in p.name.lowercased() == clean.lowercased() }) {
            list[i] = preset
        } else {
            guard list.count < Self.maximumPresets else { return nil }
            list.append(preset)
        }
        return EffectChainPresetList(presets: list)
    }

    public func removing(name: String) -> EffectChainPresetList {
        EffectChainPresetList(presets: presets.filter { (p: EffectChainPreset) -> Bool in p.name.lowercased() != name.lowercased() })
    }

    /// Canonical JSON bytes.
    public func encoded() -> [UInt8] {
        let items: [SceneJSON] = presets.map { (p: EffectChainPreset) -> SceneJSON in
            .object(["name": .string(p.name), "effects": .array(p.effects.map(\.json))])
        }
        let root: SceneJSON = .object(["version": .integer(Int64(Self.version)), "presets": .array(items)])
        return root.canonicalBytes
    }

    /// Reads `encoded()` output; nil for anything unreadable (another version, wrong types, bad names, too many).
    public static func decode(_ bytes: [UInt8]) -> EffectChainPresetList? {
        guard let root = try? SceneJSON.parse(bytes), let o = root.objectValue,
              o["version"]?.numberValue?.int64Value == Int64(version), let items = o["presets"]?.arrayValue,
              items.count <= maximumPresets else { return nil }
        var list = EffectChainPresetList()
        for (i, item) in items.enumerated() {
            guard let p = item.objectValue, let name = p["name"]?.stringValue, let entries = p["effects"]?.arrayValue,
                  entries.count <= SceneLimits.maximumEffects else { return nil }
            var effects: [SceneEffectEntry] = []
            for (k, entry) in entries.enumerated() {
                guard let decoded = try? SceneEffectEntry.decode(entry, path: "$.presets[\(i)].effects[\(k)]") else { return nil }
                effects.append(decoded)
            }
            guard let next = list.saving(name: name, effects: effects) else { return nil }
            list = next
        }
        return list
    }
}
