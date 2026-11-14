// SceneVideoLoop.swift — a video asset's loop region in a scene (MED-003-R8; research MED-003-D6).
//
// Stored as the optional object `loop` on a `video` asset:
// `{"inMilliseconds": <integer ≥ 0>, "outMilliseconds": <integer > in>}`. Assets keep unknown fields
// verbatim (`SceneAsset.extra`), so apps without MED-003 carry the field through load and save
// unchanged; there is no decoder, encoder or version change (the CMP-006 optional-field rule). Absent
// means the whole file; a malformed value (not an object, missing or non-integer keys, negative,
// out ≤ in) reads as the whole file. Only `video` assets have a loop.

public struct SceneVideoLoop: Sendable, Hashable {
    public var inMilliseconds: Int
    public var outMilliseconds: Int

    public init(inMilliseconds: Int, outMilliseconds: Int) {
        self.inMilliseconds = inMilliseconds
        self.outMilliseconds = outMilliseconds
    }

    public static let key = "loop"
    static let inKey = "inMilliseconds"
    static let outKey = "outMilliseconds"

    /// The value read from JSON, or nil when malformed.
    public init?(json: SceneJSON) {
        guard let o = json.objectValue, o.count == 2,
              let start = o[Self.inKey].flatMap({ (v: SceneJSON) -> Int64? in Self.integer(v) }),
              let end = o[Self.outKey].flatMap({ (v: SceneJSON) -> Int64? in Self.integer(v) }),
              start >= 0, end > start, end <= Int64(Int32.max) else { return nil }
        self.init(inMilliseconds: Int(start), outMilliseconds: Int(end))
    }

    public var json: SceneJSON {
        .object([Self.inKey: .integer(Int64(inMilliseconds)), Self.outKey: .integer(Int64(outMilliseconds))])
    }

    private static func integer(_ value: SceneJSON) -> Int64? {
        guard case let .number(n) = value else { return nil }
        return n.int64Value
    }
}

extension SceneAsset {
    /// MED-003: the loop region of a `video` asset (nil: the whole file, also for other kinds and a
    /// malformed value). Setting nil removes the field; setting a value on another kind does nothing.
    public var videoLoop: SceneVideoLoop? {
        get {
            guard case .video = kind, let value = extra[SceneVideoLoop.key] else { return nil }
            return SceneVideoLoop(json: value)
        }
        set {
            guard case .video = kind else { return }
            extra[SceneVideoLoop.key] = newValue?.json
        }
    }
}

// MED-004-R7 (research MED-004-D6): a video asset's playback speed is the optional integer field
// `speedPercent`, written only when the speed is not 1×. Carried verbatim by apps without MED-004
// (`SceneAsset.extra`); no version change. SceneFormat accepts any integer in 1…Int32.max; the app
// accepts only its safe set and reads anything else as 1×.
extension SceneAsset {
    public static let videoSpeedKey = "speedPercent"

    /// MED-004: the speed of a `video` asset in percent (nil: 1×, also for other kinds and a malformed
    /// value). Setting nil removes the field; setting a value on another kind does nothing.
    public var videoSpeedPercent: Int? {
        get {
            guard case .video = kind, let value = extra[Self.videoSpeedKey], case let .number(n) = value,
                  let integer = n.int64Value, integer >= 1, integer <= Int64(Int32.max) else { return nil }
            return Int(integer)
        }
        set {
            guard case .video = kind else { return }
            extra[Self.videoSpeedKey] = newValue.map { (p: Int) -> SceneJSON in .integer(Int64(p)) }
        }
    }
}
