// SceneSlideshow.swift — a photo asset's image slideshow in a scene (MED-006-R12; research MED-006-D7;
// contracts/slideshow.md C5).
//
// Stored as the optional object `slideshow` on a `photo` asset:
// `{"enabled": bool, "storeIDs": [canonical UUID, …], "mode": "time"|"beats", "seconds": int, "beats": int}`.
// Assets keep unknown fields verbatim (`SceneAsset.extra`), so apps without MED-006 carry the field
// through load and save unchanged; no decoder, encoder or version change (the optional-field rule of
// MED-003's `loop` and MED-004's `speedPercent`). A value that is not an object, has a wrong type or an
// unknown mode reads as absent. Identifiers that are not canonical are dropped and at most 20 are kept;
// the app clamps seconds and beats to its own ranges. Only `photo` assets have a slideshow.

public struct SceneSlideshow: Sendable, Hashable {
    public static let key = "slideshow"
    public static let maximumStoreIDs = 20
    public static let modes: Set<String> = ["time", "beats"]

    public var enabled: Bool
    public var storeIDs: [String]
    public var mode: String
    public var seconds: Int
    public var beats: Int

    public init(enabled: Bool, storeIDs: [String], mode: String, seconds: Int, beats: Int) {
        self.enabled = enabled
        self.storeIDs = Array(storeIDs.filter(SceneDocument.isCanonicalUUID).prefix(Self.maximumStoreIDs))
        self.mode = mode
        self.seconds = seconds
        self.beats = beats
    }

    /// The value read from JSON, or nil when malformed.
    public init?(json: SceneJSON) {
        guard let o = json.objectValue,
              case let .bool(enabled)? = o["enabled"],
              case let .array(list)? = o["storeIDs"],
              case let .string(mode)? = o["mode"], Self.modes.contains(mode),
              let seconds = o["seconds"].flatMap(Self.integer),
              let beats = o["beats"].flatMap(Self.integer) else { return nil }
        let ids: [String] = list.compactMap { (value: SceneJSON) -> String? in
            guard case let .string(text) = value else { return nil }
            return text
        }
        self.init(enabled: enabled, storeIDs: ids, mode: mode, seconds: seconds, beats: beats)
    }

    public var json: SceneJSON {
        let ids: [SceneJSON] = storeIDs.map { (id: String) -> SceneJSON in .string(id) }
        return .object(["enabled": .bool(enabled), "storeIDs": .array(ids), "mode": .string(mode),
                        "seconds": .integer(Int64(seconds)), "beats": .integer(Int64(beats))])
    }

    private static func integer(_ value: SceneJSON) -> Int? {
        guard case let .number(n) = value, let v = n.int64Value, v >= Int64(Int32.min), v <= Int64(Int32.max) else { return nil }
        return Int(v)
    }
}

extension SceneAsset {
    /// MED-006: the slideshow of a `photo` asset (nil: none, also for other kinds and a malformed value).
    /// Setting nil removes the field; setting a value on another kind does nothing.
    public var photoSlideshow: SceneSlideshow? {
        get {
            guard case .photo = kind, let value = extra[SceneSlideshow.key] else { return nil }
            return SceneSlideshow(json: value)
        }
        set {
            guard case .photo = kind else { return }
            extra[SceneSlideshow.key] = newValue?.json
        }
    }
}
