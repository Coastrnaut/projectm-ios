// SceneKenBurns.swift — a photo asset's Ken Burns movement in a scene (MED-007-R10; research MED-007-D8;
// specs/251-med-007-ken-burns/contracts/ken-burns.md K3).
//
// Stored as the optional object `kenBurns` on a `photo` asset:
// `{"start": {"x", "y", "width", "height"}, "end": {…}, "durationMilliseconds": 2000…60000, "easing": "linear"|"easeInOut"}`.
// Assets keep unknown fields verbatim (`SceneAsset.extra`), so apps without MED-007 carry the field through load and
// save unchanged; no decoder, encoder or version change (the optional-field rule of MED-003's `loop` and MED-006's
// `slideshow`). Anything malformed (a rectangle outside the image, below 0.05, non-finite; a duration out of range or
// not an integer; an unknown easing; missing or extra keys) reads as absent. Only `photo` assets have a movement.
import Compositor

public enum SceneKenBurns {
    public static let key = "kenBurns"
    static let rectKeys: Set<String> = ["x", "y", "width", "height"]
    static let motionKeys: Set<String> = ["start", "end", "durationMilliseconds", "easing"]

    /// The movement read from JSON, or nil when malformed.
    public static func motion(_ json: SceneJSON) -> KenBurnsMotion? {
        guard let o = json.objectValue, Set(o.keys) == motionKeys,
              let start = o["start"].flatMap(rect), let end = o["end"].flatMap(rect),
              case let .number(n)? = o["durationMilliseconds"], let ms = n.int64Value,
              ms >= Int64(KenBurnsMotion.durationRangeMilliseconds.lowerBound),
              ms <= Int64(KenBurnsMotion.durationRangeMilliseconds.upperBound),
              case let .string(name)? = o["easing"], let easing = KenBurnsEasing(rawValue: name) else { return nil }
        return KenBurnsMotion(start: start, end: end, durationMilliseconds: Int(ms), easing: easing)
    }

    /// The movement's stored form.
    public static func json(_ motion: KenBurnsMotion) -> SceneJSON {
        .object(["start": json(motion.start), "end": json(motion.end),
                 "durationMilliseconds": .integer(Int64(motion.durationMilliseconds)), "easing": .string(motion.easing.rawValue)])
    }

    static func json(_ r: KenBurnsRect) -> SceneJSON {
        .object(["x": .double(r.x), "y": .double(r.y), "width": .double(r.width), "height": .double(r.height)])
    }

    static func rect(_ json: SceneJSON) -> KenBurnsRect? {
        guard let o = json.objectValue, Set(o.keys) == rectKeys,
              let x = o["x"]?.numberValue?.doubleValue, let y = o["y"]?.numberValue?.doubleValue,
              let w = o["width"]?.numberValue?.doubleValue, let h = o["height"]?.numberValue?.doubleValue else { return nil }
        return KenBurnsRect(validatingX: x, y: y, width: w, height: h)
    }
}

extension SceneAsset {
    /// MED-007: the Ken Burns movement of a `photo` asset (nil: none, also for other kinds and a malformed value).
    /// Setting nil removes the field; setting a value on another kind does nothing.
    public var photoKenBurns: KenBurnsMotion? {
        get {
            guard case .photo = kind, let value = extra[SceneKenBurns.key] else { return nil }
            return SceneKenBurns.motion(value)
        }
        set {
            guard case .photo = kind else { return }
            extra[SceneKenBurns.key] = newValue.map { (m: KenBurnsMotion) -> SceneJSON in SceneKenBurns.json(m) }
        }
    }
}
